import Foundation
import LocalAuthentication
import Combine

/// Keeps the history behind Touch ID.
///
/// Klippy holds whatever you have copied, which in practice means API keys,
/// card numbers and private messages, all one keystroke away. Anyone sitting at
/// an unlocked Mac can read the lot. This puts the owner's fingerprint in front
/// of it.
///
/// It does not lock on every open. Recalling a clip is something people do
/// dozens of times an hour, and a prompt each time would get the feature turned
/// off within a day. Instead an unlock lasts for a chosen stretch, the way a
/// password manager behaves.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    static let enabledKey = "klippy.lock.enabled"
    static let timeoutKey = "klippy.lock.timeoutMinutes"

    /// How long an unlock lasts. Zero means every time the panel opens.
    static let timeoutChoices: [Int] = [0, 1, 5, 15, 60]

    @Published private(set) var isLocked: Bool = false
    @Published private(set) var lastError: String?

    private var unlockedAt: Date?
    private let defaults = UserDefaults.standard

    private init() {
        isLocked = Self.isEnabled
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Nil when the Mac cannot authenticate at all, so the setting can be
    /// refused up front rather than locking someone out of their own history.
    static var availability: String? {
        var error: NSError?
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return error?.localizedDescription ?? "This Mac cannot verify who you are."
        }
        return nil
    }

    var timeoutMinutes: Int {
        get {
            guard defaults.object(forKey: Self.timeoutKey) != nil else { return 5 }
            return defaults.integer(forKey: Self.timeoutKey)
        }
        set {
            defaults.set(newValue, forKey: Self.timeoutKey)
            objectWillChange.send()
        }
    }

    /// Called when the panel is about to appear.
    func refreshLockState() {
        guard Self.isEnabled else {
            isLocked = false
            return
        }
        guard let unlockedAt else {
            isLocked = true
            return
        }
        let minutes = timeoutMinutes
        if minutes == 0 || Date().timeIntervalSince(unlockedAt) > Double(minutes) * 60 {
            isLocked = true
        }
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        unlockedAt = enabled ? Date() : nil
        isLocked = false
        objectWillChange.send()
    }

    /// Locks again straight away, for the "Lock now" action.
    func lockNow() {
        guard Self.isEnabled else { return }
        unlockedAt = nil
        isLocked = true
    }

    func unlock() async {
        lastError = nil
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        // deviceOwnerAuthentication, not biometrics alone: it falls back to the
        // login password, so a Mac without Touch ID still works and a failed
        // finger never leaves someone locked out of their own clips.
        do {
            // The Touch ID sheet takes key focus, and the panel hides the moment
            // it loses that, so without the guard the whole window disappeared
            // as the prompt came up and the lock looked like a crash.
            let ok = try await PanelController.withModalSession {
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "unlock your clipboard history"
                )
            }
            if ok {
                unlockedAt = Date()
                isLocked = false
            }
        } catch {
            let code = (error as NSError).code
            // Cancelling is a choice, not a failure worth shouting about.
            if code != LAError.userCancel.rawValue && code != LAError.appCancel.rawValue {
                lastError = error.localizedDescription
            }
        }
    }
}
