import SwiftUI

struct SnippetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    let existingSnippet: SavedSnippetViewModel?
    let onSave: (String, String) -> Void

    init(
        snippet: SavedSnippetViewModel? = nil,
        onSave: @escaping (String, String) -> Void
    ) {
        self.existingSnippet = snippet
        self._title = State(initialValue: snippet?.title ?? "")
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename")
                .font(.headline)

            TextField("e.g. Cloudflare password", text: $title)
                .textFieldStyle(.roundedBorder)

            if let snippet = existingSnippet {
                Text(String(snippet.content.prefix(100)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Clear Name") {
                        let content = existingSnippet?.content ?? ""
                        let autoTitle = String(content.prefix(40))
                        onSave(autoTitle, content)
                        dismiss()
                    }
                }

                Button("Save") {
                    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let content = existingSnippet?.content ?? ""
                    let finalTitle = trimmed.isEmpty ? String(content.prefix(40)) : trimmed
                    onSave(finalTitle, content)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
