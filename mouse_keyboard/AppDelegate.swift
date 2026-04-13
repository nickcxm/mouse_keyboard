import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionManager = PermissionManager()
    private var keyboardController: KeyboardMouseController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = KeyboardMouseController(permissionManager: permissionManager)
        keyboardController = controller
        statusBarController = StatusBarController(keyboardController: controller, permissionManager: permissionManager)

        if !permissionManager.hasAccessibilityPermission() {
            _ = permissionManager.requestAccessibilityIfNeeded()
            showPermissionAlert()
        }

        _ = controller.startEventTap()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("alert.permission_title")
        alert.informativeText = L10n.tr("alert.permission_message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("menu.open_permissions"))
        alert.addButton(withTitle: L10n.tr("common.later"))

        if alert.runModal() == .alertFirstButtonReturn {
            permissionManager.openPermissions()
        }
    }
}
