# PickerPatcher 0.7 for iOS 15

GitHub Actions builds two outputs: a rootless Dopamine `.deb` for selected installed applications, and a separate TrollStore IPA that patches copies of unencrypted IPAs on the device. No local Mac build is required. The same interception engine is compiled independently for both modes.

## Build on GitHub

Extract the source ZIP and upload **its contents** to the repository root, including `.github/workflows/build.yml`. Open Actions → Build PickerPatcher for iOS 15 → Run workflow.

| Workflow input | Purpose |
| --- | --- |
| `target_bundle_ids` | Exact comma-separated app IDs for rootless injection. **The default targets only the included test app `dev.pickerpatcher.demo`. It does not enable every installed app.** Set the actual app ID and rebuild to target that installed app. |
| `app_display_name` | Optional patcher Home Screen name, default PickerPatcher 0.7. |
| `icon_image_url` | Optional direct HTTPS JPG/PNG URL, maximum 10 MB. Generates correctly sized app icons automatically. |

Download the installables artifact for the patcher IPA, rootless DEB and unpatched harness. The separate source artifact contains every file needed to rebuild. The full artifact includes frameworks, test results, load commands, signing reports and diagnostics. The GitHub runner uses macOS; the user does not need a Mac.

## Check injection first

Update the installed tweak to 0.7 or disable/remove the older tweak before testing a newly patched app; the 0.7 duplicate-load guard covers the two 0.7 products, not older releases. Fully close and reopen the target after changes.

Install **PickerPatcher 0.7.0 (7)** (`dev.pickerpatcher.app.v07`) in TrollStore. Import an original, unencrypted target IPA, patch it and share the result to TrollStore. Open the **patched target app**. A small blue **PP** button confirms that the injected framework actually loaded. It shows enabled state, last controller, matched-presentation count, runtime PHPicker constructor availability and WebKit hook availability. Share runtime diagnostics from this button after reproducing an upload. Logs contain controller class names and adapter events, not media contents, filenames, URLs, accounts or upload request bodies. The button can be hidden until restart. The app remembers a local disable setting.

**No PP button:** investigate installation/loading/filtering first. IPA export alone does not prove injection or upload compatibility. For `.deb` mode, verify the exact bundle ID is in the filter, jailbreak injection is enabled for that process, and fully close/relaunch the target. For IPA mode, install the newly exported copy, not the original. A duplicate package or app-specific anti-tampering can prevent launch. Restore the original IPA or remove the tweak to roll back.

**PP button but no chooser:** open PP after reproducing and share diagnostics together with the exact app name/version and upload screen. The last class and event list distinguish an unsupported custom gallery from missed standard presentation or a runtime-disabled adapter.

## Adapters

| Upload path | Behavior |
| --- | --- |
| Standard non-editing `UIImagePickerController` | Photos/Files choice; single image or movie; exact original delegate/controller and dismissal lifecycle retained. |
| `PHPickerViewController` using item providers | Photos/Files choice; genuine PhotosUI result objects wrapping lazy NSItemProvider image/file/data representations. Runtime-checks private `_initWithItemProvider:assetIdentifier:` and the newer item-based initializer. Supports images, videos or their union, up to 32 files within the original selection limit. Photos asset IDs are nil, never fabricated. |
| iOS 15 `WKWebView` HTML file uploads | Guarded private `WKFileUploadPanel` menu hook calls its own `showFilePickerMenu`. WebKit retains accepted types, multiple-selection, native document delegate, sandbox transfer and WebContent listener. The native Files picker opens directly. Camera capture remains original. |
| Wrapped/contained standard picker | Recursive detection at modal presentation; appearance fallback for navigation/containment paths that reach UIKit lifecycle. |
| Editing, specialized PHPicker filters, identifier-only/preselected Photos results, custom PHAsset/proprietary galleries | Original flow retained. Requires a tested targeted adapter. A screen containing thumbnails cannot reveal an arbitrary app's upload callback contract. |

The PHPicker constructor is a **private API**, verified in iOS 14.2 and 15.5 runtime headers; exact 15.3.1 behavior still requires device validation. WebKit selectors are verified in iOS15-era WebKit source. Both are runtime guarded, and availability is visible in PP diagnostics. The newer item-based initializer is separately signature-checked; public provider consumption is supported, while private Photos metadata, secure-coding roundtrips and Photos asset identities require their own adapter. These integrations are for jailbreak/TrollStore use. No claim of universal application compatibility is made.

The UIImagePicker/PHPicker adapters validate and stage media using coordinated file access and balanced security scopes. Original names are retained in isolated folders. Videos stay file based; item-provider data requests above 128 MiB return a clear error so the receiver must request a file representation. Image dimensions are limited to 32 MP/12,000 pixels. Original media files are not overwritten. Staging older than 24 hours is pruned on the next launch; the app's temporary storage may also be purged by iOS. At least 256 MiB free space must remain.

## On-device proof

Tap **Create picker test IPA**, reopen Choose IPA from Files, select `PickerHarness.ipa`, patch and install its export in TrollStore. The harness reports the injected framework version and has legacy image/video, PHPicker single/multiple, wrapped picker and actual HTML upload tests. Choose Files and verify image delivery, dismissal and provider reads. For rootless mode, install the unpatched harness plus the `.deb` targeting `dev.pickerpatcher.demo` instead.

Imported/exported IPAs persist in the patcher's Files container until deleted. The original IPA is never modified. The patcher accepts supported unencrypted thin arm64 binaries with free Mach-O header padding; extensions/nested apps, unsafe archives, insufficient space and encrypted binaries are rejected. API detection in binaries is a heuristic. Exports contain a manifest stating that upload compatibility has not been verified for the target app.

## Verification

CI compiles iOS15 deployment targets, runs injector safety cases, validates signatures and JPEG/PNG icon generation, and exercises native UI. **The Simulator host does not link the hook source**: CI injects the separately compiled framework into its executable with the actual Mach-O injector, signs it and launches it. A separately loaded second image checks duplicate-hook safety.

Tests cover native IPA selection/patching, legacy media/cancellation, PHPicker object/data/file representations, Objective-C-to-Swift PHPickerResult bridging, multiple selection, cancellation and a real WKWebView HTML file input change followed by reading/decoding the selected image in JavaScript. CI uploads XCTest results and actual runtime name. A newer Simulator cannot establish iOS15.3.1 physical-device behavior, jailbreak loader success, third-party upload completion, or arbitrary app compatibility. Build/test outcomes must be reported with these boundaries.

Sources and implementation rationale: [iOS 15 upload API research](Research/iOS15-upload-api-research.md). Earlier investigation notes are retained as historical context.
