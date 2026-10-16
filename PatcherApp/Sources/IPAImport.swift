import Foundation

enum IPAImport {
    static func stage(_ source: URL) throws -> URL {
        guard source.isFileURL, source.pathExtension.lowercased() == "ipa" else {
            throw PatchFailure.invalid("Select a file ending in .ipa.")
        }
        let fm = FileManager.default
        let imports = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Imports", isDirectory: true)
        try fm.createDirectory(at: imports, withIntermediateDirectories: true)
        // Local entries need no duplicate. External Open In URLs still need a
        // coordinated copy while their security scope remains active.
        if source.standardizedFileURL.deletingLastPathComponent() == imports.standardizedFileURL,
           fm.isReadableFile(atPath: source.path) { return source }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var copyResult: Result<URL, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            copyResult = Result {
                let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
                    throw PatchFailure.invalid("The provider did not return a readable regular file.")
                }
                let attrs = try fm.attributesOfFileSystem(forPath: imports.path)
                let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
                guard free > Int64(size) + 128 * 1024 * 1024 else {
                    throw PatchFailure.invalid("Not enough space to import this IPA safely.")
                }
                var target = imports.appendingPathComponent(source.lastPathComponent)
                if fm.fileExists(atPath: target.path) {
                    target = imports.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).ipa")
                }
                do {
                    try fm.copyItem(at: readable, to: target)
                    guard fm.isReadableFile(atPath: target.path) else { throw PatchFailure.invalid("Imported file is unreadable.") }
                    return target
                } catch { try? fm.removeItem(at: target); throw error }
            }
        }
        if let result = copyResult { return try result.get() }
        throw coordinationError ?? NSError(domain: "PickerPatcher.Import", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Files did not provide access to the selected IPA."])
    }
}
