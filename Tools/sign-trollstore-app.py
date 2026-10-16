#!/usr/bin/env python3
"""Ad-hoc sign our own app. TrollStore applies device installation signing.
Simulator targets use a local code identity with no restricted device claims.
"""
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

app = Path(sys.argv[1]).resolve()
report = Path(sys.argv[2]) if len(sys.argv) > 2 else None
simulator = '--simulator' in sys.argv[3:]
info = plistlib.loads((app / 'Info.plist').read_bytes())
bundle_id = info['CFBundleIdentifier']
assert bundle_id.startswith('dev.pickerpatcher.')
assert info.get('UIFileSharingEnabled') is True
assert info.get('LSSupportsOpeningDocumentsInPlace') is True
team = 'PICKERPTCH'
expected = {} if simulator else {
    'application-identifier': f'{team}.{bundle_id}',
    'com.apple.developer.team-identifier': team,
    'get-task-allow': False,
}
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / 'Entitlements.plist'
    path.write_bytes(plistlib.dumps(expected))
    command = ['codesign', '--force', '--sign', '-', '--timestamp=none', '--identifier', bundle_id]
    if not simulator:
        command.append('--generate-entitlement-der')
    command.extend(['--entitlements', str(path), str(app)])
    subprocess.run(command, check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    dump = subprocess.run(['codesign', '--display', '--entitlements', ':-', str(app)],
                          check=True, capture_output=True).stdout
    actual = plistlib.loads(dump) if dump.strip() else {}
    assert actual == expected, actual
    identity = subprocess.run(['codesign', '--display', '--verbose=4', str(app)],
                              check=True, capture_output=True).stderr.decode()
    assert f'Identifier={bundle_id}\n' in identity
    if report:
        report.write_text(json.dumps({
            'bundleIdentifier': bundle_id, 'codeSigningIdentifier': bundle_id,
            'simulator': simulator, 'entitlements': actual,
            'fileSharing': info['UIFileSharingEnabled'],
            'openingInPlace': info['LSSupportsOpeningDocumentsInPlace']
        }, indent=2)+'\n')
print(f'Verified ad-hoc identity for {bundle_id}; simulator={simulator}')
