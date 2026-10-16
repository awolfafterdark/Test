# iOS 15.3.1 picker investigation and v0.6.0 implementation

## Findings and evidence strength

| Finding | Evidence | Implementation |
| --- | --- | --- |
| Visible enabled files can produce no selection callback when a picker is hosted incorrectly. | Apple Developer Forums thread 121834: developer reports enabled files and cancellation working; direct modal presentation fixed their pushed controller. This is a first-person reproduction, not an Apple confirmation of the current user's cause. | Replace the SwiftUI sheet/representable presentation with direct full-screen UIKit modal presentation, retained controller, and a delegate retained for the app lifetime. |
| The current device cause is unknown. | Screenshots show an iCloud location but contain no callback trace. Neither a cloud issue nor an old installation is established. | Separate selection/import/patch states and export a callback event log. A bundled local test IPA distinguishes picker delivery from cloud access and binary incompatibility. |
| Import and open differ. | Apple's Document Picker Programming Guide says import delivers a temporary local copy; open returns security-scoped external URLs and requires coordination. | Use copy-import in the normal and legacy options. Coordinate and copy external Open In URLs into Imports. Do not treat startAccessingSecurityScopedResource returning false as an automatic failure for local files. |
| Delegate selection method differences have been reported on iOS 15. | Search surfaced developer reports of the singular deprecated delegate method being invoked. Not independently established for 15.3.1. | Implement singular and plural callbacks, funnel to one guarded handler; do not call both manually. |
| The previous injected media flow broke original-controller lifecycle semantics. | Source review: the original UIImagePickerController was passed to the target delegate despite never being presented. Apple's delegate documentation says the app manages dismissal. | Present the original controller normally, then present Documents over it. Dismiss Documents before the callback. The target can dismiss its original controller and read the staged file asynchronously. No private fake controller state. |
| File URLs cannot supply arbitrary Photos identities. | Apple documents PHPickerResult's read-only itemProvider and optional assetIdentifier; no documented public iOS 15 constructor from a URL exists. WWDC20 explains provider loading and app-owned dismissal. | Keep PHPicker and PHAsset-dependent flows original. App-specific adapters need a target application and its actual callback contract. Do not create fake Photos identifiers or claim a generic modern-picker adapter works. |
| The same picker contract must be verified for tweak and embedded mode. | Both compile Core/PickerPatcher.m. | Include an unpatched small arm64 test IPA and a Simulator host built with the shared source; test callback identity, original dismissal, and file reads after dismissal. |

## Primary sources reviewed

1. Apple modal-presentation report: https://developer.apple.com/forums/thread/121834
2. Apple document picker API: https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller
3. Apple document selection/import guide: https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/DocumentPickerProgrammingGuide/AccessingDocuments/AccessingDocuments.html
4. Apple provider availability/coordinated read guide: https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/DocumentPickerProgrammingGuide/CreatinganOutstandingUserExperience/CreatinganOutstandingUserExperience.html
5. Apple UIImagePickerControllerDelegate: https://developer.apple.com/documentation/uikit/uiimagepickercontrollerdelegate
6. Apple PHPickerResult: https://developer.apple.com/documentation/photosui/phpickerresult-c.class?language=objc
7. Apple WWDC20 Photos picker: https://developer.apple.com/videos/play/wwdc2020/10652/
8. Official TrollStore importer source: https://github.com/opa334/TrollStore/blob/main/TrollStore/TSAppTableViewController.m

Secondary discovery only (not treated as authoritative API guarantees): https://stackoverflow.com/questions/54234901/uidocumentpickerdelegate-methoddidpickdocumentsat-not-called-by-ios

## Signing review

Official TrollStore RootHelper/main.m was reviewed. If an input main executable has no entitlement dictionary, TrollStore supplies a fallback application identity `TROLLTROLL.*`; it also handles container entitlements. That code does not prove signing caused this device's picker failure. Version 0.6 supplies and verifies an explicit application-identifier matching our actual bundle ID, a deterministic team prefix, and get-task-allow=false; DER entitlements are generated. No no-sandbox, platform-application, or broad file-access entitlement is added. The exact generated values are uploaded as JSON. This is ad-hoc packaging intended for TrollStore, not conventional App Store/provisioned signing.

- https://github.com/opa334/TrollStore/blob/main/RootHelper/main.m
- https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles

## Research service coverage

- Parallel Search: searched modal presentation, TrollStore and iOS 15 symptoms; retrieved Apple API descriptions and distinct failure reports.
- Exa: found the Apple forum reproduction and the iOS 15 singular-delegate report; reviewed item-provider and presentation limitations.
- Search1API: entitlement-oriented lookup returned mostly macOS material; discarded the macOS-only entitlement advice. No unsupported entitlement was added to the app.
- Tavily: broad research timed out; narrower PHPicker search succeeded but returned mostly aggregated forum pages. It did not establish a fix.
- Nimble: Apple forum hit a human-verification barrier; no bypass attempted. Fetch of Apple's document import guide succeeded.
- SerpApi: no callable connector, CLI, injected key or configured key store was available. No SerpApi result is claimed.
- Mobile App Builder debugging workflow: separated UI, callback, access, patching and compatibility failures; added reproduction/test cases. It supplies no iOS framework evidence.

## Simulator reproduction and test setup

Native copy-import tests reproduced an enabled local IPA producing no callback, while native cancellation worked. Those Simulator applications had been built with CODE_SIGNING_ALLOWED=NO. Shipping IPA packaging already signs with an explicit identity. The final test pipeline separately builds for testing, ad-hoc signs the target app with that same explicit identity (get-task-allow=true for the Simulator only), then uses test-without-building to preserve that signature. It also taps the visible native file thumbnail, navigates the actual provider folders, uses explicit boolean plist file-sharing declarations, and exports File Provider logs. Because those corrections occur together, a success does not isolate one cause of the original iOS 15.3.1 problem.

## Duplicate loading

A category-based swizzle stores UIKit's implementation under another Objective-C selector. Loading a second library with that same category can overwrite the saved selector before an initialization guard runs, producing recursion. The final engine uses a static C hook and saved IMP, with shared selector association keys and a process-level installation flag. The Simulator media host deliberately loads a second independent build of the core and runs its native file-selection/cancellation tests with both images loaded. The shipping IPA patcher does not contain this simulator-only dylib.

## Tests and boundaries

The CI UI tests require native Files selection of a bundled unencrypted IPA followed by successful patching, cancellation through the compatibility picker, and native Files image selection/cancellation followed by valid original-controller callback/dismissal semantics. CI stores runtime information and XCTest results. Runtime and device distinctions must accompany any success claim.

The test host checks readable bytes after dismissal. It is not a real server upload and does not establish a third-party application's compatibility. No arbitrary app name/version was supplied for a targeted adapter. iOS 15.3.1 hardware, iCloud/provider variations, TrollStore install/launch and jailbreak injection must still be exercised on device.
