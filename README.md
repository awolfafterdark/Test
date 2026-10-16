# PickerPatcher · iOS 15 rootless tweak and on-device IPA patcher

PickerPatcher offers **Photo Library / Browse Files** when a selected app
presents a standard `UIImagePickerController` for its photo library. The Files
choice returns one image or movie via the original UIKit picker delegate.
Its core has no jailbreak-loader dependency and is built twice:

| Mode | Build output | Load mechanism |
| --- | --- | --- |
| Installed app | Rootless `.deb` | Dopamine/ElleKit loads a per-bundle filtered tweak |
| On-device patcher | `PickerPatcherApp-TrollStore.ipa` | Import another IPA from Files, patch locally, share result to TrollStore |
| Supplied IPA on macOS CI | Embedded `.framework`, patched `.ipa` | Main executable loads framework through `LC_LOAD_DYLIB` |

**Scope:** This is a functional implementation for the standard UIKit picker
contract, not a universal photo picker replacement. `PHPickerViewController`,
custom gallery UIs, edit-enabled pickers, apps that require a `PHAsset` ID,
and app-specific upload models pass through unchanged or need a separate
adapter. A successful build cannot prove a specific app's upload succeeds.

## GitHub Actions: build from scratch

Upload this directory's contents to the root of a GitHub repository, including
`.github/workflows/build.yml`. Open **Actions → Build PickerPatcher for iOS 15
→ Run workflow**. Enter exact app bundle IDs separated by commas. The run
checks out pinned Theos, uses Xcode's iOS SDK, builds the rootless `.deb`,
embedded framework, and the separate on-device patcher `.ipa`, and uploads
them together. The shared C injector rejects binaries without sufficient
Mach-O header padding.

Open `PickerPatcherApp-TrollStore.ipa` from the Actions artifact in TrollStore.
Within the patcher, choose an unencrypted IPA from Files, wait for the local
export, then tap **Share IPA to TrollStore or Files** and select TrollStore.
If it is absent from the first share panel, save to Files and share it from
there. You can also use **Files → Share → Open in PickerPatcher** to send an
IPA directly to the app. The importer declares the IPA document type so Files
can select it on iOS 15. TrollStore signs the patched app during installation. The exported IPA
remains in the patcher's Documents until deleted with the app's button. The
source IPA is never overwritten. The `.deb` is separately installed via a
rootless package manager on a Dopamine device.

The workflow's **Run workflow** form also accepts `app_display_name` and
`icon_jpg_url`. Leave them blank to use the PickerPatcher name and generated
default icon. For a custom icon, provide a public HTTPS URL to a JPEG (up to
10 MB). The build crops it to a square and creates all iPhone/iPad app icon
sizes. The name changes the patcher's Home Screen label, not the bundle ID or
the names of patched third-party apps.

With an optional URL to a user-provided **unencrypted** IPA, the workflow also
patches that IPA. Without signing secrets the resulting IPA has an invalid
original signature and requires TrollStore or another signing step. To receive
an Apple signed IPA, configure
these repository secrets with values matching the target app and device:

| Secret | Content |
| --- | --- |
| `SIGN_IDENTITY` | Apple signing identity name installed from the P12 |
| `BUILD_CERTIFICATE_BASE64` | Base64 P12 certificate |
| `P12_PASSWORD` | P12 password |
| `BUILD_PROVISION_PROFILE_BASE64` | Base64 `.mobileprovision` for this app ID |
| `ENTITLEMENTS_BASE64` | Base64 entitlements plist authorized by that profile |
| `KEYCHAIN_PASSWORD` | Temporary CI keychain password |

The workflow rejects partial signing secret sets. Keep private IPAs and signing
material in a private repository; GitHub Actions artifacts may be accessible to
people with repository access. Do not put a signing certificate in source.

## Local macOS build

Requires full Xcode, Theos, GNU Make, `dpkg`, `ldid`, and XcodeGen.
On macOS with Homebrew, the single build script installs missing command-line
tools, checks out the pinned Theos revision, and produces both artifacts:

```sh
TARGET_BUNDLE_IDS='com.example.target' \
APP_DISPLAY_NAME='My Patcher' \
ICON_JPG_URL='https://example.com/my-icon.jpg' \
bash Tools/build-all-macos.sh
```

Omit `APP_DISPLAY_NAME` and `ICON_JPG_URL` for defaults. The JPEG must be a
direct public HTTPS image URL. Results appear in `dist/`.

Manual steps, if you already have Theos configured:

```sh
python3 configure-target.py 'com.example.first,com.example.second'
export THEOS=/path/to/theos
make clean package FINALPACKAGE=1
bash Tools/build-embedded.sh "$PWD/dist"
xcrun clang -O2 -DPP_STANDALONE Core/MachOInject.c -o dist/pp-inject
python3 Tools/configure_app.py 'My Patcher'
swift Tools/make_app_icon.swift /path/to/optional-icon.jpg
mkdir -p PatcherApp/Resources
(cd dist && ditto -c -k --keepParent PickerPatcherEmbedded.framework ../PatcherApp/Resources/Payload.zip)
cp Core/MachOInject.c Core/MachOInject.h PatcherApp/Sources/
(cd PatcherApp && xcodegen generate --spec project.yml)
xcodebuild -project PatcherApp/PickerPatcherApp.xcodeproj -scheme PickerPatcherApp \
  -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

Copy the rootless `packages/*.deb` to the Dopamine device and install it in
Sileo or another compatible package manager. Fully close and reopen the
target app. The `.deb` only injects into bundle IDs in `PickerPatcher.plist`;
the original app executable is untouched. Remove the package to roll back.
The per-app `PickerPatcherDisabled` user-default flag also disables the hook.
The global `/var/jb/Library/PickerPatcher/disabled` flag is best-effort because
app sandbox access can vary; uninstalling the package is the reliable fallback.

For a user-provided, unencrypted IPA on macOS:

```sh
python3 Tools/patch_ipa.py --ipa MyApp.ipa \
  --framework dist/PickerPatcherEmbedded.framework \
  --injector dist/pp-inject --out MyApp-patched.ipa
```

That output needs a signer. For signing in this tool, also add
`--sign-identity 'Apple Development: Name (TEAM)'`, `--profile app.mobileprovision`,
and `--entitlements app-entitlements.plist` together. The profile and
entitlements must match the app ID and signing identity. The tool signs nested
frameworks, then the main app, and verifies the result. It deliberately rejects
app extensions and nested apps because each needs its own profile and signing
configuration. It will also reject an encrypted main executable, unsupported
architectures, unsafe ZIP entries, insufficient working space, or a Mach-O
binary into which the load command cannot be inserted. Preserve the original
IPA as rollback; the output includes a SHA-256 manifest.

The on-device app uses pinned ZIPFoundation 0.9.20. It extracts to a temporary
container, checks free space before extraction, refuses symlinks and unsafe
paths, and limits expanded input to 4 GiB. It supports thin arm64 main
executables only. Apps with encrypted secondary frameworks, integrity checks,
or unusual entitlement requirements can still fail installation or launch.
The patcher cannot retrieve or decrypt already installed apps.

## Device validation

1. Test Photos and Files with a small JPEG or PNG in an app you control.
2. Test a movie and a cloud-backed Files provider; verify the app's actual upload.
3. Test cancel, low free space, iPad action sheet positioning, and app relaunch.
4. Install the patcher IPA through TrollStore; patch an unencrypted test IPA,
   share the export to TrollStore, install, launch, and test the actual upload.

Files are copied to the target app's temporary directory after a size check.
Copies older than 24 hours are pruned on the next app launch. The image
handoff may decode into memory; very large images may exceed app memory.

No Xcode toolchain or jailbroken device was available where this repository was
prepared. The shared injector's insertion, duplicate, padding, and encryption
checks pass on Linux. Xcode builds, TrollStore installation, and actual uploads
still need verification by running the workflow and testing an iOS 15 device.
