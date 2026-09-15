import Foundation
import AppKit
import Carbon.HIToolbox

/// A user-assignable key combination.
struct ShortcutBinding: Equatable, Codable {
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, controlKey, optionKey, shiftKey).
    var carbonModifiers: UInt32
    /// Pre-rendered label, so no reverse key-code lookup is needed to draw it.
    var display: String

    static let openPanel = ShortcutBinding(keyCode: UInt32(kVK_ANSI_V),
                                           carbonModifiers: UInt32(controlKey | cmdKey),
                                           display: "⌃⌘V")

    static let stepBack = ShortcutBinding(keyCode: UInt32(kVK_DownArrow),
                                          carbonModifiers: UInt32(controlKey | cmdKey),
                                          display: "⌃⌘↓")

    /// Builds a binding from a real key press, or nil if the press carries no
    /// modifier. An unmodified global hotkey would swallow the key system-wide.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        var carbon: UInt32 = 0
        var label = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option)  { carbon |= UInt32(optionKey);  label += "⌥" }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey);   label += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey);     label += "⌘" }

        guard carbon != 0 else { return nil }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = carbon
        self.display = label + Self.keyLabel(for: event)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_DownArrow:  return "↓"
        case kVK_UpArrow:    return "↑"
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        case kVK_Space:      return "Space"
        case kVK_Return:     return "↩"
        case kVK_Escape:     return "esc"
        case kVK_Tab:        return "⇥"
        default:
            return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// Persists the user's shortcut choices. The Settings rows were previously
/// fixed labels that could not be changed.
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    enum Action: String, CaseIterable {
        case openPanel
        case stepBack

        var title: String {
            switch self {
            case .openPanel: return "Open Klippy"
            case .stepBack:  return "Step back through history"
            }
        }

        var fallback: ShortcutBinding {
            switch self {
            case .openPanel: return .openPanel
            case .stepBack:  return .stepBack
            }
        }
    }

    @Published private(set) var bindings: [Action: ShortcutBinding] = [:]

    private let defaults = UserDefaults.standard

    private init() {
        for action in Action.allCases {
            bindings[action] = load(action) ?? action.fallback
        }
    }

    func binding(for action: Action) -> ShortcutBinding {
        bindings[action] ?? action.fallback
    }

    func set(_ binding: ShortcutBinding, for action: Action) {
        bindings[action] = binding
        if let data = try? JSONEncoder().encode(binding) {
            defaults.set(data, forKey: Self.key(action))
        }
        PanelController.shared.reloadHotKeys()
    }

    func reset(_ action: Action) {
        bindings[action] = action.fallback
        defaults.removeObject(forKey: Self.key(action))
        PanelController.shared.reloadHotKeys()
    }

    private func load(_ action: Action) -> ShortcutBinding? {
        guard let data = defaults.data(forKey: Self.key(action)) else { return nil }
        return try? JSONDecoder().decode(ShortcutBinding.self, from: data)
    }

    private static func key(_ action: Action) -> String {
        "klippy.shortcut.\(action.rawValue)"
    }
}
