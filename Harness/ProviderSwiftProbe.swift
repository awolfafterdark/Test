import Foundation
import PhotosUI

// This forces Apple's Objective-C-to-Swift PHPickerResult bridge to run, rather
// than checking only Objective-C getters on the supplied result objects.
@objc(PPProviderProbe)
final class ProviderProbe: NSObject {
    @objc static func verify(_ results: [PHPickerResult]) -> Bool {
        !results.isEmpty && results.allSatisfy {
            $0.assetIdentifier == nil && !$0.itemProvider.registeredTypeIdentifiers.isEmpty
        }
    }
}
