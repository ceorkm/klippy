import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Owns the status item and the panel window.
///
/// `MenuBarExtra` places its window relative to its status item, so when macOS
/// collapses menu bar extras behind the overflow the panel ends up off every
/// display and the app looks like it has vanished. Owning the window means it
/// always opens somewhere visible, and a global hotkey works even when the icon
/// is hidden entirely.
final class PanelController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = PanelController()

    private var statusItem: NSStatusItem?
    private var panel: KlippyFloatingPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var slotHotKeyRefs: [EventHotKeyRef?] = []
    private var sequentialHotKeyRef: EventHotKeyRef?
    private var sequentialIndex = 0
    private var sequentialResetWork: DispatchWorkItem?

    /// Non-zero while Klippy itself is showing something that takes key focus:
    /// an open/save panel, an alert, the Touch ID prompt. Without this
    /// `windowDidResignKey` hides the panel the instant any of them appear, so
    /// the app vanishes mid-action and the result never gets seen.
    private var modalDepth = 0

    /// When the panel last went away. Clicking the status item resigns key,
    /// which runs `hide()` before the button's action fires, so without this the
    /// icon could never close the panel: it would hide, then immediately reopen.
    private var lastHiddenAt: Date?

    private override init() { super.init() }

    func install() {

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "doc.on.clipboard",
                       accessibilityDescription: "Klippy")
        item.button?.image?.accessibilityDescription = "Klippy"
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        registerHotKey()
    }

    // MARK: - Showing

    /// Right-click (or control-click) opens the menu, anything else toggles.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            toggle()
        }
    }

    @objc func toggle() {
        if panel?.isVisible == true {
            hide()
            return
        }
        // Resigning key already hid it a moment ago, as part of this same click.
        if let lastHiddenAt, Date().timeIntervalSince(lastHiddenAt) < 0.25 { return }
        show()
    }

    /// Klippy is an `LSUIElement` app: no Dock icon and no menu bar of its own.
    /// The rebuild dropped the old window's Quit button with the window, which
    /// left no way to quit at all short of Activity Monitor.
    private func showStatusMenu() {
        let menu = NSMenu()

        let open = menu.addItem(withTitle: "Open Klippy",
                                action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self

        let settings = menu.addItem(withTitle: "Settings…",
                                    action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self

        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Quit Klippy",
                                action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self

        // Attaching the menu makes the next click open it; detaching again
        // afterwards keeps the plain left click a toggle rather than a menu.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openFromMenu() { show() }

    @objc private func openSettingsFromMenu() {
        show()
        NotificationCenter.default.post(name: Self.openSettingsNotification, object: nil)
    }

    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    /// Asks the panel to open straight on Settings.
    static let openSettingsNotification = Notification.Name("klippy.panel.openSettings")

    // MARK: - Modal sessions

    /// Runs `work` with the auto-hide guard raised, then puts focus back on the
    /// panel so it is still there when the dialog closes.
    @discardableResult
    static func withModalSession<T>(_ work: () -> T) -> T {
        shared.modalDepth += 1
        defer { shared.endModalSession() }
        return work()
    }

    /// Main actor on purpose. Without it, this hops to Swift's background pool
    /// on the first await, and the `defer` then calls `makeKeyAndOrderFront`
    /// from that thread: AppKit throws and the process aborts. That is what
    /// closed the app the moment Touch ID was turned on.
    @MainActor
    static func withModalSession<T>(_ work: () async throws -> T) async rethrows -> T {
        shared.modalDepth += 1
        defer { shared.endModalSession() }
        return try await work()
    }

    private func endModalSession() {
        // Belt and braces for the crash above: whatever thread a caller ends
        // up on, the window is only ever touched from the main one.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.endModalSession() }
            return
        }
        modalDepth = max(0, modalDepth - 1)
        guard modalDepth == 0, let panel, panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Posted just before the panel appears so the UI can return to its default
    /// state instead of reopening on whatever screen was last left open.
    static let willShowNotification = Notification.Name("klippy.panel.willShow")

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        NotificationCenter.default.post(name: Self.willShowNotification, object: nil)

        // The retention setting has to keep applying on a machine that never
        // restarts. This is a no-op unless a day has passed and the user chose
        // a window.
        ClipboardManager.shared.runAutoDeleteIfDue()

        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 430, height: 650))
        panel.setFrameTopLeftPoint(anchorPoint(for: panel))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        lastHiddenAt = Date()
        panel?.orderOut(nil)
    }

    /// Re-sizes an open panel, for the Compact / Wide switch. The size was only
    /// ever set in `show()`, so changing it while the panel was up laid the
    /// content out at the new width inside a window still at the old one.
    func resizeToFit() {
        guard let panel, panel.isVisible else { return }
        panel.setContentSize(NSSize(width: SkinStore.shared.panelWidth, height: 650))
        panel.setFrameTopLeftPoint(anchorPoint(for: panel))
    }

    private func makePanel() -> KlippyFloatingPanel {
        let hosting = NSHostingView(rootView: KlippyPanel())
        let panel = KlippyFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 650),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.delegate = self

        // The rounded corners live in SwiftUI, so the window itself must be
        // fully transparent or its square backing shows behind them.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        return panel
    }

    /// Under the status item when it's visible, otherwise tucked below the
    /// top-right of the active screen so it is never off-screen.
    private func anchorPoint(for panel: NSPanel) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 8

        if let button = statusItem?.button,
           let window = button.window,
           window.screen != nil {
            let inScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
            var x = inScreen.midX - panel.frame.width / 2
            x = min(max(x, visible.minX + margin), visible.maxX - panel.frame.width - margin)
            let y = inScreen.minY - margin
            if visible.contains(NSPoint(x: x + panel.frame.width / 2, y: y - 1)) {
                return NSPoint(x: x, y: y)
            }
        }

        return NSPoint(x: visible.maxX - panel.frame.width - margin, y: visible.maxY - margin)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard modalDepth == 0 else { return }
        hide()
    }

    // MARK: - Global hotkey

    /// Control-Command-V, the shortcut the design promises. Registered through
    /// Carbon because that path needs no Accessibility permission.
    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == PanelController.hotKeySignature {
                DispatchQueue.main.async { PanelController.shared.toggle() }
            } else if hotKeyID.id == PanelController.sequentialHotKeySignature {
                Task { @MainActor in PanelController.shared.stepBackThroughHistory() }
            } else if hotKeyID.id >= PanelController.slotHotKeyBase {
                let slot = Int(hotKeyID.id - PanelController.slotHotKeyBase)
                Task { @MainActor in PanelController.shared.recallSlot(slot) }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        registerConfigurableHotKeys()
        registerSlotHotKeys()
    }

    /// Shortcuts macOS refused to give Klippy, because something else already
    /// holds them. Registration failing used to be silent: Settings showed the
    /// keys you picked and pressing them did nothing at all.
    @Published private(set) var unavailableShortcuts: Set<ShortcutStore.Action> = []

    /// Registers the two rebindable shortcuts from whatever the user has chosen.
    private func registerConfigurableHotKeys() {
        let store = ShortcutStore.shared
        var refused: Set<ShortcutStore.Action> = []

        let open = store.binding(for: .openPanel)
        let openID = EventHotKeyID(signature: OSType(0x4B4C5059), id: Self.hotKeySignature)
        if RegisterEventHotKey(open.keyCode, open.carbonModifiers, openID,
                               GetApplicationEventTarget(), 0, &hotKeyRef) != noErr {
            refused.insert(.openPanel)
        }

        let step = store.binding(for: .stepBack)
        let stepID = EventHotKeyID(signature: OSType(0x4B4C5059), id: Self.sequentialHotKeySignature)
        if RegisterEventHotKey(step.keyCode, step.carbonModifiers, stepID,
                               GetApplicationEventTarget(), 0, &sequentialHotKeyRef) != noErr {
            refused.insert(.stepBack)
        }

        unavailableShortcuts = refused
    }

    /// Called after a shortcut is reassigned so the new keys take effect at once.
    func reloadHotKeys() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let sequentialHotKeyRef { UnregisterEventHotKey(sequentialHotKeyRef) }
        hotKeyRef = nil
        sequentialHotKeyRef = nil
        registerConfigurableHotKeys()
    }

    /// Control-Command-Down walks back through history one clip per press.
    /// The position resets after a short pause, so the next run starts fresh
    /// rather than continuing from wherever the last one stopped.
    @MainActor
    func stepBackThroughHistory() {
        guard !blockedByLock() else { return }
        let items = ClipboardManager.shared.recentItems
        guard !items.isEmpty else { return }

        // Starts at 1, not 0. Slot 0 is the newest clip, which is the one
        // already on the clipboard, so the first press used to re-copy what you
        // had and look like it had done nothing.
        sequentialIndex = min(sequentialIndex + 1, items.count - 1)
        recallSlot(sequentialIndex)

        sequentialResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sequentialIndex = 0 }
        sequentialResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Control-Command-1 through 0 put the first ten clips back on the clipboard
    /// without opening anything.
    private func registerSlotHotKeys() {
        let keyCodes: [Int] = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0
        ]

        for (index, code) in keyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4B4C5059),
                                   id: Self.slotHotKeyBase + UInt32(index))
            RegisterEventHotKey(UInt32(code),
                                UInt32(controlKey | cmdKey),
                                id,
                                GetApplicationEventTarget(),
                                0,
                                &ref)
            slotHotKeyRefs.append(ref)
        }
    }

    /// Puts slot N back on the clipboard, and stops there.
    ///
    /// It used to follow up by synthesising Command-V so the clip landed
    /// straight in whatever you were typing. That needs Accessibility, and
    /// Apple rejects App Store apps for using Accessibility to drive other
    /// apps rather than to assist someone: a clipboard manager doing exactly
    /// this was turned down twice under guideline 2.4.5. Copy is the whole job
    /// here; the user presses Command-V.
    @MainActor
    func recallSlot(_ index: Int) {
        guard !blockedByLock() else { return }
        let items = ClipboardManager.shared.recentItems
        guard index >= 0, index < items.count else { return }
        ClipboardManager.shared.copyToClipboard(items[index])
    }

    /// The lock covered the panel and nothing else. With Require Touch ID on,
    /// Control-Command-1 still put the newest clip on the clipboard for anyone
    /// at the keyboard, card numbers included, and Control-Command-Down walked
    /// the whole recent list. Behind the lock a hotkey opens the panel instead,
    /// which asks for the fingerprint.
    @MainActor
    private func blockedByLock() -> Bool {
        guard AppLock.isEnabled else { return false }
        AppLock.shared.refreshLockState()
        guard AppLock.shared.isLocked else { return false }
        show()
        return true
    }

    private static let hotKeySignature: UInt32 = 1
    private static let slotHotKeyBase: UInt32 = 100
    private static let sequentialHotKeySignature: UInt32 = 2
}

/// Borderless panel that can still take keyboard focus, so the search field works.
final class KlippyFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
