# PickerPatcher for iOS 15

This project builds **two separate installable outputs in GitHub Actions**:

| Output | Use |
| --- | --- |
| `dev.pickerpatcher.prototype_0.5.0_iphoneos-arm64.deb` | Install with a rootless package manager on a Dopamine iOS 15 device. ElleKit injects only into the bundle IDs selected at build time. |
| `PickerPatcherApp-TrollStore.ipa` | Install through TrollStore. Choose an unencrypted IPA in Files, patch it on the device, then share the resulting IPA to TrollStore for installation. |

The embedded framework and Mach-O injector are also in the Action artifact. The tweak and the on-device patcher use the same picker code. The original app executable is untouched in installed-app mode; IPA mode modifies a **copy** of the supplied package.

## Upload to GitHub and build

1. Extract `PickerPatcher-GitHub-ready-iOS15.zip`. Upload **its contents** to the root of your GitHub repository, preserving `.github/workflows/build.yml`, `Makefile`, `Core/`, `PatcherApp/`, `Tools/`, and the other paths. The ZIP itself is a transport archive; uploading only the ZIP or only `build.yml` does not provide the source files needed by the runner.
2. Open **Actions → Build PickerPatcher for iOS 15 → Run workflow**. The `target_bundle_ids` field identifies one or more installed apps for the tweak; use exact comma-separated bundle IDs. Its demo default is not a real target app.
3. Optionally fill in the two customization fields below, then run the workflow. The macOS GitHub runner checks out pinned Theos, builds the rootless tweak, framework, injector, and patcher IPA, and uploads them as one artifact named `PickerPatcher-iOS15-N`.
4. Open the completed run and download the artifact ZIP. Install its `.deb` with Sileo or a compatible rootless package manager, and install its `PickerPatcherApp-TrollStore.ipa` with TrollStore. Fully close and reopen a target app after installing the tweak.

| Optional Run workflow field | Meaning |
| --- | --- |
| `icon_image_url` | Direct public HTTPS URL to a JPG or PNG (up to 10 MB). The Action checks the decoded image format, crops the image to a square, and generates all iPhone/iPad app icon sizes. Leave empty for the default icon. |
| `app_display_name` | Home Screen name for the **patcher app**. Leave empty for `PickerPatcher 0.5`. This does not rename patched third-party apps. |

No local Mac build script, Apple certificate, or repository secret is required for these two outputs. The CI-built patcher IPA uses an ad-hoc signature for TrollStore. The output of the on-device patcher is installed and signed by TrollStore.

## Use the on-device IPA patcher

Install version **0.5.0 (5)**. The build number is at the top of the patcher screen. This version has a distinct bundle ID (`dev.pickerpatcher.app.v05`) and default Home Screen name (`PickerPatcher 0.5`), so it installs beside older builds; open the new icon. Tap **Choose IPA from Files**, select an unencrypted IPA, wait for the result, and tap **Share IPA to TrollStore or Files**. The UIKit document picker asks Files for a copy, which may require an iCloud download before selection completes. If TrollStore is absent from the first share panel, save the result to Files and share it from there.

If an iCloud Drive file remains visible but untappable, use **Files → Browse → iCloud Drive**, copy the IPA, then paste it into **On My iPod → PickerPatcher 0.5 → Imports**. Return to PickerPatcher, tap **Refresh local IPAs**, and tap **Patch _filename_.ipa**. The app creates the Imports folder when first launched and shows every regular `.ipa` in it. This local path does not depend on the document picker returning a URL. If you chose a custom app name, the folder will use that name. You can also select an IPA in Files and use **Share → Open in PickerPatcher**.

Errors are shown in the app, and the source IPA is not overwritten. Exported IPAs remain in the patcher's Documents until deleted with its button.

The on-device patcher supports thin arm64 main executables with free Mach-O header space. It rejects encrypted executables, app extensions, nested apps, unsafe ZIP paths, and insufficient disk space. It cannot retrieve or decrypt already installed apps. Apps with integrity checks or unusual entitlements may still fail installation or launch. Test each patched app's actual upload flow.

## Picker compatibility

For standard `UIImagePickerController` photo-library use, choosing Files passes a single image or movie to the app's original UIKit picker delegate. Photos invokes the original picker. `PHPickerViewController`, custom gallery UIs, edit-enabled pickers, apps requiring a `PHAsset` identifier, and proprietary upload models need separate adapters. The tweak passes unsupported flows through unchanged. A successful GitHub build cannot establish compatibility with an arbitrary target app.

The `.deb` injects only into the configured bundle IDs in `PickerPatcher.plist`. Remove the package to roll back. The per-app `PickerPatcherDisabled` user default disables the hook; `/var/jb/Library/PickerPatcher/disabled` is a best-effort global flag because sandbox access varies. Staged media copies older than 24 hours are pruned on the next app launch. Large decoded images may exceed an app's memory.

## Validation

The Action compiles the iOS app and rootless tweak, exercises JPEG and PNG icon generation, verifies the IPA ZIP and ad-hoc app signature, and runs injector regression cases. An iOS 15 Dopamine device with TrollStore is still needed to verify the Files selection, local folder patch/export/install, and media upload in each target app. Test first with a small unencrypted IPA that you are authorized to modify. If an IPA remains visible but untappable in both this app and TrollStore's **Install IPA File** picker, verify it has downloaded locally in Files.
