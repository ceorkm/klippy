import SwiftUI
import CoreData

@main
struct KlippyApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        // Start clipboard monitoring immediately when app launches
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ClipboardManager.shared.startMonitoring()
            print("✅ Klippy started - Menu bar icon should be visible")
            print("📋 Clipboard monitoring active")
        }
    }

    var body: some Scene {
        MenuBarExtra("Klippy", systemImage: "doc.on.clipboard") {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Core Data Stack
class PersistenceController {
    static let shared = PersistenceController()
    
    static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // ClipboardItem entity
        let clipboardItem = NSEntityDescription()
        clipboardItem.name = "ClipboardItem"
        clipboardItem.managedObjectClassName = "ClipboardItem"

        let ciId = NSAttributeDescription(); ciId.name = "id"; ciId.attributeType = .UUIDAttributeType; ciId.isOptional = true
        let ciContent = NSAttributeDescription(); ciContent.name = "content"; ciContent.attributeType = .stringAttributeType; ciContent.isOptional = true
        let ciContentHash = NSAttributeDescription(); ciContentHash.name = "contentHash"; ciContentHash.attributeType = .stringAttributeType; ciContentHash.isOptional = true
        let ciContentType = NSAttributeDescription(); ciContentType.name = "contentType"; ciContentType.attributeType = .integer16AttributeType; ciContentType.isOptional = true; ciContentType.defaultValue = 0
        let ciCreatedAt = NSAttributeDescription(); ciCreatedAt.name = "createdAt"; ciCreatedAt.attributeType = .dateAttributeType; ciCreatedAt.isOptional = true
        let ciLastAccessed = NSAttributeDescription(); ciLastAccessed.name = "lastAccessedAt"; ciLastAccessed.attributeType = .dateAttributeType; ciLastAccessed.isOptional = true
        let ciSearchable = NSAttributeDescription(); ciSearchable.name = "searchableContent"; ciSearchable.attributeType = .stringAttributeType; ciSearchable.isOptional = true
        let ciSource = NSAttributeDescription(); ciSource.name = "sourceApplication"; ciSource.attributeType = .stringAttributeType; ciSource.isOptional = true
        let ciTags = NSAttributeDescription(); ciTags.name = "tags"; ciTags.attributeType = .stringAttributeType; ciTags.isOptional = true
        let ciUsage = NSAttributeDescription(); ciUsage.name = "usageCount"; ciUsage.attributeType = .integer32AttributeType; ciUsage.isOptional = true; ciUsage.defaultValue = 0
        let ciImageData = NSAttributeDescription(); ciImageData.name = "imageData"; ciImageData.attributeType = .binaryDataAttributeType; ciImageData.isOptional = true; ciImageData.allowsExternalBinaryDataStorage = true
        let ciImageWidth = NSAttributeDescription(); ciImageWidth.name = "imageWidth"; ciImageWidth.attributeType = .integer32AttributeType; ciImageWidth.isOptional = true; ciImageWidth.defaultValue = 0
        let ciImageHeight = NSAttributeDescription(); ciImageHeight.name = "imageHeight"; ciImageHeight.attributeType = .integer32AttributeType; ciImageHeight.isOptional = true; ciImageHeight.defaultValue = 0
        let ciIsImage = NSAttributeDescription(); ciIsImage.name = "isImage"; ciIsImage.attributeType = .booleanAttributeType; ciIsImage.isOptional = true; ciIsImage.defaultValue = false

        clipboardItem.properties = [ciId, ciContent, ciContentHash, ciContentType, ciCreatedAt, ciLastAccessed, ciSearchable, ciSource, ciTags, ciUsage, ciImageData, ciImageWidth, ciImageHeight, ciIsImage]

        // SearchIndex entity
        let searchIndex = NSEntityDescription()
        searchIndex.name = "SearchIndex"
        searchIndex.managedObjectClassName = "SearchIndex"

        let siTerm = NSAttributeDescription(); siTerm.name = "term"; siTerm.attributeType = .stringAttributeType; siTerm.isOptional = true
        let siTermHash = NSAttributeDescription(); siTermHash.name = "termHash"; siTermHash.attributeType = .stringAttributeType; siTermHash.isOptional = true
        let siClipId = NSAttributeDescription(); siClipId.name = "clipboardItemID"; siClipId.attributeType = .UUIDAttributeType; siClipId.isOptional = true

        searchIndex.properties = [siTerm, siTermHash, siClipId]

        // SavedSnippet entity
        let savedSnippet = NSEntityDescription()
        savedSnippet.name = "SavedSnippet"
        savedSnippet.managedObjectClassName = "SavedSnippet"

        let ssId = NSAttributeDescription(); ssId.name = "id"; ssId.attributeType = .UUIDAttributeType; ssId.isOptional = true
        let ssTitle = NSAttributeDescription(); ssTitle.name = "title"; ssTitle.attributeType = .stringAttributeType; ssTitle.isOptional = true
        let ssContent = NSAttributeDescription(); ssContent.name = "content"; ssContent.attributeType = .stringAttributeType; ssContent.isOptional = true
        let ssCreatedAt = NSAttributeDescription(); ssCreatedAt.name = "createdAt"; ssCreatedAt.attributeType = .dateAttributeType; ssCreatedAt.isOptional = true
        let ssUpdatedAt = NSAttributeDescription(); ssUpdatedAt.name = "updatedAt"; ssUpdatedAt.attributeType = .dateAttributeType; ssUpdatedAt.isOptional = true
        let ssSortOrder = NSAttributeDescription(); ssSortOrder.name = "sortOrder"; ssSortOrder.attributeType = .integer32AttributeType; ssSortOrder.isOptional = true; ssSortOrder.defaultValue = 0

        savedSnippet.properties = [ssId, ssTitle, ssContent, ssCreatedAt, ssUpdatedAt, ssSortOrder]

        model.entities = [clipboardItem, searchIndex, savedSnippet]
        return model
    }

    lazy var container: NSPersistentContainer = {
        let model = PersistenceController.createManagedObjectModel()
        let container = NSPersistentContainer(name: "DataModel", managedObjectModel: model)
        
        // Configure for high performance with large datasets
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description?.setOption(
            [
                "journal_mode": "WAL",
                "synchronous": "NORMAL",
                "cache_size": "10000",
            ] as NSDictionary,
            forKey: NSSQLitePragmasOption
        )
        if let description {
            migrateLegacyStoreIfNeeded(using: description)
        }
        
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Core Data error: \(error), \(error.userInfo)")
            }
        }
        
        // Configure context for performance
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Core Data save error: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func migrateLegacyStoreIfNeeded(using description: NSPersistentStoreDescription) {
        guard let destinationURL = description.url else { return }

        let fileManager = FileManager.default
        let destinationSQLitePath = destinationURL.path
        if fileManager.fileExists(atPath: destinationSQLitePath) {
            return
        }

        let legacyBaseURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Klippy", isDirectory: true)
        let legacySQLiteURL = legacyBaseURL.appendingPathComponent("DataModel.sqlite")
        guard fileManager.fileExists(atPath: legacySQLiteURL.path) else { return }

        let destinationDirURL = destinationURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: destinationDirURL, withIntermediateDirectories: true)
        } catch {
            print("Failed to create destination directory for store migration: \(error)")
            return
        }

        let suffixes = ["", "-shm", "-wal"]
        for suffix in suffixes {
            let legacyURL = URL(fileURLWithPath: legacySQLiteURL.path + suffix)
            let destinationFileURL = URL(fileURLWithPath: destinationSQLitePath + suffix)

            guard fileManager.fileExists(atPath: legacyURL.path) else { continue }
            guard !fileManager.fileExists(atPath: destinationFileURL.path) else { continue }

            do {
                try fileManager.copyItem(at: legacyURL, to: destinationFileURL)
            } catch {
                print("Failed to migrate store component \(legacyURL.lastPathComponent): \(error)")
            }
        }
    }
    
    private init() {}
}
