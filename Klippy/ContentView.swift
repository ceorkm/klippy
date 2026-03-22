import SwiftUI
import CoreData
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var clipboardManager = ClipboardManager.shared
    @StateObject private var searchEngine = SearchEngine()

    @State private var searchText = ""
    @State private var selectedCategory: ContentCategory = .all
    @State private var selectedDateFilter: ItemDateFilter = .allTime
    @State private var showingCustomDateRangePicker = false
    @State private var customRangeStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customRangeEndDate = Date()
    @State private var showingSettings = false
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
                categoryStrip
                listCard(items: items)
                footerBar(resultCount: items.count)
            }
            .padding(10)

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
        .animation(.easeInOut(duration: 0.16), value: showingSpotPanel)
        .popover(isPresented: $showingSettings) {
            SettingsView()
                .frame(width: 340, height: 240)
        }
        .sheet(isPresented: $showingCustomDateRangePicker) {
            customDateRangeEditor
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

                TextField("Search clipboard history", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)

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
                            showToast("Copied to clipboard", symbol: "checkmark.circle.fill")
                        },
                        onDeleted: {
                            showToast("Item deleted", symbol: "trash")
                        },
                        onFavoriteToggled: { isNowFavorite in
                            showToast(isNowFavorite ? "Pinned item" : "Unpinned item", symbol: isNowFavorite ? "star.fill" : "star")
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

    private var filteredItems: [ClipboardItemViewModel] {
        let results = searchEngine.search(
            query: searchText,
            category: selectedCategory,
            dateRange: selectedDateRange,
            limit: 180
        )
        return prioritizeFavorites(in: applyDateRangeFilter(results))
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
                                showToast("Copied from Spot", symbol: "sparkles")
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

struct SettingsView: View {
    @AppStorage("klippy.ui.textSize") private var textSize: Double = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Storage")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text("Max items:")
                    Spacer()
                    Text("Unlimited")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Current items:")
                    Spacer()
                    Text("\(ClipboardManager.shared.totalItemCount)")
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text("Text size:")
                    Spacer()
                    Text("\(Int(textSize)) pt")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $textSize, in: 13...24, step: 1)

                HStack(spacing: 8) {
                    Button("A-") {
                        textSize = max(13, textSize - 1)
                    }
                    .buttonStyle(.bordered)

                    Button("A+") {
                        textSize = min(24, textSize + 1)
                    }
                    .buttonStyle(.bordered)

                    Button("Reset") {
                        textSize = 16
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button("Export JSON") {
                ClipboardManager.shared.exportHistoryAsJSON()
            }
            .buttonStyle(.bordered)

            Spacer()

            HStack {
                Spacer()
                Button("Clear All") {
                    ClipboardManager.shared.clearAllItems()
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
