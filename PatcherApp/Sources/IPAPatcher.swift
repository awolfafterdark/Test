import Foundation
import ZIPFoundation

enum PatchFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum IPAPatcher {
    private static let loadPath = "@executable_path/Frameworks/PickerPatcherEmbedded.framework/PickerPatcherEmbedded"
    private static let maxExpanded: Int64 = 4 * 1024 * 1024 * 1024
    private static let fm = FileManager.default

    static func patch(_ input: URL) throws -> URL {
        guard input.pathExtension.lowercased() == "ipa" else {
            throw PatchFailure.invalid("Choose a .ipa file.")
        }
        let accessed = input.startAccessingSecurityScopedResource()
        defer { if accessed { input.stopAccessingSecurityScopedResource() } }

        let archive = try Archive(url: input, accessMode: .read)
        var expanded: Int64 = 0
        var appNames = Set<String>()
        var paths = Set<String>()
        for entry in archive {
            guard paths.count < 100_000 else {
                throw PatchFailure.invalid("IPA contains too many entries.")
            }
            let path = entry.path
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
                  !parts.contains(".."), !parts.contains("."),
                  !paths.contains(path), entry.type != .symlink else {
                throw PatchFailure.invalid("Unsafe archive entry: \(path)")
            }
            paths.insert(path)
            guard entry.uncompressedSize <= UInt64(maxExpanded),
                  expanded <= maxExpanded - Int64(entry.uncompressedSize) else {
                throw PatchFailure.invalid("IPA expands beyond the 4 GiB limit.")
            }
            expanded += Int64(entry.uncompressedSize)
            if entry.uncompressedSize > 100 * 1024 * 1024 &&
               entry.compressedSize < entry.uncompressedSize / 1000 {
                throw PatchFailure.invalid("IPA contains an extreme compression ratio.")
            }
            if parts.count >= 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") {
                appNames.insert(parts[1])
            }
            if parts.contains(where: { $0.hasSuffix(".appex") }) ||
               (parts.dropFirst(2).contains { $0.hasSuffix(".app") }) {
                throw PatchFailure.invalid("App extensions or nested apps need separate signing and are unsupported.")
            }
        }
        guard appNames.count == 1, let appName = appNames.first else {
            throw PatchFailure.invalid("IPA must contain exactly one Payload/*.app.")
        }
        let workspace = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stage = workspace.appendingPathComponent("stage", isDirectory: true)
        let results = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Patched", isDirectory: true)
        try fm.createDirectory(at: results, withIntermediateDirectories: true)
        let attrs = try fm.attributesOfFileSystem(forPath: results.path)
        let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let sourceSize = (try fm.attributesOfItem(atPath: input.path)[.size] as? NSNumber)?.int64Value ?? 0
        // Extracted tree + output archive + a margin; source IPA remains in place.
        let required = expanded > (Int64.max - sourceSize - 256*1024*1024)/2
            ? Int64.max : expanded * 2 + sourceSize + 256*1024*1024
        guard free >= required else {
            throw PatchFailure.invalid("Insufficient space: need about \(required / 1_048_576) MiB free for this IPA.")
        }
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }
        try fm.unzipItem(at: input, to: stage)

        let app = stage.appendingPathComponent("Payload/\(appName)", isDirectory: true)
        let info = app.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: info),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = plist["CFBundleExecutable"] as? String,
              name == URL(fileURLWithPath: name).lastPathComponent,
              let bundleID = plist["CFBundleIdentifier"] as? String,
              !bundleID.isEmpty, bundleID.count <= 255,
              bundleID.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0)
              }) else {
            throw PatchFailure.invalid("Malformed app Info.plist.")
        }
        let executable = app.appendingPathComponent(name)
        guard fm.fileExists(atPath: executable.path) else {
            throw PatchFailure.invalid("Main app executable is missing.")
        }
        let target = app.appendingPathComponent("Frameworks/PickerPatcherEmbedded.framework", isDirectory: true)
        guard !fm.fileExists(atPath: target.path),
              let payload = Bundle.main.url(forResource: "Payload", withExtension: "zip") else {
            throw PatchFailure.invalid("Embedded picker framework is unavailable or already present.")
        }
        let unpackPayload = workspace.appendingPathComponent("payload", isDirectory: true)
        try fm.unzipItem(at: payload, to: unpackPayload)
        let framework = unpackPayload.appendingPathComponent("PickerPatcherEmbedded.framework", isDirectory: true)
        guard fm.fileExists(atPath: framework.appendingPathComponent("PickerPatcherEmbedded").path) else {
            throw PatchFailure.invalid("Picker framework payload is damaged.")
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: framework, to: target)
        var error = [CChar](repeating: 0, count: 256)
        let patched = executable.path.withCString { binary in
            loadPath.withCString { dylib in
                PPInjectDylib(binary, dylib, &error, error.count)
            }
        }
        guard patched == 0 else {
            throw PatchFailure.invalid(String(cString: error))
        }
        let output = results.appendingPathComponent("\(bundleID)-\(UUID().uuidString.prefix(8)).ipa")
        let partial = workspace.appendingPathComponent("output.ipa")
        try fm.zipItem(at: stage, to: partial, shouldKeepParent: false, compressionMethod: .deflate)
        _ = try Archive(url: partial, accessMode: .read)
        try fm.moveItem(at: partial, to: output)
        return output
    }
}
