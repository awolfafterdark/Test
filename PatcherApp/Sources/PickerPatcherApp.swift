import SwiftUI
import UniformTypeIdentifiers

@main
struct PickerPatcherApp: App {
    var body: some Scene {
        WindowGroup { PatcherView() }
    }
}

struct PatcherView: View {
    // iOS Files exposes .ipa using com.apple.itunes.ipa. Using only .item in
    // fileImporter can leave the document visible but not selectable on iOS 15.
    private let ipaType = UTType(importedAs: "com.apple.itunes.ipa", conformingTo: .data)
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
            }
            .navigationTitle("PickerPatcher")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [ipaType, .data]) { result in
            switch result {
            case .success(let url): startPatching(url)
            case .failure(let error): status = error.localizedDescription
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
