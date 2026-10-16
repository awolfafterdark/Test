import SwiftUI
import UniformTypeIdentifiers

@main
struct PickerPatcherApp: App {
    var body: some Scene {
        WindowGroup { PatcherView() }
    }
}

struct PatcherView: View {
    @State private var importing = false
    @State private var busy = false
    @State private var status = "Choose an unencrypted IPA you are authorized to modify."
    @State private var output: URL?
    @State private var sharing = false

    var body: some View {
        NavigationView {
            Form {
                Section("Patch an IPA") {
                    Button("Choose IPA from Files") { importing = true }
                        .disabled(busy)
                    if busy { ProgressView("Inspecting and patching…") }
                    Text(status).font(.footnote).textSelection(.enabled)
                }
                if let output = output {
                    Section("Result") {
                        Text(output.lastPathComponent).font(.footnote)
                        Button("Share IPA to TrollStore or Files") { sharing = true }
                        Button("Delete this exported IPA", role: .destructive) {
                            try? FileManager.default.removeItem(at: output)
                            self.output = nil
                            status = "Export deleted. The source IPA was not changed."
                        }
                    }
                }
                Section("Compatibility") {
                    Text("Thin arm64, unencrypted app executables with free Mach-O header padding. Apps containing extensions or nested apps are rejected. TrollStore signs the patched IPA when you install it.")
                        .font(.footnote)
                    Text("The original IPA is never modified. Installation and upload behavior must be tested for each target app.")
                        .font(.footnote)
                }
                Section {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("PickerPatcher")
        }
        .sheet(isPresented: $importing) {
            IPAFilePicker(isPresented: $importing) { url in
                startPatching(url)
            }
        }
        .onOpenURL { url in startPatching(url) }
        .sheet(isPresented: $sharing) {
            if let output = output { ShareSheet(items: [output]) }
        }
    }

    private func startPatching(_ url: URL) {
        guard !busy else { status = "Finish the current patch before choosing another IPA."; return }
        busy = true; output = nil; status = "Selected \(url.lastPathComponent). Inspecting IPA…"
        DispatchQueue.global(qos: .userInitiated).async {
            let response = Result { try IPAPatcher.patch(url) }
            DispatchQueue.main.async {
                busy = false
                switch response {
                case .success(let created):
                    output = created
                    status = "Patched IPA ready. Share it to TrollStore to install."
                case .failure(let error):
                    status = error.localizedDescription
                }
            }
        }
    }
}

struct IPAFilePicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Resolve the actual system type for the filename extension. TrollStore
        // uses this same initializer for its own IPA document picker.
        let ipa = UTType(filenameExtension: "ipa", conformingTo: .data)
            ?? UTType(importedAs: "com.apple.itunes.ipa", conformingTo: .data)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [ipa])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: IPAFilePicker
        init(parent: IPAFilePicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            guard let url = urls.first else { return }
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
