import SwiftUI
import AppKit
import ServiceManagement
import Carbon.HIToolbox

struct PanelSettingsView: View {
    let onDone: () -> Void

    @ObservedObject private var skinStore = SkinStore.shared
    @ObservedObject private var shortcuts = ShortcutStore.shared

    @State private var recording: ShortcutStore.Action?
    @State private var keyMonitor: Any?
    @Environment(\.skin) private var skin

    @State private var launchAtLogin = LaunchAtLoginHelper.isEnabled
    @AppStorage(ClipboardPrivacy.ignoreConcealedKey) private var ignoreConcealed = true
    @AppStorage("klippy.feedback.hapticsEnabled") private var haptics = true
    @State private var importing = false
    @StateObject private var appLock = AppLock.shared
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage("klippy.ui.soundOnCopy") private var soundOnCopy = false
    @AppStorage(LinkPreviewStore.enabledKey) private var linkPreviews = true
    @AppStorage("klippy.ui.textSize") private var textSize: Double = 13.5
    // Off by default. This deletes data, so it only ever runs if asked for.
    @AppStorage(ClipboardManager.autoDeleteDaysKey) private var autoDeleteDays: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    section("Skin") { skinGrid }
                    section("Panel width") { widthSegment }
                    section("Text size") { textSizeSegment }
                    section("General") { generalToggles }
                    section("Lock") { lockControls }
                    section("Shortcuts") { shortcutTable }
                    section("Auto-delete") { autoDeleteControl }
                    section("Data") { dataActions }
                    privacyCard
                    storageCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)

            HStack {
                Text("Klippy \(Self.version) · free & open source")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(skin.hi)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(skin.low)
            .padding(.horizontal, 18)
            .padding(.top, 13)
            .padding(.bottom, 17)
        }
        // A recorder left running keeps a local key monitor that swallows every
        // keystroke in the app, so closing the panel mid-recording used to kill
        // typing in the search field until relaunch.
        .onDisappear { stopRecording() }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(skin.mid)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Skin

    private var skinGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                           count: skinStore.isWide ? 5 : 3),
            spacing: 10
        ) {
            ForEach(Skin.all) { option in
                Button {
                    skinStore.select(option)
                } label: {
                    VStack(spacing: 7) {
                        swatch(for: option)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            // A .fill image with only a height set renders far
                            // taller than its slot; without clipping, the
                            // overflow spills over neighbouring swatches.
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(option.id == skin.id ? skin.accent : skin.border,
                                                  lineWidth: option.id == skin.id ? 2 : 1)
                            )
                        Text(option.label)
                            .font(.system(size: 12))
                            .foregroundStyle(option.id == skin.id ? skin.hi : skin.mid)
                    }
                    // The whole cell is the target, label included, not just the
                    // image. A real click also drifts a pixel or two, which a
                    // ScrollView can swallow as the start of a scroll, so the
                    // bigger and more forgiving this area is, the better.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func swatch(for option: Skin) -> some View {
        if let image = option.image {
            Image(image).resizable().aspectRatio(contentMode: .fill)
        } else {
            option.bg ?? Color.black
        }
    }

    // MARK: - Width

    private var widthSegment: some View {
        HStack(spacing: 4) {
            segmentButton("Compact · 430", isOn: !skinStore.isWide) { skinStore.isWide = false }
            segmentButton("Wide · 640", isOn: skinStore.isWide) { skinStore.isWide = true }
        }
        .padding(4)
        .background(skin.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func segmentButton(_ title: String, isOn: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? skin.ink : skin.mid)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isOn ? skin.accent : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Text size

    private var textSizeSegment: some View {
        HStack(spacing: 4) {
            segmentButton("Small", isOn: textSize < 13) { textSize = 12 }
            segmentButton("Medium", isOn: textSize >= 13 && textSize < 15) { textSize = 13.5 }
            segmentButton("Large", isOn: textSize >= 15) { textSize = 15.5 }
        }
        .padding(4)
        .background(skin.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Lock

    /// Touch ID in front of the history.
    ///
    /// The timeout matters as much as the switch: asking on every open would
    /// put a fingerprint between the user and a paste dozens of times a day,
    /// and a feature that annoying gets switched off rather than used.
    private var lockControls: some View {
        VStack(spacing: 0) {
            toggleRow("Require Touch ID",
                      AppLock.availability ?? "Ask before showing your history",
                      isOn: $lockEnabled, isLast: !lockEnabled)
                .disabled(AppLock.availability != nil)
                .opacity(AppLock.availability == nil ? 1 : 0.5)
                .onChange(of: lockEnabled) { enabled in
                    appLock.setEnabled(enabled)
                }

            if lockEnabled {
                Divider().overlay(skin.line)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ask again after")
                            .font(.system(size: 14))
                            .foregroundStyle(skin.hi)
                        Text("How long an unlock lasts")
                            .font(.system(size: 12))
                            .foregroundStyle(skin.low)
                    }
                    Spacer(minLength: 8)
                    Picker("", selection: Binding(
                        get: { appLock.timeoutMinutes },
                        set: { appLock.timeoutMinutes = $0 }
                    )) {
                        ForEach(AppLock.timeoutChoices, id: \.self) { minutes in
                            Text(Self.timeoutLabel(minutes)).tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().overlay(skin.line)
                actionRow("Lock now", "Ask for Touch ID next time", isLast: true) {
                    appLock.lockNow()
                }
            }
        }
        .background(skin.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static func timeoutLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Every time"
        case 1: return "1 minute"
        case 60: return "1 hour"
        default: return "\(minutes) minutes"
        }
    }

    // MARK: - Toggles

    private var generalToggles: some View {
        VStack(spacing: 0) {
            toggleRow("Launch at login", "Klippy starts with your Mac",
                      isOn: $launchAtLogin, isLast: false)
                .onChange(of: launchAtLogin) { newValue in
                    LaunchAtLoginHelper.setEnabled(newValue)
                    launchAtLogin = LaunchAtLoginHelper.isEnabled
                }
            toggleRow("Ignore password managers", "1Password, Bitwarden, Keychain",
                      isOn: $ignoreConcealed, isLast: false)
            toggleRow("Play a sound on copy", "Quiet click when a clip lands",
                      isOn: $soundOnCopy, isLast: false)
            // FeedbackManager has always read this key. Its only switch used to
            // live in the old window, so the setting was unreachable once the
            // panel replaced it.
            toggleRow("Haptic feedback", "A small tap on trackpads that support it",
                      isOn: $haptics, isLast: false)
            toggleRow("Load link previews", "Asks a copied site for its preview image",
                      isOn: $linkPreviews, isLast: true)
                .onChange(of: linkPreviews) { enabled in
                    guard !enabled else { return }
                    Task { await LinkPreviewStore.shared.clearCache() }
                }
        }
        .background(skin.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// A settings switch. The whole row is the target, not just the switch.
    ///
    /// This used to be a bare HStack with no gesture on it at all. `SkinSwitch`
    /// is only shapes, so replacing the system `Toggle` (which was painting
    /// itself the asset-catalog orange instead of the skin colour) took the
    /// interaction away with it, and every switch in Settings became a picture
    /// of a switch. Wrapping the row in a button is what makes it a control.
    private func toggleRow(_ title: String, _ subtitle: String,
                           isOn: Binding<Bool>, isLast: Bool) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            FeedbackManager.playPin()
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(skin.hi)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(skin.low)
                }
                Spacer(minLength: 8)
                SkinSwitch(isOn: isOn.wrappedValue)
            }
            .padding(14)
            // Without this the gaps between the labels and the switch are not
            // part of the button, so most of the row stays dead.
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(skin.line).frame(height: 1).padding(.leading, 14)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shortcuts

    private var shortcutTable: some View {
        VStack(spacing: 0) {
            // These two are rebindable. The rows used to be fixed labels, and
            // one of them named a shortcut that was never implemented.
            editableShortcutRow(.openPanel, isLast: false)
            editableShortcutRow(.stepBack, isLast: false)
            shortcutRow("Recall recent clip", "⌃⌘1–0", isLast: true)
        }
        .background(skin.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func editableShortcutRow(_ action: ShortcutStore.Action, isLast: Bool) -> some View {
        let isRecording = recording == action
        return HStack(spacing: 10) {
            Text(action.title)
                .font(.system(size: 14))
                .foregroundStyle(skin.hi)
            Spacer(minLength: 8)

            if shortcuts.binding(for: action) != action.fallback {
                Button("Reset") { shortcuts.reset(action) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(skin.low)
            }

            Button {
                isRecording ? stopRecording() : startRecording(action)
            } label: {
                Text(isRecording ? "Press keys…" : shortcuts.binding(for: action).display)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(isRecording ? skin.ink : skin.hi)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isRecording ? skin.accent : skin.chip,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(skin.line).frame(height: 1).padding(.leading, 14)
            }
        }
    }

    private func shortcutRow(_ title: String, _ keys: String, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(skin.hi)
            Spacer(minLength: 8)
            Text(keys)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(skin.mid)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(skin.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(skin.line).frame(height: 1).padding(.leading, 14)
            }
        }
    }

    /// Captures the next modified key press. Escape cancels, and a press with no
    /// modifier is rejected, because an unmodified global hotkey would swallow
    /// that key everywhere on the system.
    private func startRecording(_ action: ShortcutStore.Action) {
        stopRecording()
        recording = action
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            if let binding = ShortcutBinding(event: event) {
                shortcuts.set(binding, for: action)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recording = nil
    }

    // MARK: - Auto-delete

    private var autoDeleteControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                autoDeleteButton("Never", days: 0)
                autoDeleteButton("30 days", days: 30)
                autoDeleteButton("90 days", days: 90)
                autoDeleteButton("1 year", days: 365)
            }
            .padding(4)
            .background(skin.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Removes clips you never copied again. Pinned, saved and secret clips are always kept.")
                .font(.system(size: 11.5))
                .foregroundStyle(skin.low)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func autoDeleteButton(_ title: String, days: Int) -> some View {
        Button {
            guard days > 0 else {
                autoDeleteDays = 0
                return
            }
            confirmAutoDelete(days: days)
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: autoDeleteDays == days ? .semibold : .regular))
                .foregroundStyle(autoDeleteDays == days ? skin.ink : skin.mid)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(autoDeleteDays == days ? skin.accent : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    /// Shows the real number of clips a window would remove before enabling it.
    /// On a large history this can be tens of thousands, so it is never silent.
    private func confirmAutoDelete(days: Int) {
        ClipboardManager.shared.countUnusedClips(olderThanDays: days) { count in
            guard count > 0 else {
                autoDeleteDays = days
                return
            }

            let alert = NSAlert()
            alert.messageText = "Delete \(count) unused clips?"
            alert.informativeText = "These were copied more than \(days) days ago and never used again. Pinned, saved and secret clips are kept. This runs now and at every launch until you set it back to Never."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete \(count)")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                autoDeleteDays = days
                ClipboardManager.shared.pruneUnusedClips(olderThanDays: days)
            }
        }
    }

    // MARK: - Data

    private var dataActions: some View {
        VStack(spacing: 0) {
            actionRow("Export history",
                      "A plain JSON file, secrets included",
                      isLast: false) {
                confirmExport()
            }
            actionRow(importing ? "Importing…" : "Import an older history",
                      "Merge a DataModel.sqlite from a previous install",
                      isLast: false) {
                guard !importing else { return }
                importOlderHistory()
            }
            actionRow("Delete all history",
                      "Clips and pins. Saved clips are kept.",
                      isLast: true,
                      destructive: true) {
                confirmDeleteAll()
            }
        }
        .background(skin.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Lets the user hand over a database from an earlier install.
    ///
    /// Sandboxing moves Klippy's storage into a container, so a history from a
    /// build that ran unsandboxed is no longer somewhere the app may read. The
    /// user choosing the file is what grants access, which is why this is a
    /// picker rather than something automatic.
    private func importOlderHistory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.prompt = "Import"
        panel.message = "Choose the DataModel.sqlite from your previous Klippy install"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Klippy", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        importing = true
        Task { @MainActor in
            let result = await ClipboardManager.shared.importHistory(from: url)
            importing = false

            let alert = NSAlert()
            alert.alertStyle = .informational
            if result.added == 0 && result.skipped == 0 {
                alert.messageText = "Nothing imported"
                alert.informativeText = "That file could not be read as a Klippy history."
            } else {
                alert.messageText = result.added == 1
                    ? "Imported 1 clip"
                    : "Imported \(result.added) clips"
                alert.informativeText = result.skipped > 0
                    ? "\(result.skipped) were duplicates and were skipped."
                    : "Your older history has been merged in."
            }
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Export writes everything, so the user is told before it happens.
    ///
    /// API keys, card numbers and clips marked secret are hidden in the list
    /// but plain text in the file. Deleting everything asks first; handing the
    /// same content to a file on disk deserves the same courtesy.
    private func confirmExport() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export your whole history?"
        alert.informativeText = """
        The file is plain JSON and is not encrypted. Anything hidden in the \
        list, including API keys, card numbers and clips you marked secret, \
        is written out readable.
        """
        alert.addButton(withTitle: "Export")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ClipboardManager.shared.exportHistoryAsJSON()
    }

    private func actionRow(_ title: String, _ subtitle: String,
                           isLast: Bool, destructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(destructive ? Color.red : skin.hi)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(skin.low)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(skin.low)
            }
            .contentShape(Rectangle())
            .padding(14)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(skin.line).frame(height: 1).padding(.leading, 14)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// An NSAlert rather than a SwiftUI dialog: the panel hides as soon as it
    /// loses key focus, which would orphan an attached sheet. This is the only
    /// irreversible action in the app, so it always asks first.
    private func confirmDeleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all clipboard history?"
        alert.informativeText = "Every clip is removed, including pinned ones. Saved clips are kept. This cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete Everything")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            ClipboardManager.shared.clearAllItems()
        }
    }

    // MARK: - Storage

    /// App Store submission requires a reachable privacy policy, and a policy
    /// nobody can find from inside the app is not much of a promise.
    private var privacyCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy policy")
                    .font(.system(size: 14))
                    .foregroundStyle(skin.hi)
                Text("What Klippy stores and what it never sends")
                    .font(.system(size: 12))
                    .foregroundStyle(skin.low)
            }
            Spacer(minLength: 8)
            Button("Read") {
                if let url = URL(string: "https://github.com/ceorkm/klippy/blob/main/PRIVACY.md") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(skin.hi)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(skin.chip, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(14)
        .background(skin.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var storageCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Everything stays on this Mac")
                    .font(.system(size: 14))
                    .foregroundStyle(skin.hi)
                Text(Self.storageDisplayPath)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(skin.low)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([Self.storageURL])
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(skin.hi)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(skin.chip, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(14)
        .background(skin.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static let storageURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Klippy", isDirectory: true)
    }()

    private static var storageDisplayPath: String {
        storageURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// The mockup's switch: track takes the skin accent when on, knob takes the ink
/// colour. Drawn here rather than using `Toggle(.switch)`, which follows the app's
/// asset-catalog accent and so ignores the active skin entirely.
private struct SkinSwitch: View {
    let isOn: Bool

    @Environment(\.skin) private var skin

    var body: some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(isOn ? skin.accent : skin.tile)
            .frame(width: 44, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? skin.ink : skin.card)
                    .frame(width: 21, height: 21)
                    .padding(.horizontal, 2.5)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
