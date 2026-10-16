import UIKit
import UniformTypeIdentifiers

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let patcher = PatcherController(style: .insetGrouped)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: patcher)
        window.makeKeyAndVisible()
        self.window = window
        if let url = options?[.url] as? URL { patcher.receive(url, origin: "launch URL") }
        return true
    }
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        patcher.receive(url, origin: "Open In")
        return true
    }
}

// UIKit owns presentation directly. This object is retained by the navigation
// controller for the whole app lifetime; UIDocumentPickerDelegate is weak.
final class PatcherController: UITableViewController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    private var picker: UIDocumentPickerViewController?
    private var didReceiveSelection = false
    private var busy = false
    private var selected: URL?
    private var output: URL?
    private var localIPAs: [URL] = []
    private var status = "Choose an IPA, check its selection below, then tap Patch selected IPA."
    private var events: [String] = []
    private let fm = FileManager.default
    private var imports: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Imports", isDirectory: true) }
    private var displayName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "PickerPatcher" }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = displayName
        tableView.accessibilityIdentifier = "patcherTable"
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: UIApplication.didBecomeActiveNotification, object: nil)
        let previousLog = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PickerPatcher-diagnostics.txt")
        events = (try? String(contentsOf: previousLog, encoding: .utf8))?.split(separator: "\n").suffix(100).map(String.init) ?? []
        record("launch iOS \(UIDevice.current.systemVersion); build 0.6.0 (6)")
        do {
            try fm.createDirectory(at: imports, withIntermediateDirectories: true)
            if ProcessInfo.processInfo.arguments.contains("--picker-uitest"),
               let fixture = Bundle.main.url(forResource: "PickerHarness", withExtension: "ipa") {
                let target = imports.appendingPathComponent("PickerHarness.ipa")
                if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: fixture, to: target) }
            }
        } catch { record("create Imports failed: \(error.localizedDescription)") }
        refresh()
    }

    @objc private func refresh() {
        localIPAs = ((try? fm.contentsOfDirectory(at: imports, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension.lowercased() == "ipa" && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if isViewLoaded { tableView.reloadData() }
    }

    private func record(_ event: String) {
        assert(Thread.isMainThread)
        events.append("\(ISO8601DateFormatter().string(from: Date())) \(event)")
        if events.count > 120 { events.removeFirst(events.count - 120) }
        // No selected filenames, full paths, file contents or remote URLs in logs.
        let logURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PickerPatcher-diagnostics.txt")
        try? events.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func choose(legacy: Bool) {
        guard !busy, picker == nil, presentedViewController == nil else { return }
        didReceiveSelection = false
        // Broad type intentionally avoids a dynamic IPA UTI disabling valid archives.
        // Validate extension and contents after selection. Both modes import a copy.
        let document: UIDocumentPickerViewController
        if legacy {
            document = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
        } else {
            document = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        }
        document.delegate = self
        document.allowsMultipleSelection = false
        document.shouldShowFileExtensions = true
        document.directoryURL = imports
        document.modalPresentationStyle = .fullScreen
        picker = document
        status = "Files is open. A cloud download may finish before selection returns."
        record("picker requested mode=\(legacy ? "legacy-import" : "copy-import"); delegate retained; main thread")
        tableView.reloadData()
        present(document, animated: true) { [weak self, weak document] in
            guard let self = self, let document = document else { return }
            document.presentationController?.delegate = self
            self.record("picker presented; delegate attached=\(document.delegate === self)")
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        accept(controller, urls: urls, callback: "didPickDocumentsAtURLs")
    }
    // Compatibility entry point: iOS 15 reports exist for the singular callback.
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        accept(controller, urls: [url], callback: "didPickDocumentAtURL")
    }
    private func accept(_ controller: UIDocumentPickerViewController, urls: [URL], callback: String) {
        record("\(callback) received; active picker=\(picker != nil); controller matches=\(controller === picker); duplicate=\(didReceiveSelection)")
        guard controller === picker, !didReceiveSelection else { return }
        didReceiveSelection = true
        record("\(callback); count=\(urls.count)")
        close(controller) { [weak self] in
            guard let self = self else { return }
            if let url = urls.first { self.receive(url, origin: "picker copy") }
            else { self.status = "Files returned no document."; self.refresh() }
        }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard controller === picker else { return }
        record("picker cancelled; selection callback received=\(didReceiveSelection)")
        close(controller) { [weak self] in
            self?.status = "Selection cancelled. If tapping a file did nothing, share the diagnostics below."
            self?.refresh()
        }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === picker else { return }
        record("picker dismissed interactively")
        picker = nil
        refresh()
    }
    private func close(_ controller: UIDocumentPickerViewController, completion: @escaping () -> Void) {
        let finish = { [weak self] in
            self?.picker = nil
            self?.record("picker closed")
            completion()
        }
        if controller.presentingViewController != nil { controller.dismiss(animated: true, completion: finish) }
        else { finish() }
    }

    func receive(_ url: URL, origin: String) {
        guard !busy else { return }
        busy = true
        status = "Selection received. Making the IPA available locally…"
        record("selection received via \(origin)")
        if isViewLoaded { tableView.reloadData() }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try IPAImport.stage(url) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let local):
                    self.selected = local
                    self.status = "Selected \(local.lastPathComponent). Ready to patch."
                    self.record("import complete; local IPA readable")
                case .failure(let error):
                    self.selected = nil
                    self.status = "Import failed: \(error.localizedDescription)"
                    self.record("import failed: \((error as NSError).domain) code=\((error as NSError).code)")
                }
                self.refresh()
            }
        }
    }
    private func patch() {
        guard !busy, let selected = selected else { return }
        busy = true
        status = "Inspecting archive and patching…"
        record("patch started")
        tableView.reloadData()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try IPAPatcher.patch(selected) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let url): self.output = url; self.status = "Patched IPA ready."; self.record("patch succeeded")
                case .failure(let error): self.status = "Patch failed: \(error.localizedDescription)"; self.record("patch rejected")
                }
                self.refresh()
            }
        }
    }
    private func share(_ url: URL, from indexPath: IndexPath) {
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        share.popoverPresentationController?.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
        present(share, animated: true)
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return 1; case 1: return 4; case 2: return 2 + localIPAs.count; case 3: return output == nil ? 1 : 3; default: return 3 }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Build", "Import and patch", "Local IPAs", "Export", "Diagnostics and compatibility"][section]
    }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        var action = false
        switch (path.section, path.row) {
        case (0, _): cell.textLabel?.text = "Build 0.6.0 (6) · iOS 15+"; cell.detailTextLabel?.text = "Native UIKit import · selection shown before patching"
        case (1, 0): cell.textLabel?.text = "Choose IPA from Files"; cell.accessibilityIdentifier = "chooseIPA"; action = true
        case (1, 1): cell.textLabel?.text = "Try compatibility import"; action = true
        case (1, 2): cell.textLabel?.text = selected?.lastPathComponent ?? "No IPA selected"; cell.detailTextLabel?.text = status; cell.accessibilityIdentifier = "selectionStatus"; cell.detailTextLabel?.accessibilityIdentifier = "statusMessage"
        case (1, 3): cell.textLabel?.text = "Patch selected IPA"; cell.accessibilityIdentifier = "patchSelected"; action = selected != nil
        case (2, 0): cell.textLabel?.text = "Refresh local IPAs"; action = true
        case (2, 1): cell.textLabel?.text = "Files → On My iPod/iPhone → \(displayName) → Imports"; cell.detailTextLabel?.text = "You can also share an IPA from Files using Open In."
        case (2, _): cell.textLabel?.text = localIPAs[path.row - 2].lastPathComponent; action = true
        case (3, 0): cell.textLabel?.text = output == nil ? "No patched IPA yet" : "Share patched IPA to TrollStore or Files"; cell.accessibilityIdentifier = "sharePatched"; action = output != nil
        case (3, 1): cell.textLabel?.text = "Delete exported IPA"; action = true
        case (3, 2): cell.textLabel?.text = output?.lastPathComponent
        case (4, 0): cell.textLabel?.text = "Share diagnostics"; action = true
        case (4, 1): cell.textLabel?.text = "Create picker test IPA"; cell.detailTextLabel?.text = "Copies a small, unencrypted test app into Imports. Select it through Files, then patch it."; cell.accessibilityIdentifier = "createFixture"; action = true
        default: cell.textLabel?.text = "Standard UIImagePickerController image/video flows only. PHPicker, editing, Photos asset identities and custom galleries retain their original UI."; cell.detailTextLabel?.text = "Actual target apps require upload testing."
        }
        if cell.accessibilityIdentifier == "selectionStatus" {
            cell.isAccessibilityElement = false
            cell.textLabel?.isAccessibilityElement = true
            cell.detailTextLabel?.isAccessibilityElement = true
        }
        cell.selectionStyle = action && !busy ? .default : .none
        cell.textLabel?.textColor = action ? (busy ? .secondaryLabel : .systemBlue) : .label
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        guard !busy else { return }
        switch (path.section, path.row) {
        case (1, 0): choose(legacy: false)
        case (1, 1): choose(legacy: true)
        case (1, 3): patch()
        case (2, 0): refresh()
        case (2, let row) where row >= 2: receive(localIPAs[row - 2], origin: "local Imports")
        case (3, 0): if let output = output { share(output, from: path) }
        case (3, 1): if let output = output { try? fm.removeItem(at: output); self.output = nil; refresh() }
        case (4, 0): share(fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PickerPatcher-diagnostics.txt"), from: path)
        case (4, 1):
            if let fixture = Bundle.main.url(forResource: "PickerHarness", withExtension: "ipa") { receive(fixture, origin: "bundled test app") }
        default: break
        }
    }
}
