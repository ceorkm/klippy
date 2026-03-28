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
}

extension SavedSnippet {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SavedSnippet> {
        return NSFetchRequest<SavedSnippet>(entityName: "SavedSnippet")
    }

    static func create(
        title: String,
        content: String,
        context: NSManagedObjectContext
    ) -> SavedSnippet {
        let snippet = SavedSnippet(context: context)
        snippet.id = UUID()
        snippet.title = title
        snippet.content = content
        snippet.createdAt = Date()
        snippet.updatedAt = Date()
        snippet.sortOrder = 0
        return snippet
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

    init(from snippet: SavedSnippet) {
        self.id = snippet.id ?? UUID()
        self.title = snippet.title ?? ""
        self.content = snippet.content ?? ""
        self.createdAt = snippet.createdAt ?? Date()
        self.updatedAt = snippet.updatedAt ?? Date()
        self.sortOrder = snippet.sortOrder
    }

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int32 = 0
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    var displayContent: String {
        let maxLength = 200
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "..."
        }
        return content
    }
}
