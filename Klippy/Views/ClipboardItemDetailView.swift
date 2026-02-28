import SwiftUI
import UniformTypeIdentifiers

struct ClipboardItemDetailView: View {
    let item: ClipboardItemViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: item.category.iconName)
                    .foregroundColor(item.category.color)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.category.displayName)
                        .font(.headline)
                        .foregroundColor(item.category.color)
                    
                    Text("Created \(item.relativeTimeString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
            }
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.isImage ? "Image" : "Content")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if item.isImage, let image = item.nsImage {
                        // Display image
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        // Display text content
                        Text(item.content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                    
                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        DetailRow(label: "Type", value: item.category.displayName)
                        DetailRow(label: "Created", value: formatDate(item.createdAt))
                        DetailRow(label: "Last Used", value: formatDate(item.lastAccessedAt))
                        DetailRow(label: "Usage Count", value: "\(item.usageCount)")
                        
                        if let sourceApp = item.sourceApplication {
                            DetailRow(label: "Source App", value: sourceApp)
                        }

                        if item.isImage {
                            DetailRow(label: "Dimensions", value: item.imageSizeString)
                            if let imageData = item.imageData {
                                DetailRow(label: "File Size", value: formatFileSize(imageData.count))
                            }
                        } else {
                            DetailRow(label: "Length", value: "\(item.content.count) characters")
                        }
                    }
                }
            }
            
            // Actions
            HStack {
                Button("Copy to Clipboard") {
                    ClipboardManager.shared.copyToClipboard(item)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button("Share") {
                    shareContent()
                }
                
                Button("Export") {
                    exportContent()
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func shareContent() {
        let sharingService = NSSharingService(named: .sendViaAirDrop)
        if item.isImage, let image = item.nsImage {
            sharingService?.perform(withItems: [image])
        } else {
            sharingService?.perform(withItems: [item.content])
        }
    }

    private func exportContent() {
        let savePanel = NSSavePanel()

        if item.isImage {
            savePanel.allowedContentTypes = [.png]
            savePanel.nameFieldStringValue = "image.png"

            if savePanel.runModal() == .OK, let url = savePanel.url, let imageData = item.imageData {
                do {
                    try imageData.write(to: url)
                } catch {
                    print("Failed to export image: \(error)")
                }
            }
        } else {
            savePanel.allowedContentTypes = [.plainText]
            savePanel.nameFieldStringValue = "clipboard_item.txt"

            if savePanel.runModal() == .OK, let url = savePanel.url {
                do {
                    try item.content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to export content: \(error)")
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
}

#Preview {
    ClipboardItemDetailView(
        item: ClipboardItemViewModel(
            id: UUID(),
            content: "This is a sample clipboard item with some content to display in the detail view.",
            category: .text,
            createdAt: Date(),
            lastAccessedAt: Date(),
            usageCount: 5,
            sourceApplication: "Safari"
        )
    )
}
