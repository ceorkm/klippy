import Foundation
import CoreData
import SwiftUI

// MARK: - Core Data Model
@objc(SavedSnippet)
public class SavedSnippet: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var content: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var isMerged: Bool
}

extension SavedSnippet {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SavedSnippet> {
        return NSFetchRequest<SavedSnippet>(entityName: "SavedSnippet")
    }

    static func create(
        title: String,
        content: String,
        isMerged: Bool = false,
        context: NSManagedObjectContext
    ) -> SavedSnippet {
        let snippet = SavedSnippet(context: context)
        snippet.id = UUID()
        snippet.title = title
        snippet.content = content
        snippet.createdAt = Date()
        snippet.updatedAt = Date()
        snippet.sortOrder = 0
        snippet.isMerged = isMerged
        return snippet
    }
}

// MARK: - Merge helpers
enum MergedSnippetCodec {
    private static let marker = "\u{001F}KLIPPY_MERGE\u{001F}"

    static func encode(_ components: [String]) -> String {
        components.joined(separator: marker)
    }

    static func decode(_ content: String) -> [String] {
        content.components(separatedBy: marker)
    }
}

// MARK: - View Model
struct SavedSnippetViewModel: Identifiable {
    let id: UUID
    let title: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let sortOrder: Int32
    let isMerged: Bool

    init(from snippet: SavedSnippet) {
        self.id = snippet.id ?? UUID()
        self.title = snippet.title ?? ""
        self.content = snippet.content ?? ""
        self.createdAt = snippet.createdAt ?? Date()
        self.updatedAt = snippet.updatedAt ?? Date()
        self.sortOrder = snippet.sortOrder
        self.isMerged = snippet.isMerged
    }

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int32 = 0,
        isMerged: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.isMerged = isMerged
    }

    var mergedComponents: [String] {
        guard isMerged else { return [] }
        return MergedSnippetCodec.decode(content)
    }

    var displayContent: String {
        if isMerged {
            return mergedComponents.joined(separator: " • ")
        }
        let maxLength = 200
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "..."
        }
        return content
    }
}
