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
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    private var statusItem: NSStatusItem?
    private var panel: KlippyFloatingPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var slotHotKeyRefs: [EventHotKeyRef?] = []
    private var sequentialHotKeyRef: EventHotKeyRef?
    private var sequentialIndex = -1
    private var sequentialResetWork: DispatchWorkItem?

    private override init() { super.init() }

    func install() {

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "doc.on.clipboard",
                       accessibilityDescription: "Klippy")
        item.button?.image?.accessibilityDescription = "Klippy"
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item

        registerHotKey()
    }

    // MARK: - Showing

    @objc func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    /// Posted just before the panel appears so the UI can return to its default
    /// state instead of reopening on whatever screen was last left open.
    static let willShowNotification = Notification.Name("klippy.panel.willShow")

    /// Posted when the panel goes away, so animated skins can stop decoding.
    static let didHideNotification = Notification.Name("klippy.panel.didHide")

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        NotificationCenter.default.post(name: Self.willShowNotification, object: nil)

        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 430, height: 650))
        panel.setFrameTopLeftPoint(anchorPoint(for: panel))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        NotificationCenter.default.post(name: Self.didHideNotification, object: nil)
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
                DispatchQueue.main.async { PanelController.shared.stepBackThroughHistory() }
            } else if hotKeyID.id >= PanelController.slotHotKeyBase {
                let slot = Int(hotKeyID.id - PanelController.slotHotKeyBase)
                DispatchQueue.main.async { PanelController.shared.recallSlot(slot) }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        registerConfigurableHotKeys()
        registerSlotHotKeys()
    }

    /// Registers the two rebindable shortcuts from whatever the user has chosen.
    private func registerConfigurableHotKeys() {
        let store = ShortcutStore.shared

        let open = store.binding(for: .openPanel)
        let openID = EventHotKeyID(signature: OSType(0x4B4C5059), id: Self.hotKeySignature)
        RegisterEventHotKey(open.keyCode, open.carbonModifiers, openID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
        _ = openID

        let step = store.binding(for: .stepBack)
        let stepID = EventHotKeyID(signature: OSType(0x4B4C5059), id: Self.sequentialHotKeySignature)
        RegisterEventHotKey(step.keyCode, step.carbonModifiers, stepID,
                            GetApplicationEventTarget(), 0, &sequentialHotKeyRef)
        _ = stepID
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
    func stepBackThroughHistory() {
        let items = ClipboardManager.shared.recentItems
        guard !items.isEmpty else { return }

        sequentialIndex = min(sequentialIndex + 1, items.count - 1)
        recallSlot(sequentialIndex)

        sequentialResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sequentialIndex = -1 }
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
    func recallSlot(_ index: Int) {
        let items = ClipboardManager.shared.recentItems
        guard index >= 0, index < items.count else { return }
        ClipboardManager.shared.copyToClipboard(items[index])
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
