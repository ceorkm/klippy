import Foundation
import ServiceManagement

/// Registers Klippy to start with the Mac.
///
/// Lived in the old ContentView until that screen was replaced by the panel.
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
