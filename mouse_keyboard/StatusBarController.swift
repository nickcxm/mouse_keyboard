import AppKit
import ServiceManagement

final class StatusBarController: NSObject {
    private let keyboardController: KeyboardMouseController
    private let permissionManager: PermissionManager
    private let modeHUD = ModeHUDController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let toggleItem = NSMenuItem()
    private let speedMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let speedSubmenu = NSMenu()
    private let invertScrollItem = NSMenuItem(title: "", action: #selector(toggleInvertScroll), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let openPermissionsItem = NSMenuItem(title: "", action: #selector(openPermissions), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: #selector(quitApp), keyEquivalent: "q")

    private var speedItems: [KeyboardMouseController.SpeedPreset: NSMenuItem] = [:]

    init(keyboardController: KeyboardMouseController, permissionManager: PermissionManager) {
        self.keyboardController = keyboardController
        self.permissionManager = permissionManager
        super.init()

        configureStatusItem()
        configureMenu()
        bindControllerState()
        refreshMenuState()
    }

    private func configureStatusItem() {
        statusItem.button?.title = ""
        statusItem.button?.image = StatusBarIconFactory.makeIcon(isActive: false)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = L10n.tr("status.tooltip")
        statusItem.menu = menu
    }

    private func configureMenu() {
        toggleItem.target = self
        toggleItem.action = #selector(toggleControlMode)
        speedMenuItem.title = L10n.tr("menu.speed")
        invertScrollItem.title = L10n.tr("menu.invert_scroll")
        launchAtLoginItem.title = L10n.tr("menu.launch_at_login")
        openPermissionsItem.title = L10n.tr("menu.open_permissions")
        quitItem.title = L10n.tr("menu.quit")

        KeyboardMouseController.SpeedPreset.allCases.forEach { preset in
            let item = NSMenuItem(title: preset.displayName, action: #selector(selectSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.tag = preset.rawValue
            speedSubmenu.addItem(item)
            speedItems[preset] = item
        }

        speedMenuItem.submenu = speedSubmenu
        invertScrollItem.target = self
        launchAtLoginItem.target = self
        openPermissionsItem.target = self
        quitItem.target = self

        menu.addItem(toggleItem)
        menu.addItem(speedMenuItem)
        menu.addItem(invertScrollItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(openPermissionsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    private func bindControllerState() {
        keyboardController.onModeChanged = { [weak self] isEnabled in
            self?.refreshMenuState()
            self?.modeHUD.show(message: isEnabled ? L10n.tr("hud.mode_on") : L10n.tr("hud.mode_off"), enabled: isEnabled)
        }
        keyboardController.onSpeedChanged = { [weak self] _ in
            self?.refreshMenuState()
        }
        keyboardController.onScrollDirectionChanged = { [weak self] _ in
            self?.refreshMenuState()
        }
        keyboardController.onInfoMessage = { [weak self] message in
            self?.modeHUD.show(message: message, enabled: false)
        }
    }

    private func refreshMenuState() {
        let isEnabled = keyboardController.isControlModeEnabled
        toggleItem.title = isEnabled ? L10n.tr("menu.disable") : L10n.tr("menu.enable")
        statusItem.button?.image = StatusBarIconFactory.makeIcon(isActive: isEnabled)
        updateLaunchAtLoginItem()
        invertScrollItem.state = keyboardController.isKeyboardScrollInverted ? .on : .off

        for (preset, item) in speedItems {
            item.state = (preset == keyboardController.speed) ? .on : .off
        }
    }

    @objc
    private func toggleControlMode() {
        if !permissionManager.hasAccessibilityPermission() {
            _ = permissionManager.requestAccessibilityIfNeeded()
            return
        }

        keyboardController.toggleControlMode()
    }

    @objc
    private func selectSpeed(_ sender: NSMenuItem) {
        guard let preset = KeyboardMouseController.SpeedPreset(rawValue: sender.tag) else {
            return
        }

        keyboardController.setSpeed(preset)
    }

    @objc
    private func openPermissions() {
        permissionManager.openPermissions()
    }

    @objc
    private func toggleInvertScroll() {
        keyboardController.setKeyboardScrollInverted(!keyboardController.isKeyboardScrollInverted)
    }

    @objc
    private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else {
            return
        }

        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            default:
                try SMAppService.mainApp.register()
            }
        } catch {
            showLaunchAtLoginError(error)
        }

        updateLaunchAtLoginItem()
    }

    private func updateLaunchAtLoginItem() {
        guard #available(macOS 13.0, *) else {
            launchAtLoginItem.title = L10n.tr("menu.launch_at_login_compat")
            launchAtLoginItem.state = .off
            launchAtLoginItem.isEnabled = false
            return
        }

        launchAtLoginItem.title = L10n.tr("menu.launch_at_login")
        launchAtLoginItem.isEnabled = true
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    private func showLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("alert.launch_login_failed_title")
        alert.informativeText = "\(error.localizedDescription)\n\n\(L10n.tr("alert.launch_login_failed_message"))"
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}
