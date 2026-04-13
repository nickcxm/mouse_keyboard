import AppKit
import ApplicationServices

final class PermissionManager {
    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openPermissions() {
        if let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(accessibilityURL)
            return
        }

        if let settingsURL = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
