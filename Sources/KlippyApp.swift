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
    
    lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "DataModel")
        
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
