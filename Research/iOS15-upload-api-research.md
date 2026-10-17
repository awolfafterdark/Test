# iOS 15 upload interception: API research

Research date: 2026-10-17. Scope: native PhotosUI results, WebKit HTML file input, and app-owned picker boundaries. This is evidence for implementation, not a claim that a real target app upload has passed.

## Findings that change the implementation

1. Version 18/19's UIImagePicker-only hook misses PHPicker and app-owned galleries. Successful IPA repackaging proves neither library loading nor upload interception. Record constructor/load, presentation class, chosen adapter, document callback, and delivery independently.
2. A genuine `PHPickerResult` can be built with the private selector `_initWithItemProvider:assetIdentifier:`. This selector is present in independently extracted iOS 14.2 and iOS 15.5 runtime headers. No exact iOS 15.3.1 dump was located in this research. Runtime capability and signature checks on that device remain necessary.
3. Public iOS 15.2 SDK headers explicitly prohibit PHPickerResult init/new and subclassing. An NSObject pretending to be a result, KVC mutation of private ivars, or a fabricated subclass is an inferior bridge: Swift imports PHPickerResult as a value wrapper and runtime implementations may enforce exact class identity. Use a real instance created by the guarded private initializer.
4. iOS 15-era WebKit already implements native Files upload delivery. Reuse `WKFileUploadPanel`'s `showFilePickerMenu`, with its own document-picker delegate and WebKit open-panel listener. The exact selector in the verified Safari-612 sources is **not** `_showDocumentPicker`.

## PHPicker bridge: concrete implementation

### Evidence and API status

Apple's public [PHPickerResult documentation](https://developer.apple.com/documentation/photosui/phpickerresult-swift.struct) exposes the item provider and nullable asset identifier. Apple's [WWDC20 picker session](https://developer.apple.com/videos/play/wwdc2020/10652/) demonstrates provider loading and states the caller owns presentation and dismissal. Its PhotoKit section distinguishes provider-based data access from PHAsset identifiers.

The [iOS 15.2 PHPicker.h SDK mirror](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS15.2.sdk/System/Library/Frameworks/PhotosUI.framework/Headers/PHPicker.h) shows:

- PHPickerResult is an NSObject with `objc_subclassing_restricted`.
- itemProvider is readonly; assetIdentifier is nullable and readonly.
- init/new are unavailable.
- PHPickerViewController itself is subclassing restricted; its private view hierarchy must not be modified.
- Delegate completion does not automatically dismiss the picker.
- Configuration selectionLimit 0 means maximum system-supported selection, not literal unlimited memory.
- A configuration initialized without PHPhotoLibrary never returns asset identifiers.
- iOS 15 preselection has special behavior: returned providers for preselected assets are empty.

The SDK mirror is a copy of Apple declarations, not a first-party Apple-hosted distribution. Private runtime evidence is also explicitly reverse-engineered:

- [iOS 15.5 PHPickerResult runtime header, fixed commit](https://github.com/lechium/iPhone_OS_15.5/blob/0f4def7da3cad33a6ea5a4224f4ec3526f3e73f8/System/Library/Frameworks/PhotosUI/PHPickerResult.h): `_initWithItemProvider:assetIdentifier:`.
- [iOS 14.2 runtime header](https://github.com/conorthedev/iOS14.2RuntimeHeaders/blob/89ff14e892a1f6fb9ec0af5c32355f77e4c3bd6f/Frameworks/PhotosUI.framework/PHPickerResult.h): same initializer.
- [iOS 15.5 configuration runtime header](https://github.com/lechium/iPhone_OS_15.5/blob/0f4def7da3cad33a6ea5a4224f4ec3526f3e73f8/System/Library/Frameworks/PhotosUI/PHPickerConfiguration.h): private `_onlyReturnsIdentifiers` getter and `initWithPhotoLibraryAndOnlyReturnsIdentifiers:`.

### Delivery flow

- Observe actual PHPicker presentation, including a navigation/container hierarchy. Retain the original picker, delegate and presentation context for the session.
- Offer Photos/Files only when the runtime has a compatible private result initializer and the original delegate implements `picker:didFinishPicking:`.
- Leave identifier-only configurations and preselected-identifier workflows on original Photos unless a target-specific adapter is present. Nil assetIdentifier is honest and valid for provider-only workflows; it cannot satisfy code that requires PHAsset identity.
- Present the original PHPicker controller through UIKit so app dismissal/completion assumptions remain true; present Files over it. Never alter its internal private view hierarchy.
- Copy/move selected media into an app-owned staging directory with a lifetime attached to provider/session, not just a document-picker callback stack.
- Construct NSItemProvider using actual file type. Lazily register original file bytes/file URL and a UIImage object representation when appropriate. Preserve original filename through suggestedName. Avoid decoding all selected images or buffering videos at selection time.
- Dynamically allocate the real PHPickerResult class and invoke `_initWithItemProvider:assetIdentifier:` with provider and nil identifier. Check method argument count/types, result class, and that result.itemProvider is the intended provider. Do not use public init and do not set ivars.
- Close only the document picker, then invoke original `picker:didFinishPicking:` with the original picker and results on the main queue. Let the app dismiss its original picker.
- Cancel should invoke the original delegate with an empty array exactly once after Files dismissal. Never invoke both cancel and success.

### Provider requirements

[Apple NSItemProvider docs](https://developer.apple.com/documentation/foundation/nsitemprovider) and the [iOS 15.2 Foundation SDK header](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS15.2.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSItemProvider.h) establish public iOS 11+ methods for file, data and object representations. UIImage conforms to NSItemProviderReading/Writing in [UIKit's UIImage.h](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS15.2.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIImage.h).

- Register higher-fidelity type first (original JPEG/HEIC/PNG/movie identifier), then conversions actually supported.
- `registerFileRepresentationForTypeIdentifier:fileOptions:visibility:loadHandler:` with no OpenInPlace option copies the provided file before the load handler returns. Do not delete the source staging file before provider consumers complete.
- `loadFileRepresentation...` returns a temporary file deleted after the consumer completion handler returns; the receiving application must copy it before that return, matching native providers.
- Tests must independently consume `loadObjectOfClass:UIImage`, loadDataRepresentation and loadFileRepresentation. Merely testing provider registration does not prove clients can read it.
- Clients requesting PHLivePhoto or PHAsset cannot be given arbitrary still-image bytes under those types.

## WKWebView HTML upload: reuse WebKit's native route

Primary source examined:

- [Apple/WebKit WKFileUploadPanel.mm, Safari-612.1.29.41.4](https://github.com/WebKit/WebKit/blob/Safari-612.1.29.41.4/Source/WebKit/UIProcess/ios/forms/WKFileUploadPanel.mm).
- [Its header](https://github.com/WebKit/WebKit/blob/Safari-612.1.29.41.4/Source/WebKit/UIProcess/ios/forms/WKFileUploadPanel.h).
- [Safari-612.4.9.1.8 source](https://github.com/WebKit/WebKit/blob/Safari-612.4.9.1.8/Source/WebKit/UIProcess/ios/forms/WKFileUploadPanel.mm), same key selectors.
- [iOS 15-era public WKUIDelegate header](https://github.com/WebKit/WebKit/blob/Safari-612.1.29.41.4/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegate.h): runOpenPanel callback declared macOS-only at that time. Do not rely on current iOS availability for iOS 15.

These are iOS 15-era sources, not proof of the exact installed 15.3.1 build. Resolve class/selectors on-device before installing hooks.

| Selector | Verified behavior | Hook recommendation |
| --- | --- | --- |
| `presentWithParameters:resultListener:` | Captures allowed types/multiple selection; opens camera when capture requires it, otherwise source-selection menu | Log route; do not replace listener pointer or C++ values |
| `showDocumentPickerMenu` | Presents Photos/Camera/Choose Files context menu for media | Replace with `showFilePickerMenu` if direct Files is desired; preserve existing capture path |
| `showFilePickerMenu` | Creates native import-mode UIDocumentPicker, accepted UTI filters, multiple-selection flag, own delegate | Call this original implementation |
| `_showPhotoPickerWithSourceType:` | Creates UIImagePicker with WebKit private flags and own delegate | Optional hook for non-camera source only, route to `showFilePickerMenu` |
| `documentPicker:didPickDocumentsAtURLs:` | Dismisses modal, coordinates moving imported copies to WebKit temporary directory, then calls its own listener | Leave intact |
| `documentPickerWasCancelled:` | Dismisses modal and cancels original listener | Leave intact |
| `_chooseFiles:displayString:iconImage:` | Sends actual paths into WebKit's open-panel listener and dismiss notification | Do not manually call unless target version validated |

The existing single-UIImagePicker callback is particularly unsafe for WebKit multiple uploads: `_willMultipleSelectionDelegateBeCalled` can cause WebKit to ignore `imagePickerController:didFinishPickingMediaWithInfo:` because it expects its private multiple-selection callback. A bridge that calls only the single result delegate can therefore show successful selection but deliver no upload.

This avoids synthesizing PHPickerResult for WebKit and preserves native upload File objects, accept filtering, multiple selection and WebKit sandbox extensions. The WebKit route must be marked to bypass the generic native picker replacement to avoid a second chooser.

Do not hook `_UIDocumentPickerRemoteViewController` to fake selection. The remote controller is the UI side of a document-provider boundary; selection only matters when the hosting API receives a valid provider URL and callback. The real UI layer may live out of process, while an embedded library lives in the target app. Intercept the hosting uploader or its native public delegate, which retains the true upload contract.

## Custom gallery/PHAsset boundary

There is no universal UIKit class that identifies every upload button or every proprietary gallery. A screen containing thumbnails does not tell a hook how to build the app's upload model. Apps can fetch PHAsset collections and use PHImageManager requests without ever presenting UIImagePicker or PHPicker. Detecting those calls can produce diagnostics, but globally replacing PHAsset or PHImageManager data would affect unrelated browsing/editing and misrepresent Photos identity.

A defensible next layer is a configurable app adapter: recognize that app's upload/gallery controller and selection callback, stage user-selected Files URLs, then construct its own image/file upload model through verified selectors. Match bundle ID + app version + callback signature. A user-triggered Files overlay can collect media, but without that adapter it cannot safely deliver into an arbitrary proprietary flow. No real app names/versions or callback trace were provided in this subtask, so none can be claimed supported.

## Required acceptance evidence

1. Embedded framework load-command injection into an unpatched harness, rather than compiling the same implementation directly into its host.
2. Load acknowledgment inside the patched app; adapter name and detection reason visible on device.
3. PHPicker delegate implemented in Swift as well as Objective-C; actual real result bridge, UIImage/data/file loads, original dismissal and cancel exactly once; selection cardinality and staged retention.
4. WKWebView local HTML input image/multiple plus JavaScript FileReader or actual multipart upload endpoint; prove selected bytes reach page, not merely picker disappears. Camera capture should keep working.
5. Negative cases: only-identifiers/preselection, live-photo-only, editing, unknown callbacks, missing private selectors fall back without crashes.
6. Physical iOS 15.3.1 + TrollStore install plus named real application/version. Current Simulator success cannot stand in for this gate.

## Research service outcomes

Exa: 21 result slots requested in three searches; useful public Apple docs, no private initializer discovery from Exa. Tavily: targeted WebKit and provider searches returned useful Apple/WebKit sources; large raw responses were filtered. Search1API: exact private-initializer query returned no results, ordinary PHPicker query returned public usage only. The decisive private selector came from GitHub code search and directly inspected runtime header files. Primary Apple/WebKit source was used for public behavior; reverse-engineered dumps are explicitly labeled and runtime-guarded.
