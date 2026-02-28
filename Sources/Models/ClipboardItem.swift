import Foundation
import CoreData
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - Content Category Enum
enum ContentCategory: Int16, CaseIterable {
    case all = 0
    case text = 1
    case url = 2
    case email = 3
    case phone = 4
    case address = 5
    case code = 6
    case image = 7
    case file = 8
    case number = 9
    case date = 10
    case color = 11
    case json = 12
    case xml = 13
    case markdown = 14
    case socialMedia = 15
    case instagramURL = 16
    case tiktokURL = 17
    case apiKey = 18
    case paymentCard = 19
    case other = 99
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .url: return "URLs"
        case .email: return "Emails"
        case .phone: return "Phone"
        case .address: return "Address"
        case .code: return "Code"
        case .image: return "Images"
        case .file: return "Files"
        case .number: return "Numbers"
        case .date: return "Dates"
        case .color: return "Colors"
        case .json: return "JSON"
        case .xml: return "XML"
        case .markdown: return "Markdown"
        case .socialMedia: return "Social URLs"
        case .instagramURL: return "Instagram URLs"
        case .tiktokURL: return "TikTok URLs"
        case .apiKey: return "API Keys"
        case .paymentCard: return "Payment Cards"
        case .other: return "Other"
        }
    }
    
    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .text: return "text.justify.left"
        case .url: return "link.circle"
        case .email: return "at"
        case .phone: return "phone.fill"
        case .address: return "mappin.and.ellipse"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo.on.rectangle"
        case .file: return "doc.text.fill"
        case .number: return "number.square"
        case .date: return "calendar"
        case .color: return "paintpalette.fill"
        case .json: return "curlybraces"
        case .xml: return "chevron.left.forwardslash.chevron.right"
        case .markdown: return "textformat"
        case .socialMedia: return "bubble.left.and.bubble.right.fill"
        case .instagramURL: return "camera.circle"
        case .tiktokURL: return "music.note"
        case .apiKey: return "key.fill"
        case .paymentCard: return "creditcard.fill"
        case .other: return "questionmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return .primary
        case .text: return .orange
        case .url: return .purple
        case .email: return .green
        case .phone: return .orange
        case .address: return .red
        case .code: return .mint
        case .image: return .pink
        case .file: return .brown
        case .number: return .orange
        case .date: return .indigo
        case .color: return .yellow
        case .json: return .orange
        case .xml: return .gray
        case .markdown: return .orange
        case .socialMedia: return .indigo
        case .instagramURL: return .pink
        case .tiktokURL: return .red
        case .apiKey: return .mint
        case .paymentCard: return .green
        case .other: return .secondary
        }
    }
}

// MARK: - Core Data Model
@objc(ClipboardItem)
public class ClipboardItem: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var content: String?
    @NSManaged public var contentType: Int16
    @NSManaged public var contentHash: String?
    @NSManaged public var searchableContent: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var lastAccessedAt: Date?
    @NSManaged public var usageCount: Int32
    @NSManaged public var sourceApplication: String?
    @NSManaged public var tags: String?

    // Image-related properties
    @NSManaged public var imageData: Data?
    @NSManaged public var imageWidth: Int32
    @NSManaged public var imageHeight: Int32
    @NSManaged public var isImage: Bool
}

// MARK: - Core Data Extensions
extension ClipboardItem {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ClipboardItem> {
        return NSFetchRequest<ClipboardItem>(entityName: "ClipboardItem")
    }
    
    var categoryEnum: ContentCategory {
        get {
            ContentCategory(rawValue: contentType) ?? .other
        }
        set {
            contentType = newValue.rawValue
        }
    }
    
    var tagsArray: [String] {
        get {
            tags?.components(separatedBy: ",").compactMap { $0.trimmingCharacters(in: .whitespaces) } ?? []
        }
        set {
            tags = newValue.joined(separator: ",")
        }
    }
    
    static func create(
        content: String,
        category: ContentCategory,
        sourceApp: String? = nil,
        context: NSManagedObjectContext
    ) -> ClipboardItem {
        let item = ClipboardItem(context: context)
        item.id = UUID()
        item.content = content
        item.categoryEnum = category
        item.sourceApplication = sourceApp
        item.createdAt = Date()
        item.lastAccessedAt = Date()
        item.usageCount = 0
        item.contentHash = content.sha256
        item.searchableContent = content.lowercased()
        item.isImage = false

        return item
    }

    static func createImage(
        imageData: Data,
        width: Int32,
        height: Int32,
        sourceApp: String? = nil,
        context: NSManagedObjectContext
    ) -> ClipboardItem {
        let item = ClipboardItem(context: context)
        item.id = UUID()
        item.content = "Image (\(width)×\(height))" // Descriptive text for search
        item.categoryEnum = .image
        item.sourceApplication = sourceApp
        item.createdAt = Date()
        item.lastAccessedAt = Date()
        item.usageCount = 0
        item.contentHash = imageData.sha256
        item.searchableContent = "image \(width) \(height) pixels"
        item.isImage = true
        item.imageData = imageData
        item.imageWidth = width
        item.imageHeight = height

        return item
    }
    
    func updateLastAccessed() {
        lastAccessedAt = Date()
        usageCount += 1
    }
}

private let fileBundlePrefix = "klippy-file-bundle-v2:"

private struct FileBundleEnvelope: Codable {
    struct Entry: Codable {
        let url: String
        let bookmarkDataBase64: String?
    }

    let version: Int
    let entries: [Entry]
}

struct ClipboardFileReference {
    let url: URL
    let bookmarkData: Data?
}

// MARK: - View Model
struct ClipboardItemViewModel: Identifiable {
    private static let filePreviewCache = NSCache<NSString, NSImage>()

    let id: UUID
    let content: String
    let category: ContentCategory
    let createdAt: Date
    let lastAccessedAt: Date
    let usageCount: Int32
    let sourceApplication: String?

    // Image-related properties
    let isImage: Bool
    let imageData: Data?
    let imageWidth: Int32
    let imageHeight: Int32

    init(from clipboardItem: ClipboardItem) {
        self.id = clipboardItem.id ?? UUID()
        self.content = clipboardItem.content ?? ""
        self.category = clipboardItem.categoryEnum
        self.createdAt = clipboardItem.createdAt ?? Date()
        self.lastAccessedAt = clipboardItem.lastAccessedAt ?? Date()
        self.usageCount = clipboardItem.usageCount
        self.sourceApplication = clipboardItem.sourceApplication
        self.isImage = clipboardItem.isImage
        self.imageData = clipboardItem.imageData
        self.imageWidth = clipboardItem.imageWidth
        self.imageHeight = clipboardItem.imageHeight
    }

    // Convenience initializer for testing/preview
    init(
        id: UUID = UUID(),
        content: String,
        category: ContentCategory,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        usageCount: Int32 = 0,
        sourceApplication: String? = nil,
        isImage: Bool = false,
        imageData: Data? = nil,
        imageWidth: Int32 = 0,
        imageHeight: Int32 = 0
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.usageCount = usageCount
        self.sourceApplication = sourceApplication
        self.isImage = isImage
        self.imageData = imageData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }
    
    var displayText: String {
        let maxLength = 200
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "..."
        }
        return content
    }

    var fileReferences: [ClipboardFileReference] {
        if content.hasPrefix(fileBundlePrefix) {
            let payload = String(content.dropFirst(fileBundlePrefix.count))
            if let encodedData = Data(base64Encoded: payload),
               let envelope = try? JSONDecoder().decode(FileBundleEnvelope.self, from: encodedData) {
                return envelope.entries.compactMap { entry -> ClipboardFileReference? in
                    guard let url = URL(string: entry.url), url.isFileURL else { return nil }
                    let bookmarkData: Data?
                    if let encodedBookmark = entry.bookmarkDataBase64 {
                        bookmarkData = Data(base64Encoded: encodedBookmark)
                    } else {
                        bookmarkData = nil
                    }
                    return ClipboardFileReference(url: url, bookmarkData: bookmarkData)
                }
            }
        }

        let candidates = content
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return candidates.map { candidate in
            if let url = URL(string: candidate), url.isFileURL {
                return ClipboardFileReference(url: url, bookmarkData: nil)
            }

            let expandedPath = (candidate as NSString).expandingTildeInPath
            return ClipboardFileReference(url: URL(fileURLWithPath: expandedPath), bookmarkData: nil)
        }
    }

    var fileURLs: [URL] {
        fileReferences.map(\.url)
    }

    var isFileReference: Bool {
        category == .file && !fileURLs.isEmpty
    }

    var fileDisplayText: String {
        guard isFileReference else { return displayText }

        let names = fileURLs.map(\.lastPathComponent).filter { !$0.isEmpty }
        guard !names.isEmpty else { return displayText }

        if names.count == 1 {
            return names[0]
        }

        return "\(names[0]) +\(names.count - 1) more"
    }

    var listPreviewImage: NSImage? {
        if let image = nsImage {
            return image
        }

        guard isImageFileReference, let reference = primaryFileReference else { return nil }
        let resolvedURL = resolveFileReferenceURL(reference)
        let cacheKey = resolvedURL.path as NSString

        if let cachedImage = Self.filePreviewCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let image = withSecurityScopedAccess(to: resolvedURL) {
            loadImage(from: resolvedURL)
        }
        if let image {
            Self.filePreviewCache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    var hasImagePreview: Bool {
        listPreviewImage != nil
    }

    var isImageFileReference: Bool {
        guard category == .file, let reference = primaryFileReference else { return false }

        let resolvedURL = resolveFileReferenceURL(reference)
        let pathExtension = resolvedURL.pathExtension.lowercased()
        guard !pathExtension.isEmpty else { return false }

        guard let type = UTType(filenameExtension: pathExtension) else {
            return false
        }

        return type.conforms(to: .image)
    }
    
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    // Image-related computed properties
    var nsImage: NSImage? {
        guard isImage, let imageData = imageData else { return nil }
        return NSImage(data: imageData)
    }

    var imageSizeString: String {
        guard isImage else { return "" }
        return "\(imageWidth)×\(imageHeight)"
    }

    var thumbnailImage: NSImage? {
        guard let image = nsImage else { return nil }

        let thumbnailSize = NSSize(width: 64, height: 64)
        let thumbnail = NSImage(size: thumbnailSize)

        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                  from: NSRect(origin: .zero, size: image.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        thumbnail.unlockFocus()

        return thumbnail
    }

    private var primaryFileReference: ClipboardFileReference? {
        guard fileReferences.count == 1 else { return nil }
        return fileReferences.first
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

    private func withSecurityScopedAccess<T>(to url: URL, _ work: () -> T?) -> T? {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return work()
    }

    private func loadImage(from url: URL) -> NSImage? {
        if let image = NSImage(contentsOf: url) {
            return image
        }

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        if let data = try? Data(contentsOf: url),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        return nil
    }
}

// MARK: - String Extensions
extension String {
    var sha256: String {
        let data = Data(self.utf8)
        return data.sha256
    }
}

// MARK: - Data Extensions
extension Data {
    var sha256: String {
        let hash = self.withUnsafeBytes { bytes in
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(self.count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// Import CommonCrypto for SHA256
import CommonCrypto
