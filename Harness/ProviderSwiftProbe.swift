import UIKit
import PhotosUI

// Apple's delegate overlay bridges the Objective-C PHPickerResult objects to
// Swift value types. Exercise that real callback, rather than casting an array
// through a made-up Objective-C helper signature.
@objc(PPProviderDelegate)
final class ProviderDelegate: NSObject, PHPickerViewControllerDelegate {
    private weak var resultLabel: UILabel?
    @objc(initWithResultLabel:)
    init(resultLabel: UILabel) {
        self.resultLabel = resultLabel
        super.init()
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let presented = picker.presentingViewController != nil
        picker.dismiss(animated: true) {
            let dismissed = picker.presentingViewController == nil
            guard !results.isEmpty else {
                self.resultLabel?.text = presented && dismissed ? "PASS php cancel; presenter=yes; dismiss=yes" : "FAIL php cancel"
                return
            }
            let group = DispatchGroup(), lock = NSLock()
            var objects = 0, dataLoads = 0, files = 0
            let identities = results.allSatisfy { $0.assetIdentifier == nil }
            for result in results {
                let provider = result.itemProvider
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, error in
                    lock.lock(); if object is UIImage && error == nil { objects += 1 }; lock.unlock()
                    group.leave()
                }
                let type = provider.registeredTypeIdentifiers.first ?? "public.png"
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    lock.lock(); if let data = data, !data.isEmpty, error == nil { dataLoads += 1 }; lock.unlock()
                    group.leave()
                }
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    // Provider file lifetimes end after this callback; read here.
                    let data = url.flatMap { try? Data(contentsOf: $0) }
                    lock.lock(); if let data = data, !data.isEmpty, error == nil { files += 1 }; lock.unlock()
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                let valid = presented && dismissed && identities && objects == results.count && dataLoads == results.count && files == results.count
                self.resultLabel?.text = "\(valid ? "PASS" : "FAIL") providers; count=\(results.count); object=\(objects == results.count ? "yes" : "no"); data=\(dataLoads == results.count ? "yes" : "no"); file=\(files == results.count ? "yes" : "no"); identities=\(identities ? "nil" : "unexpected"); dismiss=\(dismissed ? "yes" : "no"); swift=yes"
            }
        }
    }
}
