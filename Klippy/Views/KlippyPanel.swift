import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Which slice of history the panel is showing.
enum PanelView: String, CaseIterable {
    case history = "History"
    case pinned = "Pinned"
    case saved = "Saved"
    case merged = "Merged"
}

/// A day's worth of clips, as the list renders them.
struct ClipDayGroup: Identifiable {
    let id: Date
    let label: String
    let date: String
    var items: [ClipboardItemViewModel]
}

struct KlippyPanel: View {
    @StateObject private var clipboardManager = ClipboardManager.shared
    @StateObject private var searchEngine = SearchEngine()
    @StateObject private var snippetManager = SnippetManager.shared
    @ObservedObject private var skinStore = SkinStore.shared
    @ObservedObject private var secretStore = SecretStore.shared

    @State private var searchText = ""
    @State private var category: ContentCategory = .all
    @State private var dateFilter: ItemDateFilter = .allTime
    @State private var panelView: PanelView = .history
    @State private var selection: Set<UUID> = []
    @State private var copiedID: UUID?
    /// Secrets the user has chosen to see. Cleared every time the panel opens, so
    /// revealing one never persists past the moment you needed it.
    @State private var revealedIDs: Set<UUID> = []
    @State private var toast: KlippyToast?
    @State private var previewItem: ClipboardItemViewModel?
    /// A merged clip opened to show the individual clips inside it.
    @State private var expandedMerge: ClipboardItemViewModel?
    @State private var isDropTargeted = false
    @State private var showingSettings = false
    @StateObject private var appLock = AppLock.shared
    @State private var showingDatePicker = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

    @FocusState private var searchFocused: Bool

    private var skin: Skin { skinStore.skin }

    var body: some View {
        panel
            .environment(\.managedObjectContext,
                         PersistenceController.shared.container.viewContext)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header

            if appLock.isLocked {
                lockScreen
            } else if showingSettings {
                PanelSettingsView(onDone: { showingSettings = false })
            } else {
                browser
            }
        }
        // The frame goes on the content, not around it, so every child is offered
        // the panel width. Putting it outside only clips the overflow.
        .frame(width: skinStore.panelWidth, height: 650, alignment: .top)
        .background(background)
        // Safe to round now: the panel is a borderless NSPanel we own, with a
        // genuinely clear window background, so nothing can show through the
        // antialiased corner the way the old MenuBarExtra window did.
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(skin.border, lineWidth: 1)
        )
        .overlay {
            if let previewItem {
                imagePreview(previewItem)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                toastView(toast)
                    .padding(.bottom, 58)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: toast)
        .environment(\.skin, skin)
        .environment(\.colorScheme, skin.isDark ? .dark : .light)
        .onReceive(NotificationCenter.default.publisher(
            for: PanelController.willShowNotification)) { _ in
            showingSettings = false
            showingDatePicker = false
            selection = []
            revealedIDs = []
            previewItem = nil
            appLock.refreshLockState()
            if appLock.isLocked {
                Task { await appLock.unlock() }
            }
            expandedMerge = nil
        }
        .background(TransparentHostWindow())
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if let image = skin.image {
            ZStack {
                // Explicit frame: an image inside .background() with only an
                // aspectRatio keeps its natural size and never fills the panel.
                Image(image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: skinStore.panelWidth, height: 650)
                    .clipped()
                LinearGradient(
                    colors: [Color(hex: 0x080C08).opacity(skin.scrimTop),
                             Color(hex: 0x080C08).opacity(skin.scrimBottom)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(width: skinStore.panelWidth, height: 650)
        } else {
            skin.bg ?? Color.black
        }
    }

    // MARK: - Header

    /// Shown in place of the history until the owner proves who they are.
    private var lockScreen: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "touchid")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(skin.hi)

            VStack(spacing: 6) {
                Text("Klippy is locked")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(skin.hi)
                Text(appLock.lastError ?? "Use Touch ID to see your clipboard history")
                    .font(.system(size: 13))
                    .foregroundStyle(skin.low)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await appLock.unlock() }
            } label: {
                Text("Unlock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(skin.ink)
                    .padding(.horizontal, 26)
                    .frame(height: 38)
                    .background(skin.accent,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(skin.chip)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "paperclip")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(skin.hi)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Klippy")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(skin.hi)
                Text("Clipboard manager")
                    .font(.system(size: 12))
                    .foregroundStyle(skin.low)
            }

            Spacer(minLength: 4)

            iconButton("pin", isOn: panelView == .pinned) { toggle(.pinned) }
            iconButton("bookmark", isOn: panelView == .saved) { toggle(.saved) }
            iconButton("point.topleft.down.curvedto.point.bottomright.up",
                       isOn: panelView == .merged) { toggle(.merged) }
            iconButton("slider.horizontal.3", isOn: showingSettings) {
                showingSettings.toggle()
                showingDatePicker = false
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private func iconButton(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(isOn ? skin.accent : skin.chip)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isOn ? skin.ink : skin.hi)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ view: PanelView) {
        panelView = panelView == view ? .history : view
        selection = []
        showingSettings = false
    }

    // MARK: - Browser

    private var browser: some View {
        VStack(spacing: 0) {
            if let expandedMerge {
                mergedContents(expandedMerge)
            } else {
                searchBar
                metaRow
                chipRow
                list
            }

            if !selection.isEmpty {
                selectionBar
            }
        }
        .overlay(alignment: .topTrailing) {
            if showingDatePicker {
                dateMenu
                    .padding(.top, 84)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(skin.low)

            TextField("Search clipboard history", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundStyle(skin.hi)
                .focused($searchFocused)
        }
        .padding(.horizontal, 13)
        .frame(height: 40)
        .background(skin.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(panelView.rawValue)
                    .foregroundStyle(skin.mid)
                Text(countLabel)
                    .foregroundStyle(skin.hi)
                    .monospacedDigit()
            }
            .font(.system(size: 13))

            Spacer(minLength: 4)

            Button {
                showingDatePicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("Date")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 13))
                .foregroundStyle(dateFilter == .allTime && !showingDatePicker ? skin.mid : skin.hi)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    /// Drawn as an overlay inside the panel rather than a system popover, which
    /// would bring its own light chrome along with it.
    private var dateMenu: some View {
        DateRangePopover(filter: $dateFilter,
                         customStart: $customStart,
                         customEnd: $customEnd,
                         onDismiss: { showingDatePicker = false })
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(skin.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, y: 18)
            .padding(.trailing, 18)
            .padding(.top, 4)
    }

    /// Scrolls sideways so the five chips from the design sit exactly where they
    /// did, while every other category the classifier produces stays reachable.
    /// The old UI exposed all of them and the rebuild dropped that.
    private var chipRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(Self.filterCategories, id: \.self) { item in
                    let isOn = item == category
                    Button {
                        category = item
                        selection = []
                    } label: {
                        Text(item.displayName)
                            .font(.system(size: 13.5, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? skin.ink : skin.hi)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(isOn ? skin.accent : skin.chip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.never)
        .scrollContentBackground(.hidden)
        .padding(.top, 13)
        .padding(.bottom, 14)
    }

    /// Design order first, then everything else the classifier can produce.
    ///
    /// No tab for `.instagramURL` or `.tiktokURL`: they are social links, and
    /// the Social tab already covers them. Before that they had no tab at all,
    /// so a TikTok link could only be found under All.
    private static let filterCategories: [ContentCategory] = [
        .all, .text, .url, .socialMedia, .image, .file,
        .color, .code, .email, .apiKey, .paymentCard,
        .json, .markdown, .number, .date, .phone,
        .address, .ipAddress, .identifier, .merged, .other
    ]

    // MARK: - List

    private var list: some View {
        ScrollView(.vertical) {
            // Sections, not a nested VStack. The outer stack was lazy over day
            // groups but each group built every one of its cards at once, so a
            // filter with thousands of clips in one day constructed thousands of
            // views on a single click. Inside a Section the rows stay lazy.
            LazyVStack(alignment: .leading, spacing: 8) {
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups) { group in
                        Section {
                            if category == .image {
                                thumbGrid(group.items)
                            } else {
                                ForEach(group.items) { item in
                                    card(item)
                                }
                            }
                        } header: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(group.label.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.1)
                                    .foregroundStyle(skin.mid)
                                Text(group.date)
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(skin.low)
                                Spacer(minLength: 0)
                            }
                            // Restores the 12pt gap between groups that the old
                            // 12-spacing stack gave, without padding the first.
                            .padding(.top, group.id == groups.first?.id ? 0 : 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.never)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(skin.accent.opacity(0.9),
                                  style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(8)
            }
        }
        .onDrop(of: Self.dropTypes, isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func thumbGrid(_ items: [ClipboardItemViewModel]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                           count: skinStore.isWide ? 3 : 2),
            spacing: 14
        ) {
            ForEach(items) { item in
                Button { activate(item) } label: {
                    ClipThumbView(item: item,
                                  isSelected: selection.contains(item.id),
                                  justCopied: copiedID == item.id)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(for: item) }
                .onDrag { dragProvider(for: item) }
            }
        }
    }

    private func card(_ item: ClipboardItemViewModel) -> some View {
        let isSecret = item.isSensitive || secretStore.contains(item.id)
        let masked = isSecret && !revealedIDs.contains(item.id)
        // A real Button rather than .onTapGesture: it hit-tests reliably next to
        // .onDrag, takes keyboard focus, and is what assistive tech expects.
        return Button {
            // First click on a secret only uncovers it. Copying takes a
            // second, deliberate click.
            if masked {
                revealedIDs.insert(item.id)
                return
            }
            // Opening shows what went into it. Copying is still on the
            // right-click menu, and now yields readable text.
            if item.isMergedClip, NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) {
                expandedMerge = item
                return
            }
            activate(item)
        } label: {
            ClipCardView(item: item,
                         isSelected: selection.contains(item.id),
                         justCopied: copiedID == item.id,
                         isMasked: masked)
        }
            .buttonStyle(.plain)
            .contextMenu { menu(for: item) }
            .onDrag { dragProvider(for: item) }
    }

    /// A saved snippet is a different object to a clip, so it gets its own
    /// actions. Renaming and deleting saved items were both lost in the rebuild.
    @ViewBuilder
    private func menu(for item: ClipboardItemViewModel) -> some View {
        Button("Copy") { copy(item) }

        if item.nsImage != nil {
            Button("Preview") { previewItem = item }
        }

        // Selecting used to be command-click and nothing else: a hidden gesture
        // with no affordance, no feedback when it failed, and no way to find it
        // if you had not been told. Merging several clips depends on it, so it
        // needs to exist somewhere you can actually see.
        Divider()
        Button(selection.contains(item.id) ? "Deselect" : "Select") {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
        }
        if !selection.isEmpty {
            Button("Clear selection") { selection = [] }
        }
        Divider()

        if panelView == .saved {
            Button("Rename…") { renameSnippet(id: item.id) }
            Divider()
            Button("Remove from Saved", role: .destructive) {
                snippetManager.deleteSnippet(id: item.id)
                searchEngine.clearCache()
                FeedbackManager.playDelete()
                showToast("Removed from Saved", symbol: "trash")
            }
        } else {
            Button(clipboardManager.isFavorite(itemId: item.id) ? "Unpin" : "Pin") {
                let nowPinned = clipboardManager.toggleFavorite(itemId: item.id)
                FeedbackManager.playPin()
                showToast(nowPinned ? "Pinned" : "Unpinned",
                          symbol: nowPinned ? "pin.fill" : "pin.slash")
            }
            // Only offered for clips the classifier did not already flag. A
            // detected key is secret by its nature, so a manual toggle there
            // would claim to unmask something that stays masked.
            if !item.isSensitive {
                Button(secretStore.contains(item.id) ? "Remove secret mark" : "Mark as secret") {
                    let nowSecret = secretStore.toggle(item.id)
                    revealedIDs.remove(item.id)
                    showToast(nowSecret ? "Marked as secret" : "Secret mark removed",
                              symbol: nowSecret ? "lock.fill" : "lock.open")
                }
            }
            Button("Save this clip") {
                let title = item.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
                snippetManager.createSnippet(title: String(title),
                                             content: item.content,
                                             isMerged: item.isMergedClip)
                FeedbackManager.playSave()
                showToast("Saved", symbol: "bookmark.fill")
            }
            Divider()
            Button("Delete", role: .destructive) {
                clipboardManager.deleteItem(itemId: item.id)
                searchEngine.clearCache()
                FeedbackManager.playDelete()
                showToast("Deleted", symbol: "trash")
            }
        }
    }

    /// A native alert rather than a sheet: the panel hides the moment it loses
    /// key focus, which would leave a SwiftUI sheet with no parent.
    private func renameSnippet(id: UUID) {
        guard let snippet = snippetManager.snippets.first(where: { $0.id == id }) else { return }

        let alert = NSAlert()
        alert.messageText = "Rename saved clip"
        alert.informativeText = String(snippet.content.prefix(120))
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = snippet.title
        field.placeholderString = "Name this clip"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            let newTitle = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newTitle.isEmpty else { return }
            snippetManager.updateSnippet(id: id, title: newTitle, content: snippet.content)
            showToast("Renamed", symbol: "pencil")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(emptyTitle)
                .font(.system(size: 15))
                .foregroundStyle(skin.mid)
            Text("Try another view or widen the date range")
                .font(.system(size: 13))
                .foregroundStyle(skin.low)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var emptyTitle: String {
        switch panelView {
        case .pinned: return "Nothing pinned yet"
        case .saved: return "Nothing saved yet"
        case .merged: return "No merged clips yet"
        case .history: return "No clips match"
        }
    }

    // MARK: - Footer

    private var selectionBar: some View {
        HStack(spacing: 8) {
            Button(action: mergeSelection) {
                Text(selection.count == 1 ? "Copy 1 clip" : "Merge \(selection.count) clips")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(skin.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(skin.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            secondaryButton("Pin") {
                let count = selection.count
                for id in selection { _ = clipboardManager.toggleFavorite(itemId: id) }
                selection = []
                FeedbackManager.playPin()
                showToast(count == 1 ? "Pinned" : "Pinned \(count) clips", symbol: "pin.fill")
            }
            if selectedImageCount > 0 {
                secondaryButton("Export \(selectedImageCount)") { exportSelectedImages() }
            }
            secondaryButton("Save") { saveSelection() }
            secondaryButton("Clear", quiet: true) { selection = [] }
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 17)
        .overlay(Rectangle().fill(skin.line).frame(height: 1), alignment: .top)
    }

    private func secondaryButton(_ title: String, quiet: Bool = false,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(quiet ? skin.mid : skin.hi)
                .padding(.horizontal, 15)
                .frame(height: 40)
                .background(skin.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drag out

    /// Lets a clip be dragged straight into another app. Images go as images,
    /// file clips as their file URLs, everything else as plain text.
    private func dragProvider(for item: ClipboardItemViewModel) -> NSItemProvider {
        if let image = item.nsImage {
            // A file, not raw image data. Editors and terminals ignore the
            // latter, which is why dragging a picture used to do nothing.
            return DragExport.provider(for: item.id, image: image, createdAt: item.createdAt)
        }

        let files = item.category == .file ? item.fileReferences : []
        if let first = files.first {
            return NSItemProvider(contentsOf: first.url) ?? NSItemProvider(object: item.content as NSString)
        }

        return NSItemProvider(object: item.content as NSString)
    }

    // MARK: - Drop

    private static let dropTypes: [UTType] = [.plainText, .utf8PlainText, .url, .fileURL, .png, .tiff]

    /// Dropped content is written to the pasteboard and picked up by the normal
    /// capture path, so a dragged item behaves exactly like something copied.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "klippy.drop.files")
        var fileURLs: [URL] = []

        // Images are gathered and stored in one go. Writing each to the general
        // pasteboard meant a drop of twenty pictures overwrote itself before the
        // capture loop could read them, so nearly all of them vanished.
        let imageGroup = DispatchGroup()
        let imageQueue = DispatchQueue(label: "klippy.drop.images")
        var droppedImages: [NSImage] = []

        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                imageGroup.enter()
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    defer { imageGroup.leave() }
                    guard let image = object as? NSImage else { return }
                    imageQueue.sync { droppedImages.append(image) }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    DispatchQueue.main.async {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                        showToast("Text added", symbol: "arrow.down.doc.fill")
                    }
                }
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let resolved: URL?
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        resolved = url
                    } else if let url = item as? URL {
                        resolved = url
                    } else if let string = item as? String {
                        resolved = URL(string: string)?.isFileURL == true
                            ? URL(string: string)
                            : URL(fileURLWithPath: (string as NSString).expandingTildeInPath)
                    } else {
                        resolved = nil
                    }
                    if let resolved { queue.sync { fileURLs.append(resolved) } }
                    group.leave()
                }
            }
        }

        imageGroup.notify(queue: .main) {
            let images = droppedImages
            guard !images.isEmpty else { return }
            Task { @MainActor in
                let saved = await clipboardManager.importImages(images)
                searchEngine.clearCache()
                guard saved > 0 else {
                    showToast("Already in history", symbol: "photo.fill")
                    return
                }
                showToast(saved == 1 ? "Image added" : "\(saved) images added",
                          symbol: "photo.fill")
            }
        }

        group.notify(queue: .main) {
            let urls = fileURLs.filter(\.isFileURL)
            guard !urls.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            _ = pasteboard.writeObjects(urls as [NSURL])
            showToast(urls.count == 1 ? "File added" : "\(urls.count) files added",
                      symbol: "folder.fill")
        }

        return handled
    }

    // MARK: - Merged contents

    /// The clips that went into a merged clip, each copyable on its own. The old
    /// UI had this and the rebuild dropped it, which made a merge look like it
    /// had swallowed everything.
    private func mergedContents(_ item: ClipboardItemViewModel) -> some View {
        let classifier = ContentClassifier()
        let parts = item.mergedComponents.map { content in
            ClipboardItemViewModel(
                id: UUID(),
                content: content,
                category: classifier.classify(content),
                createdAt: item.createdAt,
                lastAccessedAt: item.lastAccessedAt
            )
        }

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    expandedMerge = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(skin.hi)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Text("\(parts.count) clips merged")
                    .font(.system(size: 13))
                    .foregroundStyle(skin.mid)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(parts) { part in
                        Button { copy(part) } label: {
                            ClipCardView(item: part, isSelected: false,
                                         justCopied: copiedID == part.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                copy(item)
            } label: {
                Text("Copy all \(parts.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(skin.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(skin.accent,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 17)
        }
    }

    // MARK: - Image preview

    /// Full-size look at an image without copying it. Drawn inside the panel
    /// rather than in a separate window, because the panel hides as soon as it
    /// loses key focus and a detached preview would take that focus away.
    private func imagePreview(_ item: ClipboardItemViewModel) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.72))
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if let image = item.nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 10) {
                    Text(item.imageSizeString)
                        .monospacedDigit()
                    Text("Click anywhere to close")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.8))

                Button("Copy image") {
                    copy(item)
                    previewItem = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(skin.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(skin.accent, in: Capsule())
            }
            .padding(22)
        }
        .contentShape(Rectangle())
        .onTapGesture { previewItem = nil }
        .transition(.opacity)
    }

    // MARK: - Toast

    private func toastView(_ toast: KlippyToast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(skin.hi)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(skin.pop, in: Capsule())
        .overlay(Capsule().strokeBorder(skin.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    /// Brief confirmation for actions that otherwise leave no visible trace.
    /// Copy is deliberately excluded: the card already flashes "Copied" in place.
    private func showToast(_ message: String, symbol: String) {
        let entry = KlippyToast(message: message, symbol: symbol)
        toast = entry
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if toast == entry { toast = nil }
        }
    }

    // MARK: - Actions

    /// A click copies, unless a selection is already going, in which case it
    /// adds to it. Right-click and Select starts one; command or shift click
    /// also works.
    ///
    /// Selecting used to require holding command on every click. Miss it once
    /// and the click ran `copy`, which clears the selection, so picking a
    /// second clip silently threw the first one away and put the wrong thing on
    /// the clipboard. Selecting two clips to merge them was effectively
    /// impossible. Once anything is selected Klippy is in selection mode, the
    /// way Finder and Photos behave, and Clear or merging gets you out.
    private func activate(_ item: ClipboardItemViewModel) {
        let modifiers = NSEvent.modifierFlags
        let selecting = !selection.isEmpty
            || modifiers.contains(.command)
            || modifiers.contains(.shift)

        guard selecting else {
            copy(item)
            return
        }

        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    private func copy(_ item: ClipboardItemViewModel) {
        clipboardManager.copyToClipboard(item)
        // The "Play a sound on copy" setting was being written and never read.
        if UserDefaults.standard.bool(forKey: "klippy.ui.soundOnCopy") {
            FeedbackManager.playCopy()
        }
        selection = []
        copiedID = item.id
        let id = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if copiedID == id { copiedID = nil }
        }
    }

    private var selectedImageCount: Int {
        items.filter { selection.contains($0.id) && $0.nsImage != nil }.count
    }

    /// Writes every selected picture into a folder of your choosing.
    ///
    /// Dragging is one item at a time, which is no help when you want fifty
    /// pictures out at once. The folder is picked through the open panel, so
    /// this keeps working under the App Store sandbox without asking for any
    /// broader access to the disk.
    private func exportSelectedImages() {
        let chosen = items.filter { selection.contains($0.id) && $0.nsImage != nil }
        guard !chosen.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = chosen.count == 1
            ? "Choose where to save the image"
            : "Choose where to save \(chosen.count) images"

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var written = 0
        for item in chosen {
            guard let image = item.nsImage,
                  let source = DragExport.imageFile(for: item.id,
                                                    image: image,
                                                    createdAt: item.createdAt) else { continue }
            var destination = folder.appendingPathComponent(source.lastPathComponent)
            var attempt = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                let stem = source.deletingPathExtension().lastPathComponent
                destination = folder.appendingPathComponent("\(stem)-\(attempt).png")
                attempt += 1
            }
            if (try? FileManager.default.copyItem(at: source, to: destination)) != nil {
                written += 1
            }
        }

        selection = []
        showToast(written == 1 ? "Exported 1 image" : "Exported \(written) images",
                  symbol: "square.and.arrow.down")
    }

    /// Copies the selection into the snippet store, which is what Saved reads.
    private func saveSelection() {
        for item in items where selection.contains(item.id) {
            let title = item.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(60)
            snippetManager.createSnippet(title: String(title),
                                         content: item.content,
                                         isMerged: item.isMergedClip)
        }
        let count = selection.count
        selection = []
        searchEngine.clearCache()
        FeedbackManager.playSave()
        showToast(count == 1 ? "Saved" : "Saved \(count) clips", symbol: "bookmark.fill")
    }

    private func mergeSelection() {
        let chosen = items.filter { selection.contains($0.id) }
        guard let first = chosen.first else { return }
        if chosen.count == 1 {
            copy(first)
            return
        }

        let components = chosen.flatMap { item -> [String] in
            item.isMergedClip ? item.mergedComponents : [item.content]
        }
        guard let merged = clipboardManager.createMergedClip(components: components) else {
            showToast("Merge needs at least two clips", symbol: "exclamationmark.triangle")
            return
        }

        clipboardManager.copyToClipboard(merged)
        // Search results are cached for 30s, so without this the clip that was
        // just created is missing from the list and the merge looks like it did
        // nothing at all.
        searchEngine.clearCache()
        // Show the result instead of leaving the user on History wondering.
        panelView = .merged
        selection = []
        FeedbackManager.playMerge()
        showToast("Merged \(chosen.count) clips", symbol: "arrow.triangle.merge")
    }

    // MARK: - Data

    private var countLabel: String {
        Self.grouped(panelView == .history ? clipboardManager.totalItemCount : items.count)
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var items: [ClipboardItemViewModel] {
        let range = dateFilter.makeRange(customStartDate: customStart, customEndDate: customEnd)
        let results = searchEngine.search(
            query: searchText,
            category: category,
            dateRange: range,
            limit: 5000
        )

        switch panelView {
        case .history:
            return results

        case .pinned:
            // Pins live in ClipboardManager's favourites. Fetched directly so a
            // pinned clip stays reachable even when it falls outside the current
            // search or date window.
            return clipboardManager.fetchAllPinnedItems().filter(matchesFilters)

        case .merged:
            // Fetched directly, not filtered from search results, which only
            // cover the newest 5000 clips and hid every older merged clip.
            return clipboardManager.fetchAllMergedItems().filter(matchesFilters)

        case .saved:
            // Saved is a different store entirely: snippets the user chose to
            // keep, in the SavedSnippet entity, not pinned clips.
            return snippetManager.snippets
                .map(Self.displayItem(for:))
                .filter(matchesFilters)
        }
    }

    /// Applies the search box, chip and date filters to rows that didn't come
    /// out of the search engine.
    private func matchesFilters(_ item: ClipboardItemViewModel) -> Bool {
        // Same grouping as search: the Social tab covers the three social
        // link kinds, which have no tab of their own.
        if category != .all && !item.category.matches(category) { return false }

        if let range = dateFilter.makeRange(customStartDate: customStart, customEndDate: customEnd) {
            if item.createdAt < range.start || item.createdAt >= range.end { return false }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return item.content.lowercased().contains(query)
    }

    /// Renders a saved snippet through the same card as everything else.
    private static func displayItem(for snippet: SavedSnippetViewModel) -> ClipboardItemViewModel {
        ClipboardItemViewModel(
            id: snippet.id,
            content: snippet.content,
            category: snippet.isMerged ? .merged : .text,
            createdAt: snippet.createdAt,
            lastAccessedAt: snippet.updatedAt
        )
    }

    private var groups: [ClipDayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [ClipboardItemViewModel]] = [:]

        for item in items {
            let day = calendar.startOfDay(for: item.createdAt)
            if buckets[day] == nil {
                buckets[day] = []
                order.append(day)
            }
            buckets[day]?.append(item)
        }

        return order.map { day in
            ClipDayGroup(id: day,
                         label: Self.dayLabel(day, calendar: calendar),
                         date: Self.fullDate.string(from: day),
                         items: buckets[day] ?? [])
        }
    }

    private static func dayLabel(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return weekday.string(from: day)
    }

    private static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

/// The menu bar window ships with its own opaque backdrop. Left alone it shows as
/// a pale ring around the panel's rounded corners, because the clip's antialiased
/// edge lets whatever sits behind it bleed through. Clearing the window, its
/// content layers and every visual-effect view underneath leaves only the panel.
private struct TransparentHostWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.strip(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.strip(nsView.window) }
    }

    private static func strip(_ window: NSWindow?) {
        guard let window else { return }
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        guard let root = window.contentView?.superview ?? window.contentView else { return }
        clear(root)
    }

    /// Walks the whole hierarchy: SwiftUI nests its backdrop several levels deep
    /// and rebuilds it, so one pass over the top level isn't enough.
    private static func clear(_ view: NSView) {
        if let effect = view as? NSVisualEffectView {
            effect.isHidden = true
            effect.alphaValue = 0
        }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.subviews.forEach(clear)
    }
}

/// A short confirmation shown at the bottom of the panel.
struct KlippyToast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let symbol: String
}
