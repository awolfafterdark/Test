#!/usr/bin/env python3
"""Embed PickerPatcher in a user-supplied, unencrypted iOS IPA on macOS.

The unsigned output requires an external signer. For a directly signed output,
provide a matching Apple identity, provisioning profile, and entitlements.
"""
import argparse
import datetime
import fnmatch
import hashlib
import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

LOAD_PATH = "@executable_path/Frameworks/PickerPatcherEmbedded.framework/PickerPatcherEmbedded"
MAX_UNPACKED = 8 * 1024**3


def run(*args):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise ValueError(f"{' '.join(map(str, args[:2]))} failed: {result.stderr.strip()}")
    return result.stdout


def inspect_zip(ipa):
    total = 0
    seen = set()
    with zipfile.ZipFile(ipa) as archive:
        for info in archive.infolist():
            path = PurePosixPath(info.filename)
            mode = info.external_attr >> 16
            if (path.is_absolute() or '..' in path.parts or '\\' in info.filename or
                    not path.parts or str(path) in seen or
                    stat.S_ISLNK(mode) or (stat.S_IFMT(mode) and
                    not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)))):
                raise ValueError(f"Unsafe IPA archive entry: {info.filename}")
            seen.add(str(path))
            if info.flag_bits & 1:
                raise ValueError("Encrypted ZIP entries are unsupported")
            total += info.file_size
            if total > MAX_UNPACKED:
                raise ValueError("IPA exceeds the 8 GiB unpacked safety limit")
            if info.file_size > 100 * 1024**2 and info.compress_size * 1000 < info.file_size:
                raise ValueError("IPA contains an extreme compression ratio")
        apps = sorted({p.parts[1] for i in archive.infolist()
                       if (p := PurePosixPath(i.filename)).parts[:1] == ('Payload',)
                       and len(p.parts) >= 3 and p.parts[1].endswith('.app')})
        if len(apps) != 1:
            raise ValueError(f"Expected one Payload/*.app; found {len(apps)}")
    free = min(shutil.disk_usage(ipa.parent).free,
               shutil.disk_usage(tempfile.gettempdir()).free)
    if free < total * 3 + 1024**3:
        raise ValueError("Need at least 3× unpacked IPA size plus 1 GiB free")
    return apps[0]


def encrypted_macho(executable):
    output = run('xcrun', 'otool', '-l', str(executable))
    inside = False
    for line in output.splitlines():
        line = line.strip()
        if line.startswith('cmd '):
            inside = line in ('cmd LC_ENCRYPTION_INFO', 'cmd LC_ENCRYPTION_INFO_64')
        elif inside and line.startswith('cryptid '):
            if int(line.split()[1], 0):
                return True
    return False


def validate_app(app):
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    name = info.get('CFBundleExecutable')
    bundle = info.get('CFBundleIdentifier')
    if not isinstance(name, str) or Path(name).name != name or not bundle:
        raise ValueError('Malformed main app Info.plist')
    binary = app / name
    if not binary.is_file():
        raise ValueError('Main app executable missing')
    arches = run('xcrun', 'lipo', '-archs', str(binary)).split()
    if 'arm64' not in arches or any(a not in ('arm64', 'arm64e') for a in arches):
        raise ValueError(f'Only arm64/arm64e iOS binaries supported: {arches}')
    if encrypted_macho(binary):
        raise ValueError('FairPlay-encrypted executable; provide an authorized unencrypted IPA')
    if any(app.rglob('*.appex')) or any(app.rglob('*.app')):
        raise ValueError('Nested apps/extensions need individual profiles; unsupported')
    if (app / 'Frameworks/PickerPatcherEmbedded.framework').exists():
        raise ValueError('IPA already contains PickerPatcherEmbedded.framework')
    return bundle, binary


def check_profile(profile, entitlements, bundle):
    decoded = subprocess.run(['security', 'cms', '-D', '-i', str(profile)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout
    provision = plistlib.loads(decoded)
    expiration = provision.get('ExpirationDate')
    if expiration and expiration.replace(tzinfo=datetime.timezone.utc) < datetime.datetime.now(datetime.timezone.utc):
        raise ValueError('Provisioning profile is expired')
    allowed = provision.get('Entitlements', {}).get('application-identifier', '')
    if '.' not in allowed or not fnmatch.fnmatchcase(bundle, allowed.split('.', 1)[1]):
        raise ValueError('Provisioning profile does not authorize the app bundle ID')
    with entitlements.open('rb') as stream:
        requested = plistlib.load(stream)
    requested_id = requested.get('application-identifier', '')
    if requested_id != allowed.split('.', 1)[0] + '.' + bundle:
        raise ValueError('Entitlements application-identifier does not match profile and bundle ID')


def sign_app(app, identity, profile, entitlements, bundle):
    check_profile(profile, entitlements, bundle)
    shutil.copy2(profile, app / 'embedded.mobileprovision')
    # Sign nested code before the containing app; do not use codesign --deep to sign.
    frameworks = app / 'Frameworks'
    if frameworks.exists():
        nested = list(frameworks.rglob('*.dylib')) + list(frameworks.rglob('*.framework'))
        for target in sorted(nested, key=lambda item: len(item.parts), reverse=True):
            run('codesign', '--force', '--sign', identity, '--timestamp=none', str(target))
    run('codesign', '--force', '--sign', identity, '--timestamp=none',
        '--generate-entitlement-der', '--entitlements', str(entitlements), str(app))
    run('codesign', '--verify', '--strict', '--deep', '--verbose=2', str(app))


def package_ipa(root, output):
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6,
                         allowZip64=True) as archive:
        for path in sorted(root.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(root).as_posix())


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', type=Path, required=True)
    parser.add_argument('--framework', type=Path, required=True)
    parser.add_argument('--injector', type=Path, required=True, help='Built Core/MachOInject.c tool')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--sign-identity', help='Apple signing identity in macOS keychain')
    parser.add_argument('--profile', type=Path, help='Matching embedded.mobileprovision')
    parser.add_argument('--entitlements', type=Path, help='Profile-authorized entitlements plist')
    args = parser.parse_args()
    signing = [args.sign_identity, args.profile, args.entitlements]
    if any(signing) and not all(signing):
        parser.error('Signing requires --sign-identity, --profile, and --entitlements together')
    ipa = args.ipa.resolve(strict=True)
    framework_source = args.framework.resolve(strict=True)
    injector = args.injector.resolve(strict=True)
    output = args.out.resolve()
    if output == ipa:
        parser.error('Output must differ from the original IPA')
    if not (framework_source / 'PickerPatcherEmbedded').is_file():
        parser.error('Built embedded framework executable is missing')
    app_name = inspect_zip(ipa)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='pickerpatcher-') as temporary:
        root = Path(temporary)
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(root)
            # zipfile.extractall does not restore POSIX executable bits.
            for info in archive.infolist():
                restored = root / info.filename
                permissions = (info.external_attr >> 16) & 0o777
                if permissions and restored.exists():
                    restored.chmod(permissions)
        app = root / 'Payload' / app_name
        bundle, binary = validate_app(app)
        framework = app / 'Frameworks' / framework_source.name
        framework.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(framework_source, framework)
        run(str(injector), str(binary), LOAD_PATH)
        if LOAD_PATH not in run('xcrun', 'otool', '-L', str(binary)):
            raise ValueError('Injected load command was not present after patching')
        binary.chmod(binary.stat().st_mode | stat.S_IXUSR)
        if all(signing):
            sign_app(app, args.sign_identity, args.profile, args.entitlements, bundle)
        partial = output.with_name(output.name + '.partial')
        try:
            package_ipa(root, partial)
            with zipfile.ZipFile(partial) as check:
                if check.testzip() is not None:
                    raise ValueError('Output ZIP integrity check failed')
            os.replace(partial, output)
        finally:
            partial.unlink(missing_ok=True)
    manifest = {'input_sha256': sha256_file(ipa),
                'output_sha256': sha256_file(output),
                'bundle_id': bundle, 'injected_load_path': LOAD_PATH,
                'signed': bool(all(signing)), 'ios_minimum': '15.0'}
    output.with_suffix(output.suffix + '.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f"Created {output} ({'Apple signed' if all(signing) else 'requires TrollStore or another signer'})")


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        sys.exit(f'PickerPatcher IPA error: {error}')
