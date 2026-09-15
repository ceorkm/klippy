import SwiftUI
import CoreData
import AppKit

@main
struct KlippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The panel is an NSPanel owned by PanelController, not a SwiftUI scene,
        // so the app only needs a scene here to satisfy the App protocol.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = PersistenceController.shared
        PanelController.shared.install()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ClipboardManager.shared.startMonitoring()
            print("Klippy started — menu bar item installed, ⌃⌘V opens the panel")

            // Runs once per launch, and does nothing unless the user opted in.
            let days = UserDefaults.standard.integer(forKey: ClipboardManager.autoDeleteDaysKey)
            if days > 0 {
                ClipboardManager.shared.pruneUnusedClips(olderThanDays: days)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DragExport.clear()
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
        
        var loadFailure: NSError?
        container.loadPersistentStores { _, error in
            loadFailure = error as NSError?
        }

        // A store that will not open used to crash the app on launch, which
        // meant one bad write (power loss mid-save, a full disk) left Klippy
        // unable to start ever again, with no way out but deleting files by
        // hand in Library. Move the unreadable store aside instead and come up
        // empty: the old file is kept so the history can still be recovered
        // with Import, and the app stays usable meanwhile.
        if let loadFailure {
            print("Core Data store would not open: \(loadFailure)")
            Self.setAside(description?.url)
            container.loadPersistentStores { _, secondError in
                if let secondError {
                    // Nothing left to try. Better to run without history than
                    // not to run at all.
                    print("Core Data still unavailable after reset: \(secondError)")
                }
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
                // Losing one unsaved change is recoverable. Killing the app
                // over it, which is what this used to do, is not.
                print("Core Data save failed: \(error as NSError)")
                context.rollback()
            }
        }
    }

    /// Renames an unreadable store so a fresh one can be created beside it.
    ///
    /// Nothing is deleted. The damaged files keep their data for recovery and
    /// stay next to the working store rather than disappearing.
    private static func setAside(_ storeURL: URL?) {
        guard let storeURL else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-shm", "-wal"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: storeURL.path + ".damaged-" + stamp + suffix)
            try? FileManager.default.moveItem(at: source, to: destination)
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
