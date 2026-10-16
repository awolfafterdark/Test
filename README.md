# PickerPatcher for iOS 15

This project builds **two separate installable outputs in GitHub Actions**:

| Output | Use |
| --- | --- |
| `dev.pickerpatcher.prototype_0.6.0_iphoneos-arm64.deb` | Install with a rootless package manager on a Dopamine iOS 15 device. ElleKit injects only into the bundle IDs selected at build time. |
| `PickerPatcherApp-TrollStore.ipa` | Install through TrollStore. Choose an unencrypted IPA in Files, patch it on the device, then share the resulting IPA to TrollStore for installation. |

The embedded framework and Mach-O injector are also in the Action artifact. The tweak and the on-device patcher use the same picker code. The original app executable is untouched in installed-app mode; IPA mode modifies a **copy** of the supplied package.

## Upload to GitHub and build

1. Extract `PickerPatcher-GitHub-ready-iOS15.zip`. Upload **its contents** to the root of your GitHub repository, preserving `.github/workflows/build.yml`, `Makefile`, `Core/`, `PatcherApp/`, `Tools/`, and the other paths. The ZIP itself is a transport archive; uploading only the ZIP or only `build.yml` does not provide the source files needed by the runner.
2. Open **Actions → Build PickerPatcher for iOS 15 → Run workflow**. The `target_bundle_ids` field identifies one or more installed apps for the tweak; use exact comma-separated bundle IDs. Its default targets the included test app `dev.pickerpatcher.demo`; replace it to target a real app.
3. Optionally fill in the two customization fields below, then run the workflow. The macOS GitHub runner checks out pinned Theos, builds the rootless tweak, framework, injector, and patcher IPA, and uploads them as one artifact named `PickerPatcher-iOS15-N`.
4. Open the completed run and download the artifact ZIP. Install its `.deb` with Sileo or a compatible rootless package manager, and install its `PickerPatcherApp-TrollStore.ipa` with TrollStore. Fully close and reopen a target app after installing the tweak.

| Optional Run workflow field | Meaning |
| --- | --- |
| `icon_image_url` | Direct public HTTPS URL to a JPG or PNG (up to 10 MB). The Action checks the decoded image format, crops the image to a square, and generates all iPhone/iPad app icon sizes. Leave empty for the default icon. |
| `app_display_name` | Home Screen name for the **patcher app**. Leave empty for `PickerPatcher 0.6`. This does not rename patched third-party apps. |

No local Mac build script, Apple certificate, or repository secret is required for these two outputs. The CI-built patcher IPA uses an ad-hoc signature for TrollStore. The output of the on-device patcher is installed and signed by TrollStore.

## Use the on-device IPA patcher

Install version **0.6.0 (6)**. It uses the distinct bundle ID `dev.pickerpatcher.app.v06` and default name **PickerPatcher 0.6**. Its importer is a native UIKit controller presented full screen with a persistent delegate, broad file filtering, copy import, and both document callback entry points.

1. Tap **Choose IPA from Files** and tap an IPA. The picker should close and the app should show **Selected _filename_. Ready to patch.**
2. Tap **Patch selected IPA**. Selection and patching are separate so a patch failure cannot be mistaken for a selection failure.
3. Tap **Share patched IPA to TrollStore or Files**.

If tapping still has no effect, cancel and use **Try compatibility import** (the legacy import initializer, still supported on iOS 15). Tap **Share diagnostics** to export the event log. It records whether presentation completed, which selection callback fired, and whether import or patching failed. It excludes selected filenames, full paths and file contents.

**Create picker test IPA** puts a known small, unencrypted `PickerHarness.ipa` in Imports and selects it. Reopen **Choose IPA from Files** and select this local fixture to isolate the picker from iCloud and third-party IPA compatibility. The test app supports image/video selection and checks original picker identity, dismissal completion, and reading the selected file afterward. With the default tweak bundle ID, install the unpatched harness plus the tweak; for IPA mode, patch the harness and install its exported copy instead. Avoid injecting both versions into the same test process.

Local fallback: copy an IPA in Files to **On My iPod → PickerPatcher 0.6 → Imports**, tap **Refresh local IPAs**, tap its filename, then **Patch selected IPA**. Open In from Files is also handled. Imported and exported IPAs persist until deleted; delete unused files in Files when storage is low. The original input is not overwritten.

The on-device patcher supports thin arm64 main executables with free Mach-O header space. It rejects encrypted executables, app extensions, nested apps, unsafe ZIP paths, insufficient disk space, and IPAs with no detectable supported UIKit picker reference. API reference detection is a heuristic, not an upload compatibility test. An exported manifest states that limitation. It cannot retrieve or decrypt already installed apps. Apps with integrity checks or unusual entitlements may still fail installation or launch. Test each patched app's actual upload flow.

## Picker compatibility

For standard `UIImagePickerController` photo-library use, choosing Files keeps the original UIKit picker presented beneath the document picker, then passes a single image or movie to the app's original UIKit picker delegate. Photos invokes the original picker. `PHPickerViewController`, custom gallery UIs, edit-enabled pickers, apps requiring a `PHAsset` identifier, and proprietary upload models need separate adapters. The tweak passes unsupported flows through unchanged. A successful GitHub build cannot establish compatibility with an arbitrary target app.

The `.deb` injects only into the configured bundle IDs in `PickerPatcher.plist`. Remove the package to roll back. The per-app `PickerPatcherDisabled` user default disables the hook; `/var/jb/Library/PickerPatcher/disabled` is a best-effort global flag because sandbox access varies. Staged media copies older than 24 hours are pruned on the next app launch. Images above 32 megapixels or 12,000 pixels per dimension are rejected to bound memory use. Videos stay file based.

## Validation

The Action compiles the iOS 15 deployment targets, tests JPEG/PNG icon generation, verifies packaging/signatures, and runs injector safety tests. It also runs XCTest UI tests against an available iOS Simulator: tapping the real native Files picker to select and patch the bundled IPA, compatibility-picker cancellation, and selecting/cancelling media with original delegate identity and dismissal checks. The media host loads an independently compiled second hook image to verify that accidental duplicate loading does not recursively replace the UIKit entry point. The runtime name and `.xcresult` bundles are uploaded with the artifacts, including on failure. These tests target the shared source; Simulator cannot load the arm64 device injection framework.

The GitHub runner's available Simulator runtime is newer than iOS 15. On-device iOS 15.3.1, TrollStore installation, jailbreak injection, cloud providers, actual server upload and each third-party app remain separate verification gates. A successful test result must not be described as universal application compatibility. See `Research/iOS15-deep-research.md` for sources, verified code defects, hypotheses, and remaining boundaries.
