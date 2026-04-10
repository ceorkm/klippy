import Foundation
import AppKit

/// Plays haptic feedback for Klippy actions.
/// Respects user preference from Settings.
enum FeedbackManager {
    private static let hapticsKey = "klippy.feedback.hapticsEnabled"

    static var hapticsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: hapticsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: hapticsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hapticsKey)
        }
    }

    // MARK: - Actions

    static func playCopy() {
        performHaptic(.generic)
    }

    static func playPin() {
        performHaptic(.levelChange)
    }

    static func playMerge() {
        performHaptic(.alignment)
    }

    static func playSave() {
        performHaptic(.generic)
    }

    static func playDelete() {
        performHaptic(.levelChange)
    }

    // MARK: - Primitives

    private static func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}
