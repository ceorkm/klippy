import Foundation
import CoreData
import AppKit

class SnippetManager: ObservableObject {
    static let shared = SnippetManager()

    @Published var snippets: [SavedSnippetViewModel] = []

    private lazy var backgroundContext: NSManagedObjectContext = {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()

    private init() {
        loadSnippets()
    }

    func loadSnippets() {
        let context = backgroundContext
        context.perform { [weak self] in
            let request: NSFetchRequest<SavedSnippet> = SavedSnippet.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \SavedSnippet.sortOrder, ascending: true),
                NSSortDescriptor(keyPath: \SavedSnippet.createdAt, ascending: false)
            ]

            do {
                let results = try context.fetch(request)
                let viewModels = results.map { SavedSnippetViewModel(from: $0) }
                DispatchQueue.main.async {
                    self?.snippets = viewModels
                }
            } catch {
                print("Failed to load snippets: \(error)")
            }
        }
    }

    func createSnippet(title: String, content: String) {
        let context = backgroundContext
        context.performAndWait {
            _ = SavedSnippet.create(title: title, content: content, context: context)
            do {
                try context.save()
            } catch {
                print("Failed to save snippet: \(error)")
            }
        }
        loadSnippets()
    }

    func saveFromClipboardItem(_ item: ClipboardItemViewModel, title: String) {
        createSnippet(title: title, content: item.content)
    }

    func updateSnippet(id: UUID, title: String, content: String) {
        let context = backgroundContext
        context.performAndWait {
            let request: NSFetchRequest<SavedSnippet> = SavedSnippet.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            do {
                guard let snippet = try context.fetch(request).first else { return }
                snippet.title = title
                snippet.content = content
                snippet.updatedAt = Date()
                try context.save()
            } catch {
                print("Failed to update snippet: \(error)")
            }
        }
        loadSnippets()
    }

    func deleteSnippet(id: UUID) {
        let context = backgroundContext
        context.performAndWait {
            let request: NSFetchRequest<SavedSnippet> = SavedSnippet.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            do {
                guard let snippet = try context.fetch(request).first else { return }
                context.delete(snippet)
                try context.save()
            } catch {
                print("Failed to delete snippet: \(error)")
            }
        }
        loadSnippets()
    }

    func copySnippetToClipboard(_ snippet: SavedSnippetViewModel) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.content, forType: .string)
    }

    func filteredSnippets(query: String) -> [SavedSnippetViewModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return snippets }
        return snippets.filter {
            $0.title.lowercased().contains(trimmed) ||
            $0.content.lowercased().contains(trimmed)
        }
    }
}
