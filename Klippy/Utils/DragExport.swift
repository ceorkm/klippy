import AppKit
import UniformTypeIdentifiers

/// Writes a clip's image to a real file so it can be dragged into other apps.
///
/// Dragging used to hand over an `NSImage`, which only apps that accept raw
/// image data would take. Cursor, Terminal, Finder and most editors want a
/// *file*, so the drag simply did nothing there. Writing a PNG first and
/// dragging its URL works everywhere, and image-accepting apps still get PNG
/// data because the provider advertises both.
enum DragExport {
    /// One folder per launch, cleared on quit, so dragged files do not pile up.
    private static let folder: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KlippyDrags", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static var written: [UUID: URL] = [:]
    private static let lock = NSLock()
    private static let maxWritten = 256

    /// A PNG on disk for this clip, written once and reused.
    static func imageFile(for id: UUID, image: NSImage, createdAt: Date) -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let existing = written[id],
           FileManager.default.fileExists(atPath: existing.path) { return existing }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }

        // Full id in the name: the old 4-letter prefix could land two drags
        // in the same second on the same file.
        let url = folder.appendingPathComponent("\(name(for: createdAt))-\(id.uuidString).png")
        do {
            try png.write(to: url)
        } catch {
            return nil
        }
        written[id] = url
        // Cap the map, not the files: an in-flight drag may still be reading
        // one, so evicted entries simply get rewritten on next drag. The
        // folder itself is cleared on quit.
        if written.count > maxWritten, let oldest = written.keys.first {
            written.removeValue(forKey: oldest)
        }
        return url
    }

    /// A drag payload carrying the file and the image data behind it.
    static func provider(for id: UUID, image: NSImage, createdAt: Date) -> NSItemProvider {
        guard let url = imageFile(for: id, image: image, createdAt: createdAt),
              let provider = NSItemProvider(contentsOf: url) else {
            return NSItemProvider(object: image)
        }
        provider.suggestedName = url.lastPathComponent
        return provider
    }

    /// Names files by when the clip was copied, so a folder of them sorts
    /// sensibly instead of reading as a wall of identifiers.
    private static func name(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Klippy-\(formatter.string(from: date))"
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        written.removeAll()
        try? FileManager.default.removeItem(at: folder)
    }
}
