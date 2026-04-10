import SwiftUI
import CoreData
import AppKit
import UniformTypeIdentifiers
import ServiceManagement

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var clipboardManager = ClipboardManager.shared
    @StateObject private var searchEngine = SearchEngine()
    @StateObject private var snippetManager = SnippetManager.shared

    @State private var searchText = ""
    @State private var selectedCategory: ContentCategory = .all
    @State private var selectedDateFilter: ItemDateFilter = .allTime
    @State private var showingCustomDateRangePicker = false
    @State private var customRangeStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customRangeEndDate = Date()
    @State private var showingSettings = false
    @State private var showingSaved = false
    @State private var showingPinned = false
    @State private var showingMerged = false
    @State private var showingSnippetEditor = false
    @State private var editingSnippet: SavedSnippetViewModel? = nil
    @State private var showingSavePopover = false
    @State private var snippetSaveTitle = ""
    @State private var snippetSaveContent = ""
    @State private var pendingMergeItem: ClipboardItemViewModel? = nil
    @State private var showingMergePreview = false
    @State private var mergedItems: [ClipboardItemViewModel] = []
    @State private var showingSpotPanel = false
    @State private var spotQuery = ""
    @State private var isDropTargeted = false
    @State private var toast: ToastState?
    @AppStorage("klippy.ui.textSize") private var textSize: Double = 16

    @FocusState private var isSearchFieldFocused: Bool
    @FocusState private var isSpotFieldFocused: Bool

    private let dropTypes: [UTType] = [.plainText, .utf8PlainText, .url, .fileURL, .png, .tiff]
    private var listRowHeight: CGFloat {
        let clamped = min(max(textSize, 13), 24)
        return max(96, clamped * 6.2)
    }

    var body: some View {
        let items = filteredItems

        ZStack {
            LinearGradient(
                colors: [
                    Color(.windowBackgroundColor),
                    Color(.underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                headerCard(resultCount: items.count)
                if showingSaved {
                    savedSnippetsCard
                } else if showingPinned {
                    pinnedOnlyCard
                } else if showingMerged {
                    mergedOnlyCard
                } else {
                    categoryStrip
                    if let pending = pendingMergeItem {
                        mergeBanner(pending: pending)
                    }
                    listCard(items: items)
                }
                footerBar(resultCount: items.count)
            }
            .padding(10)

            if showingMergePreview {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingMergePreview = false
                    }
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "link.circle.fill")
                            .foregroundColor(.orange)
                        Text("Merged Clips")
                            .font(.headline)
                        Spacer()
                        Button {
                            showingMergePreview = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Tap any item to copy it")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    VStack(spacing: 6) {
                        ForEach(Array(mergedItems.enumerated()), id: \.offset) { _, mergedItem in
                            mergedItemRow(mergedItem)
                        }
                    }
                }
                .padding(16)
                .frame(width: 340)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(6)
            }

            if showingSavePopover {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingSavePopover = false
                    }
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Save")
                        .font(.headline)

                    TextField("Name (optional)", text: $snippetSaveTitle)
                        .textFieldStyle(.roundedBorder)

                    Text("Content")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $snippetSaveContent)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 100)
                        .padding(4)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )

                    HStack {
                        Button("Cancel") {
                            showingSavePopover = false
                        }
                        Spacer()
                        Button("Save") {
                            let trimmed = snippetSaveTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            let title = trimmed.isEmpty ? String(snippetSaveContent.prefix(40)) : trimmed
                            snippetManager.createSnippet(title: title, content: snippetSaveContent)
                            showingSavePopover = false
                            FeedbackManager.playSave(); showToast("Saved", symbol: "bookmark.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(snippetSaveContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .frame(width: 320)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(5)
            }

            if showingSpotPanel {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeSpotPanel()
                    }
                    .transition(.opacity)

                spotPanel
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(3)
            }

            if let toast {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ToastView(symbol: toast.symbolName, message: toast.message)
                            .padding(.trailing, 24)
                            .padding(.bottom, 24)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(4)
            }
        }
        .frame(width: 430, height: 650)
        .animation(.easeInOut(duration: 0.16), value: selectedCategory)
        .animation(.easeInOut(duration: 0.16), value: searchText)
        .animation(.easeInOut(duration: 0.16), value: selectedDateFilter)
        .animation(.easeInOut(duration: 0.16), value: customRangeStartDate)
        .animation(.easeInOut(duration: 0.16), value: customRangeEndDate)
        .animation(.easeInOut(duration: 0.16), value: showingSavePopover)
        .animation(.easeInOut(duration: 0.16), value: showingMergePreview)
        .animation(.easeInOut(duration: 0.16), value: showingSaved)
        .animation(.easeInOut(duration: 0.16), value: showingPinned)
        .animation(.easeInOut(duration: 0.16), value: showingMerged)
        .animation(.easeInOut(duration: 0.16), value: showingSpotPanel)
        .popover(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingCustomDateRangePicker) {
            customDateRangeEditor
        }
        .popover(isPresented: $showingSnippetEditor) {
            SnippetEditorView(
                snippet: editingSnippet
            ) { title, content in
                if let existing = editingSnippet {
                    snippetManager.updateSnippet(id: existing.id, title: title, content: content)
                }
                editingSnippet = nil
            }
        }
        .onAppear {
            clipboardManager.refreshHistory()
        }
    }

    private func headerCard(resultCount: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.94), Color.yellow.opacity(0.86)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Klippy")
                        .font(.headline)
                    Text("Clipboard manager")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    topIconButton(
                        systemName: showingMerged ? "link.circle.fill" : "link",
                        helpText: showingMerged ? "Show History" : "Merged"
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showingMerged.toggle()
                            if showingMerged {
                                showingSaved = false
                                showingPinned = false
                            }
                        }
                    }

                    topIconButton(
                        systemName: showingPinned ? "pin.fill" : "pin",
                        helpText: showingPinned ? "Show History" : "Pinned"
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showingPinned.toggle()
                            if showingPinned {
                                showingSaved = false
                                showingMerged = false
                            }
                        }
                    }

                    topIconButton(
                        systemName: showingSaved ? "bookmark.fill" : "bookmark",
                        helpText: showingSaved ? "Show History" : "Saved"
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showingSaved.toggle()
                            if showingSaved {
                                showingPinned = false
                                showingMerged = false
                            }
                        }
                    }

                    topIconButton(systemName: "gearshape.fill", helpText: "Settings") {
                        showingSettings.toggle()
                    }

                    topIconButton(systemName: "xmark.circle.fill", helpText: "Quit Klippy") {
                        quitApp()
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField(showingSaved ? "Search saved items" : "Search clipboard history", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onTapGesture {
                        isSearchFieldFocused = true
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            HStack(spacing: 8) {
                badge(label: "Saved", value: "\(clipboardManager.totalItemCount)")

                if !searchText.isEmpty {
                    badge(label: "Matches", value: "\(resultCount)")
                }

                dateFilterMenu

                Spacer()

                if !searchText.isEmpty {
                    badge(label: "Search", value: "Active")
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    private var dateFilterMenu: some View {
        Menu {
            ForEach(ItemDateFilter.quickCases) { option in
                Button {
                    selectedDateFilter = option
                } label: {
                    if selectedDateFilter == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }

            Divider()

            Button {
                showingCustomDateRangePicker = true
            } label: {
                if selectedDateFilter == .custom {
                    Label("Custom range…", systemImage: "checkmark")
                } else {
                    Text("Custom range…")
                }
            }
        } label: {
            badge(label: "Date", value: selectedDateFilterLabel)
        }
        .menuStyle(.borderlessButton)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categoryFilterOrder, id: \.self) { category in
                    CategoryPillButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func mergedItemRow(_ item: ClipboardItemViewModel) -> some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.content, forType: .string)
            FeedbackManager.playCopy(); showToast("Copied", symbol: "checkmark.circle.fill")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.category.iconName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.category.color)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24)

                Text(item.content)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func mergeBanner(pending: ClipboardItemViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 1) {
                Text("Selected for merge")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(pending.content.prefix(40)))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            Spacer()

            Text("Pick another →")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button {
                pendingMergeItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Cancel merge")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func listCard(items: [ClipboardItemViewModel]) -> some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass.circle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(searchText.isEmpty ? "Clipboard is Ready" : "No Results")
                        .font(.headline)

                    Text(searchText.isEmpty
                         ? "Copy text, links, or images and they will appear here. You can also drop content into this area."
                         : "Try another term, switch category, or broaden the date filter.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(20)
            } else {
                VirtualScrollView(
                    items: items,
                    itemHeight: listRowHeight
                ) { item in
                    VirtualClipboardItemRow(
                        item: item,
                        isFavorite: clipboardManager.isFavorite(itemId: item.id),
                        onCopied: {
                            FeedbackManager.playCopy(); showToast("Copied to clipboard", symbol: "checkmark.circle.fill")
                        },
                        onDeleted: {
                            FeedbackManager.playDelete(); showToast("Item deleted", symbol: "trash")
                        },
                        onFavoriteToggled: { isNowFavorite in
                            FeedbackManager.playPin()
                            showToast(isNowFavorite ? "Pinned item" : "Unpinned item", symbol: isNowFavorite ? "star.fill" : "star")
                        },
                        onSaveSnippet: {
                            snippetSaveContent = item.content
                            snippetSaveTitle = ""
                            showingSavePopover = true
                        },
                        isMergePending: pendingMergeItem?.id == item.id,
                        hasMergePending: pendingMergeItem != nil && pendingMergeItem?.id != item.id,
                        onMergeSelect: {
                            pendingMergeItem = item
                            showToast("Selected for merge — pick another", symbol: "link")
                        },
                        onMergeCombine: {
                            guard let first = pendingMergeItem else { return }
                            // Create a merged clipboard item — lives in the main list, not Saved.
                            clipboardManager.createMergedClip(components: [first.content, item.content])

                            mergedItems = [first, item]
                            pendingMergeItem = nil
                            showingMergePreview = true
                            FeedbackManager.playMerge(); showToast("Merged", symbol: "link.circle.fill")
                        },
                        onMergeCancel: {
                            pendingMergeItem = nil
                        },
                        onOpenMerged: {
                            let classifier = ContentClassifier()
                            let components = item.mergedComponents
                            mergedItems = components.map { content in
                                ClipboardItemViewModel(
                                    id: UUID(),
                                    content: content,
                                    category: classifier.classify(content),
                                    createdAt: item.createdAt,
                                    lastAccessedAt: item.lastAccessedAt,
                                    usageCount: 0,
                                    sourceApplication: nil
                                )
                            }
                            showingMergePreview = true
                        }
                    )
                }
                .id("list-\(selectedCategory.rawValue)-\(selectedDateFilter.rawValue)-\(customRangeCacheToken)-\(searchText)")
                .padding(8)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .onDrop(of: dropTypes, isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footerBar(resultCount: Int) -> some View {
        HStack {
            Text(searchText.isEmpty
                 ? "\(clipboardManager.totalItemCount) total"
                 : "\(resultCount) showing from \(clipboardManager.totalItemCount)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text("\(selectedCategory.displayName) • \(selectedDateFilterLabel)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var selectedDateFilterLabel: String {
        if selectedDateFilter == .custom {
            return customDateRangeSummary
        }
        return selectedDateFilter.displayName
    }

    private var customRangeCacheToken: String {
        let start = min(customRangeStartDate, customRangeEndDate).timeIntervalSince1970
        let end = max(customRangeStartDate, customRangeEndDate).timeIntervalSince1970
        return "\(Int(start))-\(Int(end))"
    }

    private var customDateRangeSummary: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let start = min(customRangeStartDate, customRangeEndDate)
        let end = max(customRangeStartDate, customRangeEndDate)

        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }

        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }

    private var selectedDateRange: SearchEngine.DateRange? {
        selectedDateFilter.makeRange(
            referenceDate: Date(),
            calendar: .current,
            customStartDate: customRangeStartDate,
            customEndDate: customRangeEndDate
        )
    }

    private var categoryFilterOrder: [ContentCategory] {
        let prioritized: [ContentCategory] = [.all, .text, .url, .image, .file, .ipAddress, .apiKey, .paymentCard]
        let remaining = ContentCategory.allCases.filter { !prioritized.contains($0) }
        return prioritized + remaining
    }

    private var mergedOnlyCard: some View {
        let results = searchEngine.search(
            query: searchText,
            category: .merged,
            dateRange: selectedDateRange,
            limit: 180
        )
        let filtered = applyDateRangeFilter(results)

        return Group {
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: searchText.isEmpty ? "link.circle" : "magnifyingglass.circle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(searchText.isEmpty ? "No Merged Clips" : "No Results")
                        .font(.headline)

                    Text(searchText.isEmpty
                         ? "Right-click an item, pick \"Select for Merge\", then tap another to merge them."
                         : "Try another search term.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VirtualScrollView(
                    items: filtered,
                    itemHeight: listRowHeight
                ) { item in
                    VirtualClipboardItemRow(
                        item: item,
                        isFavorite: clipboardManager.isFavorite(itemId: item.id),
                        onCopied: {
                            FeedbackManager.playCopy(); showToast("Copied to clipboard", symbol: "checkmark.circle.fill")
                        },
                        onDeleted: {
                            FeedbackManager.playDelete(); showToast("Item deleted", symbol: "trash")
                        },
                        onFavoriteToggled: { isNowFavorite in
                            FeedbackManager.playPin()
                            showToast(isNowFavorite ? "Pinned item" : "Unpinned item", symbol: isNowFavorite ? "star.fill" : "star")
                        },
                        onOpenMerged: {
                            let classifier = ContentClassifier()
                            let components = item.mergedComponents
                            mergedItems = components.map { content in
                                ClipboardItemViewModel(
                                    id: UUID(),
                                    content: content,
                                    category: classifier.classify(content),
                                    createdAt: item.createdAt,
                                    lastAccessedAt: item.lastAccessedAt,
                                    usageCount: 0,
                                    sourceApplication: nil
                                )
                            }
                            showingMergePreview = true
                        }
                    )
                }
                .id("merged-list-\(searchText)")
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pinnedOnlyCard: some View {
        let pinned = clipboardManager.fetchAllPinnedItems()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = trimmed.isEmpty
            ? pinned
            : pinned.filter { $0.content.lowercased().contains(trimmed) }

        return Group {
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: searchText.isEmpty ? "pin" : "magnifyingglass.circle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(searchText.isEmpty ? "No Pinned Items" : "No Results")
                        .font(.headline)

                    Text(searchText.isEmpty
                         ? "Right-click any clipboard item and tap \"Pin\" to keep it here."
                         : "Try another search term.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VirtualScrollView(
                    items: filtered,
                    itemHeight: listRowHeight
                ) { item in
                    VirtualClipboardItemRow(
                        item: item,
                        isFavorite: true,
                        onCopied: {
                            FeedbackManager.playCopy(); showToast("Copied to clipboard", symbol: "checkmark.circle.fill")
                        },
                        onDeleted: {
                            FeedbackManager.playDelete(); showToast("Item deleted", symbol: "trash")
                        },
                        onFavoriteToggled: { isNowFavorite in
                            FeedbackManager.playPin()
                            showToast(isNowFavorite ? "Pinned item" : "Unpinned item", symbol: isNowFavorite ? "star.fill" : "star")
                        }
                    )
                }
                .id("pinned-list-\(searchText)")
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var savedSnippetsCard: some View {
        Group {
            let results = snippetManager.filteredSnippets(query: searchText)
            if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: searchText.isEmpty ? "bookmark" : "magnifyingglass.circle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(searchText.isEmpty ? "No Saved Items" : "No Results")
                        .font(.headline)

                    Text(searchText.isEmpty
                         ? "Right-click any clipboard item and tap \"Save\" to keep it here."
                         : "Try another search term.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VirtualScrollView(
                    items: results,
                    itemHeight: listRowHeight
                ) { snippet in
                    savedSnippetRow(snippet)
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func savedSnippetRow(_ snippet: SavedSnippetViewModel) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: snippet.isMerged ? "link.circle.fill" : "bookmark.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    if !snippet.title.isEmpty && snippet.title != String(snippet.content.prefix(40)) {
                        HStack(spacing: 4) {
                            if snippet.isMerged {
                                Text("MERGED")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange, in: Capsule())
                            }
                            Text(snippet.title)
                                .font(.system(size: max(11, CGFloat(min(max(textSize, 13), 24)) - 3), weight: .medium))
                                .foregroundColor(.orange)
                                .lineLimit(1)
                        }
                    }

                    Text(snippet.displayContent)
                        .lineLimit(3)
                        .font(.system(size: CGFloat(min(max(textSize, 13), 24)), weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .trailing, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Self.savedDateFormatter.string(from: snippet.createdAt))
                            .font(.system(size: max(10, CGFloat(min(max(textSize, 13), 24)) - 4), weight: .semibold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Button {
                        snippetManager.deleteSnippet(id: snippet.id)
                        FeedbackManager.playDelete(); showToast("Removed", symbol: "trash")
                    } label: {
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
        .contentShape(Rectangle())
        .onTapGesture {
            if snippet.isMerged {
                openMergedSnippet(snippet)
            } else {
                snippetManager.copySnippetToClipboard(snippet)
                FeedbackManager.playCopy(); showToast("Copied", symbol: "checkmark.circle.fill")
            }
        }
        .contextMenu {
            if snippet.isMerged {
                Button("Open") {
                    openMergedSnippet(snippet)
                }
            } else {
                Button("Copy") {
                    snippetManager.copySnippetToClipboard(snippet)
                    FeedbackManager.playCopy(); showToast("Copied", symbol: "checkmark.circle.fill")
                }
            }

            Button("Rename") {
                editingSnippet = snippet
                showingSnippetEditor = true
            }

            Button("Delete") {
                snippetManager.deleteSnippet(id: snippet.id)
                FeedbackManager.playDelete(); showToast("Removed", symbol: "trash")
            }
        }
    }

    private func openMergedSnippet(_ snippet: SavedSnippetViewModel) {
        // Reconstruct lightweight view models from component strings.
        // Classify each so the icons match what the content looks like.
        let classifier = ContentClassifier()
        let components = snippet.mergedComponents
        mergedItems = components.map { content in
            ClipboardItemViewModel(
                id: UUID(),
                content: content,
                category: classifier.classify(content),
                createdAt: snippet.createdAt,
                lastAccessedAt: snippet.updatedAt,
                usageCount: 0,
                sourceApplication: nil
            )
        }
        showingMergePreview = true
    }

    private static let savedDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var filteredItems: [ClipboardItemViewModel] {
        let results = searchEngine.search(
            query: searchText,
            category: selectedCategory,
            dateRange: selectedDateRange,
            limit: 180
        )
        return mergeWithPinned(applyDateRangeFilter(results))
    }

    /// Ensures ALL pinned items appear at the top, even if they fall outside
    /// the search/category/date window. Pinned items are fetched directly from
    /// Core Data so they persist regardless of how old they are.
    private func mergeWithPinned(_ items: [ClipboardItemViewModel]) -> [ClipboardItemViewModel] {
        let pinnedAll = clipboardManager.fetchAllPinnedItems()
        guard !pinnedAll.isEmpty else { return items }

        // Apply current filters to pinned items too so switching category hides irrelevant pins
        let filteredPinned = pinnedAll.filter { pinned in
            // Category filter
            if selectedCategory != .all && pinned.category != selectedCategory {
                return false
            }
            // Date range filter
            if let range = selectedDateRange {
                if pinned.createdAt < range.start || pinned.createdAt >= range.end {
                    return false
                }
            }
            // Search filter (simple contains match)
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty && !pinned.content.lowercased().contains(trimmed) {
                return false
            }
            return true
        }

        // Deduplicate: remove pinned items from the regular list since they'll appear at top
        let pinnedIDs = Set(filteredPinned.map(\.id))
        let unpinnedItems = items.filter { !pinnedIDs.contains($0.id) }

        return filteredPinned + unpinnedItems
    }

    private var spotResults: [ClipboardItemViewModel] {
        let trimmed = spotQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Array(filteredItems.prefix(10))
        }

        let results = searchEngine.search(
            query: trimmed,
            category: selectedCategory,
            dateRange: selectedDateRange,
            limit: 12
        )
        return prioritizeFavorites(in: applyDateRangeFilter(results))
    }

    private func prioritizeFavorites(in items: [ClipboardItemViewModel]) -> [ClipboardItemViewModel] {
        guard !items.isEmpty else { return [] }

        var favorites: [ClipboardItemViewModel] = []
        var regular: [ClipboardItemViewModel] = []
        favorites.reserveCapacity(items.count / 3)
        regular.reserveCapacity(items.count)

        for item in items {
            if clipboardManager.isFavorite(itemId: item.id) {
                favorites.append(item)
            } else {
                regular.append(item)
            }
        }

        return favorites + regular
    }

    private var spotPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Spot a clipboard item", text: $spotQuery)
                    .textFieldStyle(.plain)
                    .focused($isSpotFieldFocused)

                Button {
                    closeSpotPanel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if spotResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("No matching items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(spotResults) { item in
                            SpotResultRow(item: item) {
                                ClipboardManager.shared.copyToClipboard(item)
                                FeedbackManager.playCopy(); showToast("Copied from Spot", symbol: "sparkles")
                                closeSpotPanel()
                            }
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            HStack {
                Text("Return to copy • Esc to close")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 390, height: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)
        .onAppear {
            DispatchQueue.main.async {
                isSpotFieldFocused = true
            }
        }
    }

    private func openSpotPanel() {
        spotQuery = searchText
        withAnimation(.easeInOut(duration: 0.16)) {
            showingSpotPanel = true
        }
    }

    private func closeSpotPanel() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showingSpotPanel = false
        }
        isSpotFieldFocused = false
    }

    private func applyDateRangeFilter(_ items: [ClipboardItemViewModel]) -> [ClipboardItemViewModel] {
        guard let range = selectedDateRange else { return items }
        return items.filter { $0.createdAt >= range.start && $0.createdAt < range.end }
    }

    private var customDateRangeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Date Range")
                .font(.headline)

            DatePicker("From", selection: $customRangeStartDate, displayedComponents: .date)
                .datePickerStyle(.field)

            DatePicker("To", selection: $customRangeEndDate, displayedComponents: .date)
                .datePickerStyle(.field)

            Text("Items copied between these dates (inclusive).")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Cancel") {
                    showingCustomDateRangePicker = false
                }

                Spacer()

                Button("Any time") {
                    selectedDateFilter = .allTime
                    showingCustomDateRangePicker = false
                }

                Button("Apply") {
                    selectedDateFilter = .custom
                    showingCustomDateRangePicker = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func topIconButton(systemName: String, helpText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.88))
                .padding(8)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func badge(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        let fileLoadGroup = DispatchGroup()
        let fileURLQueue = DispatchQueue(label: "klippy.drop.files")
        var droppedFileURLs: [URL] = []

        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    DispatchQueue.main.async {
                        writeImageToPasteboard(image)
                        showToast("Image added from drop", symbol: "photo.fill")
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let string = object as? String else { return }
                    DispatchQueue.main.async {
                        writeTextToPasteboard(string)
                        showToast("Text added from drop", symbol: "arrow.down.doc.fill")
                    }
                }
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                fileLoadGroup.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let fileURL: URL?

                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        fileURL = url
                    } else if let url = item as? URL {
                        fileURL = url
                    } else if let string = item as? String {
                        if let parsed = URL(string: string), parsed.isFileURL {
                            fileURL = parsed
                        } else {
                            fileURL = URL(fileURLWithPath: (string as NSString).expandingTildeInPath)
                        }
                    } else {
                        fileURL = nil
                    }

                    if let fileURL {
                        fileURLQueue.sync {
                            droppedFileURLs.append(fileURL)
                        }
                    }

                    fileLoadGroup.leave()
                }
            }
        }

        fileLoadGroup.notify(queue: .main) {
            guard !droppedFileURLs.isEmpty else { return }
            writeFileURLsToPasteboard(droppedFileURLs)
            let count = droppedFileURLs.count
            let message = count == 1 ? "File added from drop" : "\(count) files added from drop"
            showToast(message, symbol: "folder.fill")
        }

        return handled
    }

    private func writeTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func writeImageToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func writeFileURLsToPasteboard(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = pasteboard.writeObjects(fileURLs as [NSURL])
    }

    private func showToast(_ message: String, symbol: String) {
        let nextToast = ToastState(id: UUID(), message: message, symbolName: symbol)

        withAnimation(.easeInOut(duration: 0.18)) {
            toast = nextToast
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard toast?.id == nextToast.id else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                toast = nil
            }
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Supporting Views

private struct ToastState: Equatable {
    let id: UUID
    let message: String
    let symbolName: String
}

private enum ItemDateFilter: String, CaseIterable, Identifiable {
    case allTime
    case today
    case yesterday
    case last7Days
    case last30Days
    case thisMonth
    case custom

    var id: String { rawValue }

    static var quickCases: [ItemDateFilter] {
        [.allTime, .today, .yesterday, .last7Days, .last30Days, .thisMonth]
    }

    var displayName: String {
        switch self {
        case .allTime: return "Any time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        case .thisMonth: return "This month"
        case .custom: return "Custom"
        }
    }

    func makeRange(
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        customStartDate: Date = Date(),
        customEndDate: Date = Date()
    ) -> SearchEngine.DateRange? {
        switch self {
        case .allTime:
            return nil

        case .today:
            let start = calendar.startOfDay(for: referenceDate)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return SearchEngine.DateRange(start: start, end: end)

        case .yesterday:
            let end = calendar.startOfDay(for: referenceDate)
            guard let start = calendar.date(byAdding: .day, value: -1, to: end) else { return nil }
            return SearchEngine.DateRange(start: start, end: end)

        case .last7Days:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
            guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate)) else {
                return nil
            }
            return SearchEngine.DateRange(start: start, end: end)

        case .last30Days:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
            guard let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: referenceDate)) else {
                return nil
            }
            return SearchEngine.DateRange(start: start, end: end)

        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: referenceDate)
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return nil
            }
            return SearchEngine.DateRange(start: start, end: end)

        case .custom:
            let from = min(customStartDate, customEndDate)
            let to = max(customStartDate, customEndDate)

            let start = calendar.startOfDay(for: from)
            let endBase = calendar.startOfDay(for: to)
            guard let end = calendar.date(byAdding: .day, value: 1, to: endBase) else {
                return nil
            }

            return SearchEngine.DateRange(start: start, end: end)
        }
    }
}

private struct CategoryPillButton: View {
    let category: ContentCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.caption)
                Text(category.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundColor(isSelected ? .white : .primary)
            .background(
                Capsule()
                    .fill(
                        isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.95), Color.yellow.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(.thinMaterial)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(isSelected ? 0.0 : 0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SpotResultRow: View {
    let item: ClipboardItemViewModel
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: item.category.iconName)
                    .font(.caption)
                    .foregroundColor(item.category.color)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayText)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Text(item.category.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(item.relativeTimeString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text("↩")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ToastView: View {
    let symbol: String
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)

            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

enum LaunchAtLoginHelper {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    return
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login toggle failed: \(error)")
        }
    }
}

struct SettingsView: View {
    @AppStorage("klippy.ui.textSize") private var textSize: Double = 16
    @AppStorage("klippy.feedback.hapticsEnabled") private var hapticsEnabled: Bool = true
    @State private var showClearConfirm = false
    @State private var launchAtLogin: Bool = LaunchAtLoginHelper.isEnabled

    var body: some View {
        VStack(spacing: 14) {
            // General
            settingsSection(title: "General", icon: "power") {
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at login")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.orange)
                .onChange(of: launchAtLogin) { newValue in
                    LaunchAtLoginHelper.setEnabled(newValue)
                    launchAtLogin = LaunchAtLoginHelper.isEnabled
                }
            }

            // Feedback
            settingsSection(title: "Feedback", icon: "hand.tap.fill") {
                Toggle(isOn: $hapticsEnabled) {
                    Text("Haptics")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.orange)
            }

            // Storage
            settingsSection(title: "Storage", icon: "internaldrive.fill") {
                settingsRow(label: "Saved items", value: "\(ClipboardManager.shared.totalItemCount)")
                settingsRow(label: "Limit", value: "Unlimited")
            }

            // Appearance
            settingsSection(title: "Appearance", icon: "textformat.size") {
                HStack {
                    Text("Text size")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(textSize)) pt")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                }

                Slider(value: $textSize, in: 13...24, step: 1)
                    .tint(.orange)

                HStack(spacing: 6) {
                    settingsButton("A-") { textSize = max(13, textSize - 1) }
                    settingsButton("A+") { textSize = min(24, textSize + 1) }
                    settingsButton("Reset") { textSize = 16 }
                }
            }

            // Actions
            HStack(spacing: 8) {
                Button {
                    ClipboardManager.shared.exportHistoryAsJSON()
                } label: {
                    Label("Export JSON", systemImage: "arrow.down.doc")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)

                Button {
                    showClearConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(16)
        .frame(width: 300)
        .alert("Clear All History?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                ClipboardManager.shared.clearAllItems()
            }
        } message: {
            Text("This will permanently delete all \(ClipboardManager.shared.totalItemCount) clipboard items. This cannot be undone.")
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        tint: Color = .orange,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(tint)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
    }

    private func settingsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }

    private func settingsButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
