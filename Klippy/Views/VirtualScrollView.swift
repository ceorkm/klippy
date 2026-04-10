import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// High-performance virtual scrolling view for handling large datasets
struct VirtualScrollView<Content: View, Item: Identifiable>: View {
    let items: [Item]
    let itemHeight: CGFloat
    let content: (Item) -> Content

    init(
        items: [Item],
        itemHeight: CGFloat = 60,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.itemHeight = itemHeight
        self.content = content
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.id) { item in
                    content(item)
                        .frame(height: itemHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(ScrollElasticityConfigurator())
        }
    }
}

private struct ScrollElasticityConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
        }
    }
}

// MARK: - Clipboard Item Row

struct VirtualClipboardItemRow: View {
    let item: ClipboardItemViewModel
    var isFavorite: Bool = false
    var onCopied: (() -> Void)? = nil
    var onDeleted: (() -> Void)? = nil
    var onFavoriteToggled: ((Bool) -> Void)? = nil
    var onSaveSnippet: (() -> Void)? = nil
    var isMergePending: Bool = false
    var hasMergePending: Bool = false
    var onMergeSelect: (() -> Void)? = nil
    var onMergeCombine: (() -> Void)? = nil
    var onMergeCancel: (() -> Void)? = nil
    var onOpenMerged: (() -> Void)? = nil
    @State private var isHovered = false
    @AppStorage("klippy.ui.textSize") private var textSize: Double = 16

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                itemPreview

                VStack(alignment: .leading, spacing: 6) {
                    Text(itemDisplayText)
                        .lineLimit(3)
                        .font(.system(size: clampedTextSize, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        if item.isMergedClip {
                            Text("MERGED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange, in: Capsule())
                        }

                        if let sourceApplication = item.sourceApplication, !sourceApplication.isEmpty {
                            Text(sourceApplication)
                                .font(.system(size: metadataTextSize))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                    }
                }

                VStack(alignment: .trailing, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Self.rowDateFormatter.string(from: item.createdAt))
                            .font(.system(size: dateTextSize, weight: .semibold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Text(Self.rowTimeFormatter.string(from: item.createdAt))
                            .font(.system(size: dateTextSize, weight: .semibold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Button(action: deleteItem) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .overlay(Color.primary.opacity(0.14))
                .padding(.leading, 12)
                .padding(.trailing, 6)
        }
        .background(
            isMergePending
                ? Color.orange.opacity(0.15)
                : Color.primary.opacity(isHovered ? 0.08 : 0)
        )
        .overlay(alignment: .leading) {
            if isMergePending {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if hasMergePending {
                onMergeCombine?()
            } else if isMergePending {
                onMergeCancel?()
            } else if item.isMergedClip {
                onOpenMerged?()
            } else {
                copyItem()
            }
        }
        .onDrag {
            dragItemProvider()
        }
        .contextMenu {
            Button("Copy") {
                copyItem()
            }

            Button("Share...") {
                shareItem()
            }

            Button(isFavorite ? "Unpin" : "Pin") {
                toggleFavorite()
            }

            if !item.isImage {
                Button("Save") {
                    onSaveSnippet?()
                }
            }

            if !item.isImage {
                if isMergePending {
                    Button("Cancel Merge") {
                        onMergeCancel?()
                    }
                } else if hasMergePending {
                    Button("Merge with Selected") {
                        onMergeCombine?()
                    }
                } else {
                    Button("Select for Merge") {
                        onMergeSelect?()
                    }
                }
            }

            Button("Delete") {
                deleteItem()
            }
        }
    }

    private var itemDisplayText: String {
        if item.isImage {
            return "\(item.content) • \(item.imageSizeString)"
        }

        if item.isImageFileReference {
            return "Image"
        }

        if item.isFileReference {
            return item.fileDisplayText
        }

        return item.displayText
    }

    private var clampedTextSize: CGFloat {
        CGFloat(min(max(textSize, 13), 24))
    }

    private var metadataTextSize: CGFloat {
        max(11, clampedTextSize - 4)
    }

    private var dateTextSize: CGFloat {
        max(10, clampedTextSize - 4)
    }

    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d yyyy"
        return formatter
    }()

    private static let rowTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var itemPreview: some View {
        Group {
            if let previewImage = item.isImage ? item.thumbnailImage : item.listPreviewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: item.category.iconName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.category.color)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 42, height: 42)
            }
        }
    }

    private func copyItem() {
        ClipboardManager.shared.copyToClipboard(item)
        onCopied?()
    }

    private func shareItem() {
        let sharingService = NSSharingService(named: .sendViaAirDrop)

        if item.isImage, let image = item.nsImage {
            sharingService?.perform(withItems: [image])
        } else if item.isFileReference {
            let existingURLs = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !existingURLs.isEmpty {
                sharingService?.perform(withItems: existingURLs)
            } else {
                sharingService?.perform(withItems: [fileReferenceShareFallbackText])
            }
        } else {
            sharingService?.perform(withItems: [item.content])
        }
    }

    private var fileReferenceShareFallbackText: String {
        let filePaths = item.fileURLs
            .filter { $0.isFileURL && !$0.path.isEmpty }
            .map(\.path)
        if !filePaths.isEmpty {
            return filePaths.joined(separator: "\n")
        }
        return item.fileDisplayText
    }

    private func dragItemProvider() -> NSItemProvider {
        if item.isImage, let data = item.imageData {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.png.identifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        }

        if item.isFileReference, let firstFileURL = item.fileURLs.first {
            return NSItemProvider(object: firstFileURL as NSURL)
        }

        return NSItemProvider(object: item.content as NSString)
    }

    private func deleteItem() {
        ClipboardManager.shared.deleteItem(itemId: item.id)
        onDeleted?()
    }

    private func toggleFavorite() {
        let isNowFavorite = ClipboardManager.shared.toggleFavorite(itemId: item.id)
        onFavoriteToggled?(isNowFavorite)
    }
}

#Preview {
    VirtualScrollView(
        items: Array(0..<1000).map { index in
            ClipboardItemViewModel(
                id: UUID(),
                content: "Sample clipboard item #\(index) with some content to display",
                category: ContentCategory.allCases.randomElement() ?? .text,
                createdAt: Date().addingTimeInterval(-Double(index * 60)),
                lastAccessedAt: Date(),
                usageCount: Int32.random(in: 0...10),
                sourceApplication: ["Safari", "Xcode", "TextEdit", "Mail"].randomElement()
            )
        },
        itemHeight: 60
    ) { item in
        VirtualClipboardItemRow(item: item)
    }
    .frame(width: 400, height: 600)
}
