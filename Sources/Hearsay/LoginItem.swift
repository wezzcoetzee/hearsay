import Foundation
import ServiceManagement
import os

enum LoginItem {
    private static let log = Logger(subsystem: "com.wcoetzee.hearsay", category: "LoginItem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns whether the app is registered afterwards, which differs from what was
    /// asked when macOS refuses (an unsigned build, or one outside Applications).
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
