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
        }

        _ = controller.startEventTap()
    }

}
