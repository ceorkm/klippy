import Foundation
import AppKit
import CoreData
import Combine
import UniformTypeIdentifiers
import ImageIO

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var monitoringTimer: Timer?
    private let contentClassifier = ContentClassifier()
    
    // Core Data context for background operations
    private lazy var backgroundContext: NSManagedObjectContext = {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()
    
    // Published properties for UI updates
    @Published var totalItemCount: Int = 0
    @Published var recentItems: [ClipboardItemViewModel] = []
    @Published private(set) var favoriteItemIDs: Set<UUID> = []
    
    // Performance optimization: Cache for recent items
    var itemCache: [ClipboardItemViewModel] = []
    private let cacheSize = 1000
    
    // Duplicate detection
    var recentHashes: Set<String> = []
    private let maxRecentHashes = 10000
    // Short-window text dedup: catches voice-to-text apps that write the same
    // content twice in quick succession. Doesn't block intentional re-copies later.
    /// Change count of a write Klippy made itself. Copying a clip back out puts
    /// it on the pasteboard, which the monitor then sees as brand new content and
    /// stores a second time. Hash dedup does not catch it, because it only
    /// compares against the previous capture, and a recalled clip is older than
    /// that. Without this, every copy-back-out duplicated the clip.
    private var selfWriteChangeCount: Int?
    private var lastTextHash: String?
    private var lastTextTimestamp: Date?
    private let textDedupWindow: TimeInterval = 2.0
    private let favoritesDefaultsKey = "klippy.favoriteItemIDs"

    private struct ExportClipboardItem: Codable {
        let id: String
        let content: String
        let categoryRawValue: Int16
        let categoryName: String
        let isFavorite: Bool
        let createdAt: Date
        let lastAccessedAt: Date
        let usageCount: Int32
        let sourceApplication: String?
        let tags: String?
        let isImage: Bool
        let imageWidth: Int32
        let imageHeight: Int32
        let imageDataBase64: String?
    }

    private struct ExportEnvelope: Codable {
        let exportVersion: Int
        let exportedAt: Date
        let totalItems: Int
        let items: [ExportClipboardItem]
    }
    
    private init() {
        favoriteItemIDs = loadFavoriteIDs()
        refreshHistory()

        // Startup fallback: persistent stores can finish loading slightly after manager init.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshHistory()
            self?.reclassifyFakeFileClipsIfNeeded()
        }
    }

    /// Refiles stored clips whenever the classifier's rules have moved on.
    ///
    /// The classifier decides a clip's category once, at capture, so improving
    /// a rule does nothing for the clips already in the library. Several rules
    /// used to ask whether the text *contained* something of the right shape
    /// rather than whether it *was* that thing, which mislabelled thousands of
    /// clips: prose became addresses, log files became dates, React sources
    /// became markdown.
    ///
    /// Bump `classifierGeneration` after changing a rule and every stored clip
    /// gets looked at once more. Images are left alone: their category comes
    /// from the data, not the text.
    private static let classifierGeneration = 6

    private func reclassifyFakeFileClipsIfNeeded() {
        let flag = "didReclassifyContent_gen\(Self.classifierGeneration)"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }

        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            let started = Date()
            let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
            request.predicate = NSPredicate(format: "isImage == NO")
            request.fetchBatchSize = 500

            do {
                let items = try self.backgroundContext.fetch(request)
                var changed = 0
                for item in items {
                    guard let content = item.content, !content.isEmpty else { continue }

                    // A stored file bundle or a real path is authoritative: it
                    // was recorded from the pasteboard, not guessed from text.
                    if item.contentType == ContentCategory.file.rawValue {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("klippy-file-bundle-v2:")
                            || trimmed.hasPrefix("/")
                            || trimmed.hasPrefix("~/")
                            || trimmed.hasPrefix("file://") { continue }
                    }

                    let resolved = self.contentClassifier.classify(content).rawValue
                    if resolved != item.contentType {
                        item.contentType = resolved
                        changed += 1
                    }
                }
                if changed > 0 { try self.backgroundContext.save() }
                UserDefaults.standard.set(true, forKey: flag)
                let seconds = Date().timeIntervalSince(started)
                print("Refiled \(changed) of \(items.count) clips in \(String(format: "%.1f", seconds))s")
                if changed > 0 {
                    DispatchQueue.main.async { self.refreshHistory() }
                }
            } catch {
                print("Reclassification failed: \(error)")
            }
        }
    }

    /// Stores dropped images directly, without going through the pasteboard.
    ///
    /// Dropping several pictures used to write each one to the general
    /// pasteboard in turn. Capture polls ten times a second, so a drop of
    /// twenty images overwrote itself and only a couple were ever recorded.
    /// Writing straight to the store keeps every one of them, in order.
    func startMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        lastChangeCount = pasteboard.changeCount

        // Keep polling active even while menu-bar UI is open (event tracking mode).
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkForClipboardChanges()
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        monitoringTimer = timer

        print("Clipboard monitoring started (checking every 0.1s)")
        print("Initial change count: \(lastChangeCount)")
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        print("Clipboard monitoring stopped")
    }
    
    // MARK: - Clipboard Change Detection
    
    private func checkForClipboardChanges() {
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount

        // Klippy's own write, from clicking a clip, is not a new copy. Without
        // this every recall put the clip back into the history a second time:
        // roughly a quarter of the library was duplicates created this way.
        if let selfWrite = selfWriteChangeCount, selfWrite == currentChangeCount {
            selfWriteChangeCount = nil
            return
        }

        // Password managers and throwaway copies are marked on the pasteboard.
        // Honour that before anything reads or hashes the content.
        guard !ClipboardPrivacy.shouldSkip(pasteboard) else { return }

        processClipboardContent()
    }
    
    private func processClipboardContent() {
        // Get the current clipboard content
        let clipboardData = getClipboardContent()

        // Several images copied together become one clip each, so they show up
        // in the Images tab as thumbnails instead of as a filename list.
        if let batch = clipboardData.imageBatch, !batch.isEmpty {
            Task { @MainActor in
                var stored = 0
                for payload in batch {
                    let hash = payload.data.sha256
                    guard !recentHashes.contains(hash) else { continue }
                    recentHashes.insert(hash)
                    await saveImageClipboardItem(imageData: payload.data,
                                                 imageSize: payload.size,
                                                 hash: hash)
                    stored += 1
                }
                if stored > 0 { refreshHistory() }
            }
            return
        }

        // Determine content hash based on what we have
        let contentHash: String
        let contentType: String
        if let imageData = clipboardData.imageData {
            contentHash = imageData.sha256
            contentType = "image"
            print("Processing image: \(imageData.count) bytes, hash: \(String(contentHash.prefix(8)))...")
        } else if let content = clipboardData.content {
            // A clip of nothing but spaces and newlines is not worth a row. It
            // is unsearchable, shows as a blank card, and pasting it back does
            // nothing. File bundles are exempt: their content is encoded, so it
            // is never whitespace.
            if clipboardData.categoryOverride != .file,
               content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
            if clipboardData.categoryOverride == .file {
                contentHash = canonicalFileBundleHash(from: content)
                contentType = "file-bundle"
            } else {
                contentHash = content.sha256
                contentType = "text"
            }
            print("Processing text, hash: \(String(contentHash.prefix(8)))...")
        } else {
            print("No content to process")
            return // No content to process
        }

        // Non-text content: permanent dedup via recentHashes.
        // Text: short-window dedup only (catches apps that write twice in rapid succession
        // like voice-to-text, but still allows intentional re-copy of the same text later).
        if contentType == "text" {
            if let lastHash = lastTextHash,
               let lastTime = lastTextTimestamp,
               lastHash == contentHash,
               Date().timeIntervalSince(lastTime) < textDedupWindow {
                print("Duplicate text within \(textDedupWindow)s window, skipping")
                return
            }
            lastTextHash = contentHash
            lastTextTimestamp = Date()
        } else {
            if recentHashes.contains(contentHash) {
                print("Duplicate \(contentType) detected, skipping")
                return
            }
            recentHashes.insert(contentHash)
            if recentHashes.count > maxRecentHashes {
                let hashesToRemove = Array(recentHashes.prefix(recentHashes.count - maxRecentHashes))
                hashesToRemove.forEach { recentHashes.remove($0) }
            }
        }

        print("New \(contentType) content, adding to history")

        // Process in background to avoid blocking UI
        Task {
            if let imageData = clipboardData.imageData, let imageSize = clipboardData.imageSize {
                await saveImageClipboardItem(imageData: imageData, imageSize: imageSize, hash: contentHash)
            } else if let content = clipboardData.content {
                await saveClipboardItem(
                    content: content,
                    hash: contentHash,
                    categoryOverride: clipboardData.categoryOverride
                )
            }
        }
    }
    
    private func getClipboardContent() -> (
        content: String?,
        imageData: Data?,
        imageSize: NSSize?,
        categoryOverride: ContentCategory?,
        imageBatch: [(data: Data, size: NSSize)]?
    ) {
        // PRIORITY 1: Preserve file/document references as real file URLs.
        // Finder often includes an icon image on the pasteboard; file URLs must win.
        // However, code editors (Electron apps like Cursor/VS Code) put the SOURCE
        // file's URL on the pasteboard alongside the copied text. When plain text is
        // present, it's a text copy — not a file copy. Only treat as file when there
        // is NO plain text on the pasteboard.
        // The question is not "is there text" but "is that text these files".
        //
        // Finder always writes the display name alongside the file URL, so a
        // plain "is there text" guard skipped every Finder copy: a single image
        // survived only because the image path reads it off disk separately,
        // and copying several files degraded into a list of bare names with the
        // paths thrown away. Cursor and VS Code, which put the source file's
        // URL next to copied code, are still excluded because their text has
        // nothing to do with the URL.
        if let fileURLs = readFileURLsFromPasteboard(), !fileURLs.isEmpty,
           plainTextDescribes(fileURLs) {
            let fileReferences = makeFileReferences(from: fileURLs)

            if fileReferences.count == 1,
               let imagePayload = imagePayloadFromFileReference(fileReferences[0]) {
                print("Image file URL detected and normalized to image content")
                return (
                    content: nil,
                    imageData: imagePayload.data,
                    imageSize: imagePayload.size,
                    categoryOverride: .image
                , imageBatch: nil)
            }

            // Several pictures copied at once are pictures, not a file list.
            // They used to land as one file clip, so the Images tab never saw
            // them and each thumbnail was lost behind a filename.
            if fileReferences.count > 1,
               fileReferences.allSatisfy({ isImageFileURL($0.url) }) {
                let payloads = fileReferences.compactMap(imagePayloadFromFileReference)
                if payloads.count == fileReferences.count {
                    print("\(payloads.count) image files detected, storing each as an image")
                    return (
                        content: nil,
                        imageData: nil,
                        imageSize: nil,
                        categoryOverride: .image,
                        imageBatch: payloads
                    )
                }
            }

            let serialized = serializeFileReferences(fileReferences)
            print("File URLs detected: \(fileURLs.count)")
            return (content: serialized, imageData: nil, imageSize: nil, categoryOverride: .file, imageBatch: nil)
        }

        // PRIORITY 2: Check for images with enhanced detection.
        if let imageData = getImageFromPasteboard() {
            let image = NSImage(data: imageData)
            let size = image?.size ?? NSSize.zero
            print("Image detected and prioritized over text content")
            return (content: nil, imageData: imageData, imageSize: size, categoryOverride: .image, imageBatch: nil)
        }

        // PRIORITY 3: Try alternative image detection before text fallback.
        print("Primary image detection failed, trying alternative methods...")
        if let imageData = tryAlternativeImageDetection() {
            let image = NSImage(data: imageData)
            let size = image?.size ?? NSSize.zero
            print("Found image data using alternative detection!")
            return (content: nil, imageData: imageData, imageSize: size, categoryOverride: .image, imageBatch: nil)
        }

        // PRIORITY 4: Check if we have text that might be masking an image.
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            print("Found text content (\(string.count) chars)")

            // If the text looks like a filename, we already tried alternative detection above
            if isLikelyImageFilename(string) {
                print("Text looks like image filename but no image data found: \(string)")
            }

            // Guard against HTML-stripped text from Electron apps (e.g. Cursor).
            // When the plain text is suspiciously short but HTML is available,
            // the app likely put HTML on the pasteboard and the plain text was
            // derived by stripping tags — which nukes XML/HTML-like content.
            let htmlType = NSPasteboard.PasteboardType.html
            if string.trimmingCharacters(in: .whitespacesAndNewlines).count < 4,
               let htmlData = pasteboard.data(forType: htmlType),
               let attrString = NSAttributedString(
                   html: htmlData,
                   options: [.characterEncoding: String.Encoding.utf8.rawValue],
                   documentAttributes: nil
               ) {
                let recovered = attrString.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if recovered.count > string.count {
                    print("Recovered longer text from HTML pasteboard (\(recovered.count) chars)")
                    return (content: recovered, imageData: nil, imageSize: nil, categoryOverride: nil, imageBatch: nil)
                }
            }

            return (content: string, imageData: nil, imageSize: nil, categoryOverride: nil, imageBatch: nil)
        }

        // PRIORITY 5: Try HTML pasteboard when plain text is absent.
        let htmlType = NSPasteboard.PasteboardType.html
        if let htmlData = pasteboard.data(forType: htmlType),
           let attrString = NSAttributedString(
               html: htmlData,
               options: [.characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil
           ) {
            let text = attrString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                print("Recovered text from HTML pasteboard (\(text.count) chars)")
                return (content: text, imageData: nil, imageSize: nil, categoryOverride: nil, imageBatch: nil)
            }
        }

        // Handle other text-like types (URLs, etc.)
        if let url = pasteboard.string(forType: .URL) {
            print("Fell through to .URL fallback: \(url.prefix(80))")
            return (content: url, imageData: nil, imageSize: nil, categoryOverride: .url, imageBatch: nil)
        }

        if let fileURL = pasteboard.string(forType: .fileURL) {
            print("Fell through to .fileURL fallback: \(fileURL.prefix(80))")
            return (content: fileURL, imageData: nil, imageSize: nil, categoryOverride: .file, imageBatch: nil)
        }

        // Handle RTF content
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            return (content: attributedString.string, imageData: nil, imageSize: nil, categoryOverride: .text, imageBatch: nil)
        }

        return (content: nil, imageData: nil, imageSize: nil, categoryOverride: nil, imageBatch: nil)
    }

    /// True when the pasteboard's text is just a description of these files,
    /// which is what a file copy looks like, rather than content of its own.
    private func plainTextDescribes(_ urls: [URL]) -> Bool {
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return true  // no competing text at all
        }

        let lines = text
            .split(whereSeparator: { $0.isNewline || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty, lines.count <= urls.count else { return false }

        // Finder writes display names; some apps write full paths.
        var described = Set<String>()
        for url in urls {
            described.insert(url.lastPathComponent)
            described.insert(url.path)
            described.insert(url.deletingPathExtension().lastPathComponent)
        }
        return lines.allSatisfy { described.contains($0) }
    }

    private func readFileURLsFromPasteboard() -> [URL]? {
        var collected: [URL] = []
        let readingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: readingOptions) as? [URL] {
            collected.append(contentsOf: objects.filter(\.isFileURL))
        }

        if collected.isEmpty, let items = pasteboard.pasteboardItems {
            for item in items {
                if let fileURLString = item.string(forType: .fileURL) {
                    collected.append(contentsOf: parseFileURLs(from: fileURLString))
                    continue
                }

                if let rawString = item.string(forType: .string) {
                    collected.append(contentsOf: parseFileURLs(from: rawString))
                }
            }
        }

        let deduplicated = deduplicatedFileURLs(collected.filter(\.isFileURL))
        return deduplicated.isEmpty ? nil : deduplicated
    }

    private func parseFileURLs(from rawText: String) -> [URL] {
        rawText
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> URL? in
                let candidate = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty else { return nil }

                if let url = URL(string: candidate), url.isFileURL {
                    return url
                }

                // Fallback for absolute/tilde paths that may come via plain string flavor.
                if candidate.hasPrefix("/") || candidate.hasPrefix("~/") {
                    let expandedPath = (candidate as NSString).expandingTildeInPath
                    return URL(fileURLWithPath: expandedPath)
                }

                return nil
            }
    }

    private func makeFileReferences(from urls: [URL]) -> [ClipboardFileReference] {
        urls
            .filter(\.isFileURL)
            .map { url in
                let bookmarkData = withSecurityScopedAccess(to: url) {
                    try? url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                } ?? (try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ))

                return ClipboardFileReference(url: url, bookmarkData: bookmarkData)
            }
    }

    private func serializeFileReferences(_ references: [ClipboardFileReference]) -> String {
        let entries = references.map { reference in
            SerializedFileBundle.Entry(
                url: reference.url.absoluteString,
                bookmarkDataBase64: reference.bookmarkData?.base64EncodedString()
            )
        }

        let bundle = SerializedFileBundle(version: 2, entries: entries)
        if let encoded = try? JSONEncoder().encode(bundle) {
            return serializedFileBundlePrefix + encoded.base64EncodedString()
        }

        return references
            .map(\.url)
            .filter(\.isFileURL)
            .map(\.absoluteString)
            .joined(separator: "\n")
    }

    private func canonicalFileBundleHash(from serializedURLs: String) -> String {
        if let decodedBundle = decodeSerializedFileBundle(from: serializedURLs) {
            let normalized = decodedBundle.entries
                .map(\.url)
                .sorted()
                .joined(separator: "\n")
            return normalized.sha256
        }

        let normalized = serializedURLs
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\n")

        return normalized.sha256
    }

    private func decodeSerializedFileBundle(from content: String) -> SerializedFileBundle? {
        guard content.hasPrefix(serializedFileBundlePrefix) else { return nil }

        let payload = String(content.dropFirst(serializedFileBundlePrefix.count))
        guard let encodedData = Data(base64Encoded: payload) else { return nil }
        return try? JSONDecoder().decode(SerializedFileBundle.self, from: encodedData)
    }

    private func fileReferences(fromSerializedContent content: String) -> [ClipboardFileReference] {
        if let bundle = decodeSerializedFileBundle(from: content) {
            var references: [ClipboardFileReference] = []
            references.reserveCapacity(bundle.entries.count)

            for entry in bundle.entries {
                guard let url = URL(string: entry.url), url.isFileURL else { continue }
                let bookmarkData: Data?
                if let encodedBookmark = entry.bookmarkDataBase64 {
                    bookmarkData = Data(base64Encoded: encodedBookmark)
                } else {
                    bookmarkData = nil
                }
                references.append(ClipboardFileReference(url: url, bookmarkData: bookmarkData))
            }
            return references
        }

        return content
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { candidate -> ClipboardFileReference? in
                guard !candidate.isEmpty else { return nil }
                if let url = URL(string: candidate), url.isFileURL {
                    return ClipboardFileReference(url: url, bookmarkData: nil)
                }
                let path = (candidate as NSString).expandingTildeInPath
                return ClipboardFileReference(url: URL(fileURLWithPath: path), bookmarkData: nil)
            }
    }

    /// Reads the bytes of a single copied image file, so the stored clip is the
    /// picture itself rather than the document icon macOS offers alongside it.
    private func imageDataFromPasteboardFileURLs() -> Data? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              urls.count == 1,
              let url = urls.first,
              isImageFileURL(url) else { return nil }

        return withSecurityScopedAccess(to: url) { () -> Data? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            // Normalise to PNG so every stored clip decodes the same way later.
            guard let image = NSImage(data: data) else { return nil }
            print("Read image file from disk: \(data.count) bytes")
            return convertImageToPNG(image)
        } ?? nil
    }

    private func getImageFromPasteboard() -> Data? {
        let availableTypes = pasteboard.types ?? []

        // PHASE 0: A copied image FILE must be read from disk.
        //
        // Reading NSImage off a file-URL pasteboard hands back the Finder document
        // icon ("PNG" on a page-corner sheet), not the picture, so this has to run
        // before any NSImage read.
        if let fileData = imageDataFromPasteboardFileURLs() {
            return fileData
        }

        // PHASE 0b: Try typed NSImage read (some apps provide images this way only)
        if let imageObjects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = imageObjects.first {
            print("Found NSImage object on pasteboard")
            return convertImageToPNG(image)
        }

        // PHASE 1: Check standard image types first
        let standardImageTypes: [NSPasteboard.PasteboardType] = [
            .tiff,
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.jpg"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("com.microsoft.bmp"),
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("com.apple.pict"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.heif"),
            NSPasteboard.PasteboardType("public.webp")
        ]

        for type in standardImageTypes {
            if availableTypes.contains(type) {
                print("Checking standard image type: \(type.rawValue)")
                if let imageData = pasteboard.data(forType: type) {
                    print("Found image data for type \(type.rawValue): \(imageData.count) bytes")
                    if let image = NSImage(data: imageData) {
                        print("Successfully created NSImage from standard type")
                        return convertImageToPNG(image)
                    } else {
                        print("Failed to create NSImage from standard type data")
                    }
                }
            }
        }

        // PHASE 2: Check WebKit custom pasteboard data
        let webkitType = NSPasteboard.PasteboardType("com.apple.WebKit.custom-pasteboard-data")
        if availableTypes.contains(webkitType) {
            print("Checking WebKit custom pasteboard data")
            if let webkitData = pasteboard.data(forType: webkitType) {
                print("Found WebKit data: \(webkitData.count) bytes")
                // WebKit data might contain image data in a custom format
                if let image = extractImageFromWebKitData(webkitData) {
                    print("Successfully extracted image from WebKit data")
                    return convertImageToPNG(image)
                }
            }
        }

        // PHASE 3: Check ALL available types for potential image data
        print("Phase 3: Checking all available types for image data...")
        for type in availableTypes {
            let typeString = type.rawValue.lowercased()

            // Skip types we know are not images
            if typeString.contains("string") || typeString.contains("text") ||
               typeString.contains("url") || typeString.contains("filename") {
                continue
            }

            print("Trying type: \(type.rawValue)")
            if let data = pasteboard.data(forType: type) {
                print("Found data for \(type.rawValue): \(data.count) bytes")

                // Try to create an NSImage from the data
                if let image = NSImage(data: data) {
                    print("Successfully created NSImage from type: \(type.rawValue)")
                    return convertImageToPNG(image)
                }

                // For very small data, log what it contains
                if data.count < 1000 {
                    if let string = String(data: data, encoding: .utf8) {
                        print("Small data content: \(string.prefix(100))")
                    }
                }
            }
        }

        print("No image data found in any pasteboard type")
        return nil
    }

    private func extractImageFromWebKitData(_ data: Data) -> NSImage? {
        // WebKit custom pasteboard data is often a property list containing various data types
        // Try to extract image data from it

        do {
            // Try to parse as property list
            if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                print("WebKit plist keys: \(plist.keys)")

                // Look for image data in common WebKit keys
                let imageKeys = ["image/png", "image/jpeg", "image/gif", "image/tiff", "public.png", "public.jpeg"]

                for key in imageKeys {
                    if let imageData = plist[key] as? Data {
                        print("Found image data in WebKit plist key: \(key)")
                        if let image = NSImage(data: imageData) {
                            return image
                        }
                    }
                }

                // Sometimes the data is nested deeper
                for (key, value) in plist {
                    if let nestedDict = value as? [String: Any] {
                        for imageKey in imageKeys {
                            if let imageData = nestedDict[imageKey] as? Data {
                                print("Found image data in nested WebKit key: \(key).\(imageKey)")
                                if let image = NSImage(data: imageData) {
                                    return image
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            print("WebKit data is not a property list, trying direct image creation")
        }

        // If property list parsing fails, try to create image directly
        if let image = NSImage(data: data) {
            print("Created image directly from WebKit data")
            return image
        }

        return nil
    }

    private func isLikelyImageFilename(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]

        // Check if it's a short string that ends with an image extension
        if trimmed.count < 100 && trimmed.contains(".") {
            let lowercased = trimmed.lowercased()
            return imageExtensions.contains { lowercased.hasSuffix(".\($0)") }
        }

        return false
    }

    private func tryAlternativeImageDetection() -> Data? {
        print("Starting alternative image detection...")
        let availableTypes = pasteboard.types ?? []

        // Try each available type more systematically
        for type in availableTypes {
            let typeString = type.rawValue.lowercased()

            // Skip obvious non-image types
            if typeString.contains("string") || typeString.contains("text") ||
               typeString.contains("url") || typeString.contains("filename") {
                continue
            }

            print("Alternative check for type: \(type.rawValue)")

            if let data = pasteboard.data(forType: type) {
                print("Got \(data.count) bytes from \(type.rawValue)")

                // Try direct NSImage creation
                if let image = NSImage(data: data) {
                    print("Alternative detection found image in type: \(type.rawValue)")
                    return convertImageToPNG(image)
                }

                // For WebKit data, try special extraction
                if typeString.contains("webkit") {
                    if let image = extractImageFromWebKitData(data) {
                        print("Alternative detection found image in WebKit data")
                        return convertImageToPNG(image)
                    }
                }

                // Try to detect image headers in the data
                if data.count > 8 {
                    let header = data.prefix(8)
                    if isImageHeader(header) {
                        print("Detected image header in \(type.rawValue)")
                        if let image = NSImage(data: data) {
                            print("Alternative detection found image via header detection")
                            return convertImageToPNG(image)
                        }
                    }
                }
            }
        }

        print("Alternative detection found no images")
        return nil
    }

    private func isImageHeader(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }

        let bytes = [UInt8](data.prefix(8))

        // PNG header: 89 50 4E 47 0D 0A 1A 0A
        if bytes.count >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return true
        }

        // JPEG header: FF D8 FF
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return true
        }

        // GIF header: GIF87a or GIF89a
        if bytes.count >= 6 {
            let gifHeader = String(data: Data(bytes.prefix(6)), encoding: .ascii)
            if gifHeader == "GIF87a" || gifHeader == "GIF89a" {
                return true
            }
        }

        // TIFF headers: II*\0 or MM\0*
        if bytes.count >= 4 {
            if (bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
               (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A) {
                return true
            }
        }

        return false
    }

    private func convertImageToPNG(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        // Resize if too large (max 1024x1024 for performance)
        let maxSize: CGFloat = 1024
        let originalSize = image.size

        if originalSize.width > maxSize || originalSize.height > maxSize {
            let scale = min(maxSize / originalSize.width, maxSize / originalSize.height)
            let newSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)

            let resizedImage = NSImage(size: newSize)
            resizedImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize),
                      from: NSRect(origin: .zero, size: originalSize),
                      operation: .sourceOver,
                      fraction: 1.0)
            resizedImage.unlockFocus()

            guard let resizedTiffData = resizedImage.tiffRepresentation,
                  let resizedBitmapRep = NSBitmapImageRep(data: resizedTiffData) else {
                return bitmapRep.representation(using: .png, properties: [:])
            }

            return resizedBitmapRep.representation(using: .png, properties: [:])
        }

        return bitmapRep.representation(using: .png, properties: [:])
    }
    
    // MARK: - Data Persistence
    
    @MainActor
    private func saveClipboardItem(
        content: String,
        hash: String,
        categoryOverride: ContentCategory? = nil
    ) async {
        // Read on the main actor, before handing off. NSPasteboard and NSWorkspace
        // are not safe to touch from the Core Data background queue, and by the
        // time that queue runs the frontmost app may well have changed.
        let source = currentSourceApp()

        await withCheckedContinuation { continuation in
            backgroundContext.perform { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                // Classify content
                let category = categoryOverride ?? self.contentClassifier.classify(content)

                // Create new clipboard item
                let item = ClipboardItem.create(
                    content: content,
                    category: category,
                    sourceApp: source.name,
                    sourceBundleID: source.bundleID,
                    context: self.backgroundContext
                )
                
                // Save to Core Data
                do {
                    try self.backgroundContext.save()
                    
                    // Update UI on main thread
                    DispatchQueue.main.async {
                        self.updateTotalItemCount()
                        self.addToRecentItems(ClipboardItemViewModel(from: item))
                    }
                } catch {
                    print("Failed to save clipboard item: \(error)")
                }
                
                continuation.resume()
            }
        }
    }

    // MARK: - Importing an older database

    /// Pulls clips out of a Klippy database that lives outside this app's
    /// storage and adds any that are missing.
    ///
    /// Turning the sandbox on for the App Store moves Klippy's storage into a
    /// container, so a history built up by an earlier, unsandboxed build is
    /// suddenly somewhere the app is no longer allowed to look. The sandbox
    /// does let the user hand a file over deliberately, which is what this is:
    /// they pick the old database, and it gets merged in. Nothing is deleted
    /// from either side, and clips already present are skipped.
    @MainActor
    func importHistory(from storeURL: URL) async -> (added: Int, skipped: Int) {
        guard let model = PersistenceController.shared.container.managedObjectModel.copy() as? NSManagedObjectModel else {
            return (0, 0)
        }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let options: [AnyHashable: Any] = [
            NSReadOnlyPersistentStoreOption: true,
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        do {
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType,
                                               configurationName: nil,
                                               at: storeURL,
                                               options: options)
        } catch {
            print("Import: could not open \(storeURL.lastPathComponent): \(error)")
            return (0, 0)
        }

        let source = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        source.persistentStoreCoordinator = coordinator

        // Hashes already here, so a re-import is a no-op rather than a
        // second copy of everything.
        let existing = existingContentHashes()
        var takenIDs = existingIdentifiers()

        var added = 0
        var skipped = 0
        let batchSize = 500
        var offset = 0

        while true {
            let batch: [[String: Any]] = await withCheckedContinuation { continuation in
                source.perform {
                    let request = NSFetchRequest<NSManagedObject>(entityName: "ClipboardItem")
                    request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                    request.fetchOffset = offset
                    request.fetchLimit = batchSize
                    let rows = (try? source.fetch(request)) ?? []
                    let names: [String] = rows.first.map { Array($0.entity.attributesByName.keys) } ?? []
                    continuation.resume(returning: rows.map { row in
                        var values: [String: Any] = [:]
                        for name in names {
                            if let value = row.value(forKey: name) { values[name] = value }
                        }
                        return values
                    })
                }
            }
            if batch.isEmpty { break }
            offset += batch.count

            let result = await insert(batch, skippingHashes: existing, takenIDs: takenIDs)
            added += result.added
            skipped += result.skipped
            takenIDs = result.takenIDs
        }

        if added > 0 {
            refreshHistory()
        }
        return (added, skipped)
    }

    /// Every clip id already in this store, so an import cannot reuse one.
    private func existingIdentifiers() -> Set<UUID> {
        let request = NSFetchRequest<NSDictionary>(entityName: "ClipboardItem")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        let rows = (try? PersistenceController.shared.container.viewContext.fetch(request)) ?? []
        return Set(rows.compactMap { $0["id"] as? UUID })
    }

    /// Every content hash already in this store.
    private func existingContentHashes() -> Set<String> {
        let request = NSFetchRequest<NSDictionary>(entityName: "ClipboardItem")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["contentHash"]
        let rows = (try? PersistenceController.shared.container.viewContext.fetch(request)) ?? []
        return Set(rows.compactMap { $0["contentHash"] as? String })
    }

    private func insert(_ rows: [[String: Any]],
                        skippingHashes existing: Set<String>,
                        takenIDs: Set<UUID>) async -> (added: Int, skipped: Int, takenIDs: Set<UUID>) {
        await withCheckedContinuation { continuation in
            backgroundContext.perform { [weak self] in
                guard let self = self,
                      let entity = NSEntityDescription.entity(forEntityName: "ClipboardItem",
                                                              in: self.backgroundContext) else {
                    continuation.resume(returning: (0, 0, takenIDs))
                    return
                }
                var added = 0
                var skipped = 0
                var seen = existing
                var takenIDs = takenIDs
                for values in rows {
                    let hash = values["contentHash"] as? String
                    if let hash, seen.contains(hash) {
                        skipped += 1
                        continue
                    }
                    let item = NSManagedObject(entity: entity, insertInto: self.backgroundContext)
                    for (key, value) in values where entity.attributesByName[key] != nil {
                        item.setValue(value, forKey: key)
                    }
                    // Keep the original identity where it is free: pins and
                    // manual secrets are stored as clip ids in preferences, so
                    // reusing them is what carries those across an import. Mint
                    // a new one only on a clash, because two clips sharing an id
                    // makes the list address the wrong row.
                    if entity.attributesByName["id"] != nil {
                        let incoming = values["id"] as? UUID
                        if incoming == nil || takenIDs.contains(incoming!) {
                            var fresh = UUID()
                            while takenIDs.contains(fresh) { fresh = UUID() }
                            item.setValue(fresh, forKey: "id")
                            takenIDs.insert(fresh)
                        } else {
                            takenIDs.insert(incoming!)
                        }
                    }
                    if let hash { seen.insert(hash) }
                    added += 1
                }
                do {
                    try self.backgroundContext.save()
                } catch {
                    print("Import: save failed: \(error)")
                    self.backgroundContext.rollback()
                    continuation.resume(returning: (0, rows.count, takenIDs))
                    return
                }
                continuation.resume(returning: (added, skipped, takenIDs))
            }
        }
    }

    @MainActor
    @discardableResult
    func importImages(_ images: [NSImage]) async -> Int {
        var saved = 0
        for image in images {
            guard let data = convertImageToPNG(image) else { continue }
            let hash = data.sha256
            guard !recentHashes.contains(hash) else { continue }
            recentHashes.insert(hash)
            await saveImageClipboardItem(imageData: data,
                                         imageSize: image.size,
                                         hash: hash)
            saved += 1
        }
        if saved > 0 { refreshHistory() }
        return saved
    }

    @MainActor
    private func saveImageClipboardItem(imageData: Data, imageSize: NSSize, hash: String) async {
        // Same as above: the source has to be read here, on the main actor.
        let source = currentSourceApp()

        await withCheckedContinuation { continuation in
            backgroundContext.perform { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                self.pruneRecentDuplicateFileImageItems(
                    matchingImageHash: hash,
                    imageSize: imageSize
                )

                // Create new image clipboard item
                let item = ClipboardItem.createImage(
                    imageData: imageData,
                    width: Int32(imageSize.width),
                    height: Int32(imageSize.height),
                    sourceApp: source.name,
                    sourceBundleID: source.bundleID,
                    context: self.backgroundContext
                )

                // Save to Core Data
                do {
                    try self.backgroundContext.save()

                    // Update UI on main thread
                    DispatchQueue.main.async {
                        self.updateTotalItemCount()
                        self.addToRecentItems(ClipboardItemViewModel(from: item))
                        print("Image saved successfully: \(Int32(imageSize.width))×\(Int32(imageSize.height)), Total items: \(self.totalItemCount)")
                    }
                } catch {
                    print("Failed to save image clipboard item: \(error)")
                }

                continuation.resume()
            }
        }
    }

    private func pruneRecentDuplicateFileImageItems(
        matchingImageHash imageHash: String,
        imageSize: NSSize
    ) {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        request.fetchLimit = 16
        request.predicate = NSPredicate(
            format: "contentType == %d AND createdAt >= %@",
            ContentCategory.file.rawValue,
            Date().addingTimeInterval(-30) as NSDate
        )

        do {
            let candidates = try backgroundContext.fetch(request)
            guard !candidates.isEmpty else { return }

            var removedCount = 0

            for candidate in candidates {
                guard let content = candidate.content else { continue }
                let references = fileReferences(fromSerializedContent: content)
                guard references.count == 1 else { continue }
                let reference = references[0]

                // Only merge on identical bytes. A size-only fallback used to
                // live here, and it deleted file clips of different pictures
                // that happened to share pixel dimensions. A leftover duplicate
                // row is a lesser evil than a deleted clip.
                if let payload = imagePayloadFromFileReference(reference),
                   payload.data.sha256 == imageHash {
                    backgroundContext.delete(candidate)
                    removedCount += 1
                }
            }

            if removedCount > 0 {
                print("Coalesced \(removedCount) duplicate file-image entr\(removedCount == 1 ? "y" : "ies")")
            }
        } catch {
            print("Failed to prune duplicate file-image entries: \(error)")
        }
    }

    /// The app a clip is being copied from. The bundle identifier is what lets us
    /// show that app's real icon later; the name is kept for display and search.
    private func currentSourceApp() -> (name: String?, bundleID: String?) {
        // 1. The app named itself on the pasteboard. This is the only signal that
        //    is actually authoritative, and it stays correct even when the copy
        //    came from an app that isn't in front.
        let sourceKey = NSPasteboard.PasteboardType("org.nspasteboard.source")
        if let declared = pasteboard.string(forType: sourceKey), !declared.isEmpty {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: declared) {
                let name = FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                return (name, declared)
            }
            return (nil, declared)
        }

        // 2. Universal Clipboard. The content came from an iPhone or iPad, so no
        //    Mac app produced it. Crediting whatever window happened to be in
        //    front is simply wrong, which is how an iPhone copy ended up wearing
        //    the Cursor icon. Record no source rather than a false one.
        if isRemoteClipboardContent() {
            return (Self.remoteSourceName, nil)
        }

        // 3. Nothing better available: the frontmost app is a reasonable guess for
        //    an ordinary in-app copy.
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil)
        }
        // Klippy putting a clip on the pasteboard isn't Klippy authoring it.
        if frontmostApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return (nil, nil)
        }
        return (frontmostApp.localizedName, frontmostApp.bundleIdentifier)
    }

    /// Universal Clipboard payloads are flagged on the pasteboard. Confirmed on
    /// macOS 26 as `com.apple.is-remote-clipboard`; matched on a substring rather
    /// than that exact constant because the spelling has moved across releases.
    private func isRemoteClipboardContent() -> Bool {
        guard let types = pasteboard.types else { return false }
        return types.contains { type in
            let raw = type.rawValue.lowercased()
            return raw.contains("is-remote-clipboard") || raw.contains("isremoteclipboard")
        }
    }

    static let remoteSourceName = "Another device"

    // MARK: - Debug Methods

    func debugCurrentState() {
        print("=== Klippy Debug State ===")
        print("Current change count: \(pasteboard.changeCount)")
        print("Last tracked change count: \(lastChangeCount)")
        print("Total items in history: \(totalItemCount)")
        print("Recent items count: \(recentItems.count)")
        print("Recent hashes count: \(recentHashes.count)")
        print("Timer running: \(monitoringTimer != nil)")

        // Check current clipboard content
        let clipboardData = getClipboardContent()
        if let imageData = clipboardData.imageData {
            print("Current clipboard: Image (\(imageData.count) bytes)")
        } else if let content = clipboardData.content {
            print("Current clipboard: Text (\(content.count) chars)")
        } else {
            print("Current clipboard: Empty")
        }
        print("=== End Debug State ===")
    }
    
    // MARK: - Data Retrieval
    
    private func updateTotalItemCount() {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()

        backgroundContext.perform { [weak self] in
            guard let self = self else { return }

            do {
                let count = try self.backgroundContext.count(for: request)
                DispatchQueue.main.async {
                    self.totalItemCount = count
                }
            } catch {
                print("Failed to count clipboard items: \(error)")
                DispatchQueue.main.async {
                    self.totalItemCount = 0
                }
            }
        }
    }
    
    private func loadRecentItems() {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        request.fetchLimit = cacheSize
        
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            do {
                let items = try self.backgroundContext.fetch(request)
                let viewModels = items.map { ClipboardItemViewModel(from: $0) }
                
                DispatchQueue.main.async {
                    self.itemCache = viewModels
                    self.recentItems = Array(viewModels.prefix(50)) // Show only 50 in UI initially
                }
            } catch {
                print("Failed to load recent items: \(error)")
            }
        }
    }
    
    private func addToRecentItems(_ item: ClipboardItemViewModel) {
        // Add to cache
        itemCache.insert(item, at: 0)
        if itemCache.count > cacheSize {
            itemCache.removeLast()
        }
        
        // Update recent items for UI
        recentItems.insert(item, at: 0)
        if recentItems.count > 50 {
            recentItems.removeLast()
        }
    }
    
    // MARK: - Public Interface
    
    func copyToClipboard(_ item: ClipboardItemViewModel) {
        defer { selfWriteChangeCount = pasteboard.changeCount }
        pasteboard.clearContents()

        // A merged clip is stored in an encoded form with 0x1F separators.
        // Putting that on the pasteboard verbatim pastes control characters, so
        // the parts are rejoined into readable text first.
        if item.isMergedClip {
            let text = item.mergedComponents.joined(separator: "\n")
            pasteboard.setString(text, forType: .string)
            print("Merged clip copied (\(item.mergedComponents.count) parts)")
            return
        }

        if item.isImage {
            if let image = item.nsImage, pasteboard.writeObjects([image]) {
                print("Image copied to clipboard: \(item.imageSizeString)")
            } else if let tiffData = item.nsImage?.tiffRepresentation, pasteboard.setData(tiffData, forType: .tiff) {
                print("Image copied to clipboard (TIFF fallback): \(item.imageSizeString)")
            } else if let imageData = item.imageData, pasteboard.setData(imageData, forType: .png) {
                print("Image copied to clipboard (PNG fallback): \(item.imageSizeString)")
            } else {
                pasteboard.setString(item.content, forType: .string)
                print("Image data unavailable, copied text fallback")
            }
        } else if item.isFileReference {
            let fileReferences = item.fileReferences.filter { $0.url.isFileURL }
            let resolvedURLs = deduplicatedFileURLs(
                fileReferences.map(resolveFileReferenceURL).filter { $0.isFileURL }
            )
            let originalURLs = deduplicatedFileURLs(item.fileURLs.filter(\.isFileURL))
            let candidateURLs = resolvedURLs.isEmpty ? originalURLs : resolvedURLs
            let existingURLs = candidateURLs.filter(fileURLExists)
            let preferredURLs = existingURLs.isEmpty ? candidateURLs : existingURLs
            if fileReferences.count == 1,
               let imagePayload = imagePayloadFromFileReference(fileReferences[0]) {
                // Prefer true image data first so paste targets receive actual image content.
                if let fileImage = NSImage(data: imagePayload.data), pasteboard.writeObjects([fileImage]) {
                    print("Image file copied as image content")
                } else if pasteboard.setData(imagePayload.data, forType: .png) {
                    print("Image file copied as PNG data fallback")
                } else if writeFileURLsToPasteboard(preferredURLs) {
                    print("Image file copied as file reference fallback")
                } else if pasteboard.setString(fileReferenceFallbackText(urls: preferredURLs, item: item), forType: .string) {
                    print("Image file copied as plain-text path fallback")
                } else {
                    print("Failed image-file copy")
                }
            } else {
                if writeFileURLsToPasteboard(preferredURLs) {
                // Copy files/documents as file URL objects for native paste behavior.
                    print("File reference copied to clipboard: \(preferredURLs.count) item(s)")
                } else if pasteboard.setString(fileReferenceFallbackText(urls: preferredURLs, item: item), forType: .string) {
                    print("File path copied as text fallback")
                } else {
                    print("Failed file-reference copy")
                }
            }
        } else {
            // Copy text content to clipboard
            pasteboard.setString(item.content, forType: .string)
            print("Text copied to clipboard (\(item.content.count) chars)")
        }

        // Update usage statistics in background
        Task {
            await updateItemUsage(itemId: item.id)
        }
    }

    private func fileReferenceFallbackText(urls: [URL], item: ClipboardItemViewModel) -> String {
        let resolvedPaths = urls
            .filter { $0.isFileURL && !$0.path.isEmpty }
            .map(\.path)
        if !resolvedPaths.isEmpty {
            return resolvedPaths.joined(separator: "\n")
        }

        let originalPaths = item.fileURLs
            .filter { $0.isFileURL && !$0.path.isEmpty }
            .map(\.path)
        if !originalPaths.isEmpty {
            return originalPaths.joined(separator: "\n")
        }

        return item.fileDisplayText
    }

    private func deduplicatedFileURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var uniqueURLs: [URL] = []
        uniqueURLs.reserveCapacity(urls.count)

        for url in urls {
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            uniqueURLs.append(url)
        }

        return uniqueURLs
    }

    private func fileURLExists(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return withSecurityScopedAccess(to: url) {
            FileManager.default.fileExists(atPath: url.path)
        } ?? FileManager.default.fileExists(atPath: url.path)
    }

    private func writeFileURLsToPasteboard(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }

        // Primary path: native NSURL objects for Finder/document paste fidelity.
        if pasteboard.writeObjects(urls as [NSURL]) {
            return true
        }

        let items = urls.map { url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            item.setString(url.path, forType: .string)
            return item
        }
        return pasteboard.writeObjects(items)
    }

    private func isImageFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            return true
        }
        return loadImage(from: url) != nil
    }

    private func imagePayloadFromFileReference(_ reference: ClipboardFileReference) -> (data: Data, size: NSSize)? {
        let resolvedURL = resolveFileReferenceURL(reference)
        guard resolvedURL.isFileURL else { return nil }

        return withSecurityScopedAccess(to: resolvedURL) {
            guard FileManager.default.fileExists(atPath: resolvedURL.path) else { return nil }
            guard isImageFileURL(resolvedURL) else { return nil }
            guard let image = loadImage(from: resolvedURL) else { return nil }
            guard let pngData = convertImageToPNG(image) else { return nil }
            return (data: pngData, size: image.size)
        } ?? nil
    }

    private func resolveFileReferenceURL(_ reference: ClipboardFileReference) -> URL {
        guard let bookmarkData = reference.bookmarkData else {
            return reference.url
        }

        var isStale = false
        if let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return resolvedURL
        }

        return reference.url
    }

    private func loadImage(from url: URL) -> NSImage? {
        if let image = NSImage(contentsOf: url) {
            return image
        }

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            return NSImage(cgImage: cgImage, size: size)
        }

        if let data = try? Data(contentsOf: url),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            return NSImage(cgImage: cgImage, size: size)
        }

        return nil
    }

    private func withSecurityScopedAccess<T>(to url: URL, _ work: () -> T?) -> T? {
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return work()
    }
    
    @MainActor
    private func updateItemUsage(itemId: UUID) async {
        await withCheckedContinuation { continuation in
            backgroundContext.perform { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", itemId as CVarArg)
                request.fetchLimit = 1
                
                do {
                    if let item = try self.backgroundContext.fetch(request).first {
                        item.updateLastAccessed()
                        try self.backgroundContext.save()
                    }
                } catch {
                    print("Failed to update item usage: \(error)")
                }
                
                continuation.resume()
            }
        }
    }
    
    static let autoDeleteDaysKey = "klippy.data.autoDeleteDays"

    /// How many clips a given retention window would remove, without removing
    /// anything. Used to show the real number before the setting is switched on.
    /// The one rule for what auto-delete may remove.
    ///
    /// The count shown in Settings and the deletion itself must agree, or the
    /// app promises to remove one number of clips and removes another.
    private static func isPrunable(_ item: ClipboardItem,
                                   keepIDs: Set<UUID>,
                                   savedContents: Set<String>) -> Bool {
        if let id = item.id, keepIDs.contains(id) { return false }
        if let content = item.content, savedContents.contains(content) { return false }
        // A merged clip is something the user built by hand. It usually has a
        // usage count of zero because merging is how you collect things, not
        // how you paste them, so auto-delete would throw away deliberate work.
        if item.contentType == ContentCategory.merged.rawValue { return false }
        return true
    }

    func countUnusedClips(olderThanDays days: Int, completion: @escaping (Int) -> Void) {
        guard days > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            completion(0)
            return
        }

        let keepIDs = favoriteItemIDs.union(SecretStore.shared.ids)
        let savedContents = Set(SnippetManager.shared.snippets.map(\.content))

        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
            request.predicate = NSPredicate(format: "createdAt < %@ AND usageCount == 0",
                                            cutoff as NSDate)
            request.fetchBatchSize = 500

            let count = (try? self.backgroundContext.fetch(request))?.filter {
                Self.isPrunable($0, keepIDs: keepIDs, savedContents: savedContents)
            }.count ?? 0

            DispatchQueue.main.async { completion(count) }
        }
    }

    /// Removes clips that were captured a long time ago and never used again.
    ///
    /// "Unused" is measured, not guessed: `usageCount` is incremented by
    /// `updateLastAccessed()` every time a clip is copied back out, so a count of
    /// zero means it was captured and never reached for. Pinned clips, clips the
    /// user marked secret, and anything saved as a snippet are always kept.
    func pruneUnusedClips(olderThanDays days: Int, completion: ((Int) -> Void)? = nil) {
        guard days > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            completion?(0)
            return
        }

        let keepIDs = favoriteItemIDs.union(SecretStore.shared.ids)
        let savedContents = Set(SnippetManager.shared.snippets.map(\.content))

        backgroundContext.perform { [weak self] in
            guard let self = self else { return }

            let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
            request.predicate = NSPredicate(format: "createdAt < %@ AND usageCount == 0",
                                            cutoff as NSDate)
            request.fetchBatchSize = 500

            do {
                let candidates = try self.backgroundContext.fetch(request)
                var removed = 0
                for item in candidates {
                    guard Self.isPrunable(item, keepIDs: keepIDs,
                                          savedContents: savedContents) else { continue }
                    self.backgroundContext.delete(item)
                    removed += 1
                }
                if removed > 0 { try self.backgroundContext.save() }

                DispatchQueue.main.async {
                    if removed > 0 { self.refreshHistory() }
                    print("Auto-delete removed \(removed) unused clips older than \(days) days")
                    completion?(removed)
                }
            } catch {
                print("Auto-delete failed: \(error)")
                DispatchQueue.main.async { completion?(0) }
            }
        }
    }

    func clearAllItems() {
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            let request: NSFetchRequest<NSFetchRequestResult> = ClipboardItem.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            
            do {
                try self.backgroundContext.execute(deleteRequest)
                try self.backgroundContext.save()
                
                DispatchQueue.main.async {
                    self.totalItemCount = 0
                    self.recentItems.removeAll()
                    self.itemCache.removeAll()
                    self.recentHashes.removeAll()
                    self.favoriteItemIDs.removeAll()
                    self.persistFavoriteIDs()
                }
            } catch {
                print("Failed to clear all items: \(error)")
            }
        }
    }

    func deleteItem(itemId: UUID) {
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }

            let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", itemId as CVarArg)
            request.fetchLimit = 1

            do {
                guard let item = try self.backgroundContext.fetch(request).first else { return }

                let existingHash = item.contentHash
                self.backgroundContext.delete(item)
                try self.backgroundContext.save()

                DispatchQueue.main.async {
                    if let existingHash {
                        self.recentHashes.remove(existingHash)
                    }
                    self.itemCache.removeAll { $0.id == itemId }
                    self.recentItems.removeAll { $0.id == itemId }
                    if self.favoriteItemIDs.remove(itemId) != nil {
                        self.persistFavoriteIDs()
                    }
                    self.updateTotalItemCount()
                }
            } catch {
                print("Failed to delete clipboard item: \(error)")
            }
        }
    }

    func isFavorite(itemId: UUID) -> Bool {
        favoriteItemIDs.contains(itemId)
    }

    /// Create a merged clip from multiple components and insert it into the main
    /// clipboard history. The new item appears at the top of the list like any
    /// fresh copy, but is marked as `.merged` so the UI can handle it specially.
    @discardableResult
    func createMergedClip(components: [String]) -> ClipboardItemViewModel? {
        guard components.count >= 2 else { return nil }

        let encoded = MergedClipCodec.encode(components)
        var newItem: ClipboardItemViewModel?

        backgroundContext.performAndWait {
            let item = ClipboardItem.create(
                content: encoded,
                category: .merged,
                sourceApp: "Klippy",
                context: backgroundContext
            )
            do {
                try backgroundContext.save()
                newItem = ClipboardItemViewModel(from: item)
            } catch {
                print("Failed to save merged clip: \(error)")
            }
        }

        if let item = newItem {
            DispatchQueue.main.async { [weak self] in
                self?.addToRecentItems(item)
                self?.updateTotalItemCount()
            }
        }

        return newItem
    }

    /// Fetch all pinned items from Core Data, regardless of cache window.
    /// Returns them sorted by most recently pinned (using createdAt as proxy).
    /// Every merged clip, fetched straight from the store.
    ///
    /// The Merged view used to filter the search results, which are capped at the
    /// newest 5000 clips. On a large history that window only reaches back a few
    /// weeks, so older merged clips were simply invisible. Pinned had the same
    /// problem and is fetched directly for the same reason.
    func fetchAllMergedItems() -> [ClipboardItemViewModel] {
        var results: [ClipboardItemViewModel] = []

        backgroundContext.performAndWait {
            let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
            request.predicate = NSPredicate(format: "contentType == %d",
                                            ContentCategory.merged.rawValue)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt,
                                                        ascending: false)]
            do {
                let items = try backgroundContext.fetch(request)
                results = items.map { ClipboardItemViewModel(from: $0) }
            } catch {
                print("Failed to fetch merged items: \(error)")
            }
        }

        return results
    }

    func fetchAllPinnedItems() -> [ClipboardItemViewModel] {
        guard !favoriteItemIDs.isEmpty else { return [] }

        let idsSnapshot = favoriteItemIDs
        var results: [ClipboardItemViewModel] = []

        backgroundContext.performAndWait {
            let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
            let ids = Array(idsSnapshot)
            request.predicate = NSPredicate(format: "id IN %@", ids)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]

            do {
                let items = try backgroundContext.fetch(request)
                results = items.map { ClipboardItemViewModel(from: $0) }
            } catch {
                print("Failed to fetch pinned items: \(error)")
            }
        }

        return results
    }

    @discardableResult
    func toggleFavorite(itemId: UUID) -> Bool {
        let isNowFavorite: Bool
        if favoriteItemIDs.contains(itemId) {
            favoriteItemIDs.remove(itemId)
            isNowFavorite = false
        } else {
            favoriteItemIDs.insert(itemId)
            isNowFavorite = true
        }
        persistFavoriteIDs()
        return isNowFavorite
    }

    func exportHistoryAsJSON() {
        let favoriteIDsSnapshot = favoriteItemIDs

        backgroundContext.perform { [weak self] in
            guard let self = self else { return }

            let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]

            do {
                let fetchedItems = try self.backgroundContext.fetch(request)
                let payloadItems = fetchedItems.map { item in
                    ExportClipboardItem(
                        id: (item.id ?? UUID()).uuidString,
                        content: item.content ?? "",
                        categoryRawValue: item.contentType,
                        categoryName: item.categoryEnum.displayName,
                        isFavorite: item.id.map { favoriteIDsSnapshot.contains($0) } ?? false,
                        createdAt: item.createdAt ?? Date(),
                        lastAccessedAt: item.lastAccessedAt ?? Date(),
                        usageCount: item.usageCount,
                        sourceApplication: item.sourceApplication,
                        tags: item.tags,
                        isImage: item.isImage,
                        imageWidth: item.imageWidth,
                        imageHeight: item.imageHeight,
                        imageDataBase64: item.isImage ? item.imageData?.base64EncodedString() : nil
                    )
                }

                let envelope = ExportEnvelope(
                    exportVersion: 1,
                    exportedAt: Date(),
                    totalItems: payloadItems.count,
                    items: payloadItems
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let jsonData = try encoder.encode(envelope)

                DispatchQueue.main.async {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [UTType.json]
                    panel.nameFieldStringValue = self.defaultExportFileName()
                    panel.canCreateDirectories = true

                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            try jsonData.write(to: url, options: .atomic)
                            print("Exported clipboard history to \(url.path)")
                        } catch {
                            print("Failed to write export file: \(error)")
                        }
                    }
                }
            } catch {
                print("Failed to export clipboard history: \(error)")
            }
        }
    }
    
    // MARK: - Search Interface
    
    func getItemsFromCache(matching query: String, category: ContentCategory, limit: Int) -> [ClipboardItemViewModel] {
        var filteredItems = itemCache
        
        // Filter by category
        if category != .all {
            filteredItems = filteredItems.filter { $0.category.matches(category) }
        }
        
        // Filter by search query
        if !query.isEmpty {
            let lowercaseQuery = query.lowercased()
            filteredItems = filteredItems.filter { item in
                item.content.lowercased().contains(lowercaseQuery)
            }
        }
        
        return Array(filteredItems.prefix(limit))
    }
    
    func clearCache() {
        itemCache.removeAll()
        recentHashes.removeAll()
    }

    func refreshHistory() {
        updateTotalItemCount()
        loadRecentItems()
    }

    private func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "klippy-export-\(formatter.string(from: Date())).json"
    }

    private func loadFavoriteIDs() -> Set<UUID> {
        let storedIDs = UserDefaults.standard.array(forKey: favoritesDefaultsKey) as? [String] ?? []
        return Set(storedIDs.compactMap(UUID.init(uuidString:)))
    }

    private func persistFavoriteIDs() {
        let encodedIDs = favoriteItemIDs.map(\.uuidString)
        UserDefaults.standard.set(encodedIDs, forKey: favoritesDefaultsKey)
    }
}
    private let serializedFileBundlePrefix = "klippy-file-bundle-v2:"

    private struct SerializedFileBundle: Codable {
        struct Entry: Codable {
            let url: String
            let bookmarkDataBase64: String?
        }

        let version: Int
        let entries: [Entry]
    }
