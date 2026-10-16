# IPA selection on iOS 15.3.1

## Evidence from the reported device

- The supplied Files screenshots show IPA files under **iCloud Drive** in Recents, with cloud badges on several icons. That indicates a provider-backed location; it does not prove the downloads succeeded or failed.
- The PickerPatcher screen photo has no **Version 0.4.0 (4)** row, although the v0.4.0 source renders one below Compatibility. The shown process therefore cannot be confidently identified as v0.4.0 and is consistent with an older installation. A cropped or scrolled screenshot is another possibility; a visible top build banner removes this ambiguity.
- No document-picker delegate callback or system log was captured. The precise cause of the untappable IPA is still unconfirmed.

## Relevant platform behavior

Apple's Document Picker Programming Guide says external URLs may point to placeholders, a coordinated read triggers their download, and a slow network may delay availability. It also says import operations copy the source and a provider must materialize a remote document before notifying the importing app. See:

- https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/DocumentPickerProgrammingGuide/CreatinganOutstandingUserExperience/CreatinganOutstandingUserExperience.html
- https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/DocumentPickerProgrammingGuide/AccessingDocuments/AccessingDocuments.html

Apple documents that `UIFileSharingEnabled` plus `LSSupportsOpeningDocumentsInPlace` exposes an app's Documents directory in Files on iOS 11 and later:

- https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html

TrollStore's IPA selection code resolves the `.ipa` extension and presents `UIDocumentPickerViewController`; this informed the v0.4.0 importer:

- https://github.com/opa334/TrollStore/blob/main/TrollStore/TSAppTableViewController.m

## v0.5.0 changes and validation boundary

- Distinct bundle ID and a visible `Build 0.5.0 (5)` banner distinguish this build from an existing installation.
- The Files picker requests an import copy (`asCopy: true`) and accepts the resolved IPA type or general data type. IPA extension is still validated by the patcher.
- On first launch, the app creates `Documents/Imports`, exposed in Files at **On My iPod → PickerPatcher 0.5 → Imports**. A refreshable list patches local IPAs directly without relying on a picker delegate.
- GitHub Actions can verify compilation, packaging, and archive metadata. Only a test on iOS 15.3.1 can establish that the picker and local path work on the device. If the local button shows an error after selection, record the exact status text; that is a separate patching failure.
