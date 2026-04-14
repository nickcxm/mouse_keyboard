import AppKit
import CoreGraphics
import Quartz

final class KeyboardMouseController {
    enum SpeedPreset: Int, CaseIterable {
        case slow
        case normal
        case fast

        var displayName: String {
            switch self {
            case .slow: return L10n.tr("speed.slow")
            case .normal: return L10n.tr("speed.normal")
            case .fast: return L10n.tr("speed.fast")
            }
        }

        var baseStep: CGFloat {
            switch self {
            case .slow: return 12
            case .normal: return 18
            case .fast: return 26
            }
        }

        var maxStep: CGFloat {
            switch self {
            case .slow: return 32
            case .normal: return 60
            case .fast: return 80
            }
        }

        var accelerationIncrement: CGFloat {
            switch self {
            case .slow: return 3
            case .normal: return 5
            case .fast: return 7
            }
        }

        var scrollLines: Int32 {
            switch self {
            case .slow: return 2
            case .normal: return 4
            case .fast: return 6
            }
        }
    }

    private enum Config {
        static let syntheticMouseIgnoreSeconds: CFTimeInterval = 0.12
        static let mouseExitThrottleSeconds: CFTimeInterval = 0.03
        static let appActivationCursorDelaySeconds: TimeInterval = 0.12
        static let minimumWindowEdgeLength: CGFloat = 40
    }

    private enum MultiWindowCursorPolicy {
        case doNotMove
        case firstWindowCenter
    }

    var onModeChanged: ((Bool) -> Void)?
    var onSpeedChanged: ((SpeedPreset) -> Void)?
    var onInfoMessage: ((String) -> Void)?
    var onScrollDirectionChanged: ((Bool) -> Void)?

    private(set) var isControlModeEnabled = false {
        didSet {
            onModeChanged?(isControlModeEnabled)
        }
    }

    private(set) var speed: SpeedPreset = .normal {
        didSet {
            settingsStore.saveSpeed(speed)
            movementEngine.setProfile(currentMovementProfile())
            onSpeedChanged?(speed)
        }
    }

    private(set) var isKeyboardScrollInverted = false {
        didSet {
            settingsStore.saveKeyboardScrollInverted(isKeyboardScrollInverted)
            onScrollDirectionChanged?(isKeyboardScrollInverted)
        }
    }

    private let permissionManager: PermissionManager
    private let settingsStore: SettingsStore
    private let displayManager: DisplayManager
    private let keyActionRouter = KeyActionRouter()
    private let eventTapService = EventTapService()
    private let movementEngine: MouseMovementEngine
    private let appSwitcherOverlay = AppSwitcherOverlayController()
    private let multiWindowCursorPolicy: MultiWindowCursorPolicy = .doNotMove

    private var ignoreMouseMovementUntil: CFTimeInterval = 0
    private var lastMouseExitCheckTimestamp: CFTimeInterval = 0
    private var cachedCursorPosition: CGPoint?

    init(
        permissionManager: PermissionManager,
        settingsStore: SettingsStore = SettingsStore(),
        displayManager: DisplayManager = DisplayManager()
    ) {
        self.permissionManager = permissionManager
        self.settingsStore = settingsStore
        self.displayManager = displayManager

        speed = settingsStore.loadSpeed()
        isKeyboardScrollInverted = settingsStore.loadKeyboardScrollInverted()
        movementEngine = MouseMovementEngine(initialProfile: MouseMovementEngine.Profile(
            baseStep: speed.baseStep,
            maxStep: speed.maxStep,
            accelerationIncrement: speed.accelerationIncrement
        ))
        movementEngine.onMove = { [weak self] dx, dy in
            self?.moveMouse(dx: dx, dy: dy)
        }
    }

    deinit {
        movementEngine.stopAndReset()
        stopEventTap()
    }

    @discardableResult
    func startEventTap() -> Bool {
        guard permissionManager.hasAccessibilityPermission() else {
            return false
        }

        return installEventTap(includeMouseEvents: isControlModeEnabled)
    }

    private func installEventTap(includeMouseEvents: Bool) -> Bool {
        eventTapService.stop()

        let keyDownMask = (1 as CGEventMask) << CGEventType.keyDown.rawValue
        let keyUpMask = (1 as CGEventMask) << CGEventType.keyUp.rawValue
        var events: CGEventMask = keyDownMask | keyUpMask
        if includeMouseEvents {
            let mouseMovedMask = (1 as CGEventMask) << CGEventType.mouseMoved.rawValue
            let leftDraggedMask = (1 as CGEventMask) << CGEventType.leftMouseDragged.rawValue
            let rightDraggedMask = (1 as CGEventMask) << CGEventType.rightMouseDragged.rawValue
            let otherDraggedMask = (1 as CGEventMask) << CGEventType.otherMouseDragged.rawValue
            events |= (mouseMovedMask | leftDraggedMask | rightDraggedMask | otherDraggedMask)
        }

        return eventTapService.start(eventsOfInterest: events) { [weak self] type, event in
            guard let self else {
                return Unmanaged.passUnretained(event)
            }
            return self.handleEvent(type: type, event: event)
        }
    }

    func stopEventTap() {
        eventTapService.stop()
    }

    func toggleControlMode() {
        setControlModeEnabled(!isControlModeEnabled)
    }

    func setControlModeEnabled(_ enabled: Bool) {
        isControlModeEnabled = enabled
        if !enabled {
            hideAppSwitcherOverlay()
            movementEngine.stopAndReset()
        }
        // Reduce event overhead when idle: only keep keyboard events outside control mode.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            _ = self.installEventTap(includeMouseEvents: self.isControlModeEnabled)
        }
    }

    func setSpeed(_ newSpeed: SpeedPreset) {
        speed = newSpeed
    }

    func setKeyboardScrollInverted(_ inverted: Bool) {
        isKeyboardScrollInverted = inverted
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            eventTapService.reenable()
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            return handleKeyDown(keyCode, originalEvent: event)

        case .keyUp:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            return handleKeyUp(keyCode, originalEvent: event)

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            cachedCursorPosition = event.location
            if shouldAutoExitFromMouseMovement() {
                setControlModeEnabled(false)
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ keyCode: CGKeyCode, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if isControlModeEnabled, keyCode == 48 || appSwitcherOverlay.isVisible {
            return handleAppSwitcherKeyDown(keyCode, originalEvent: originalEvent)
        }

        guard let action = keyActionRouter.keyDownAction(for: keyCode) else {
            guard isControlModeEnabled else {
                return Unmanaged.passUnretained(originalEvent)
            }

            setControlModeEnabled(false)
            return Unmanaged.passUnretained(originalEvent)
        }

        switch action {
        case .toggleMode:
            toggleControlMode()
            return nil

        default:
            guard isControlModeEnabled else {
                return Unmanaged.passUnretained(originalEvent)
            }
            performKeyDownAction(action)
            return nil
        }
    }

    private func handleKeyUp(_ keyCode: CGKeyCode, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if appSwitcherOverlay.isVisible || (isControlModeEnabled && keyCode == 48) {
            return handleAppSwitcherKeyUp(keyCode, originalEvent: originalEvent)
        }

        guard let action = keyActionRouter.keyUpAction(for: keyCode) else {
            return Unmanaged.passUnretained(originalEvent)
        }

        switch action {
        case .consumeGlobal:
            return nil

        default:
            guard isControlModeEnabled else {
                return Unmanaged.passUnretained(originalEvent)
            }
            performKeyUpAction(action)
            return nil
        }
    }

    private func performKeyDownAction(_ action: KeyActionRouter.KeyDownAction) {
        switch action {
        case .toggleMode:
            toggleControlMode()
        case .exitMode:
            setControlModeEnabled(false)
        case .startMove(let direction):
            movementEngine.setDirection(direction, isPressed: true)
        case .setBoost(let enabled):
            movementEngine.setBoostEnabled(enabled)
        case .setFineTune(let enabled):
            movementEngine.setFineTuneEnabled(enabled)
        case .scrollDown:
            scroll(lines: isKeyboardScrollInverted ? speed.scrollLines : -speed.scrollLines)
        case .scrollUp:
            scroll(lines: isKeyboardScrollInverted ? -speed.scrollLines : speed.scrollLines)
        case .leftClick:
            leftClick()
        case .rightClick:
            rightClick()
        case .quickRegion(let region):
            moveToRegion(region)
        case .displaySlot(let slot):
            moveToDisplaySlot(slot)
        }
    }

    private func performKeyUpAction(_ action: KeyActionRouter.KeyUpAction) {
        switch action {
        case .consumeGlobal, .consumeInControlMode:
            break
        case .stopMove(let direction):
            movementEngine.setDirection(direction, isPressed: false)
        case .setBoost(let enabled):
            movementEngine.setBoostEnabled(enabled)
        case .setFineTune(let enabled):
            movementEngine.setFineTuneEnabled(enabled)
        }
    }

    private func handleAppSwitcherKeyDown(_ keyCode: CGKeyCode, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if keyCode == 48 { // Tab
            if appSwitcherOverlay.isVisible {
                hideAppSwitcherOverlay()
            } else {
                showAppSwitcherOverlay()
            }
            return nil
        }

        guard appSwitcherOverlay.isVisible else {
            return Unmanaged.passUnretained(originalEvent)
        }

        switch keyCode {
        case 123: // Left
            appSwitcherOverlay.moveSelection(.left)
            return nil
        case 124: // Right
            appSwitcherOverlay.moveSelection(.right)
            return nil
        case 125: // Down
            appSwitcherOverlay.moveSelection(.down)
            return nil
        case 126: // Up
            appSwitcherOverlay.moveSelection(.up)
            return nil
        case 0: // A
            appSwitcherOverlay.moveSelection(.left)
            return nil
        case 2: // D
            appSwitcherOverlay.moveSelection(.right)
            return nil
        case 1: // S
            appSwitcherOverlay.moveSelection(.down)
            return nil
        case 13: // W
            appSwitcherOverlay.moveSelection(.up)
            return nil
        case 36, 76, 49: // Return / keypad Enter / Space
            if let activatedApp = appSwitcherOverlay.activateSelection() {
                hideAppSwitcherOverlay()
                scheduleCursorMoveAfterAppActivation(for: activatedApp)
            } else if appSwitcherOverlay.hasInputIdentifier {
                onInfoMessage?(L10n.tr("hud.app_switcher_id_not_found", appSwitcherOverlay.currentInputIdentifier))
            } else {
                onInfoMessage?(L10n.tr("hud.app_switcher_no_apps"))
                hideAppSwitcherOverlay()
            }
            return nil
        case 53: // Esc
            hideAppSwitcherOverlay()
            return nil
        case 51: // Delete / backspace
            appSwitcherOverlay.removeLastDigit()
            return nil
        default:
            if let digit = mapDigitFromKeyCode(keyCode) {
                if let activatedApp = appSwitcherOverlay.appendDigit(digit) {
                    hideAppSwitcherOverlay()
                    scheduleCursorMoveAfterAppActivation(for: activatedApp)
                }
                return nil
            }
            // Tab mode: non-selection keys should behave as a normal keyboard.
            return Unmanaged.passUnretained(originalEvent)
        }
    }

    private func handleAppSwitcherKeyUp(_ keyCode: CGKeyCode, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if isAppSwitcherConsumedKey(keyCode) {
            return nil
        }
        return Unmanaged.passUnretained(originalEvent)
    }

    private func isAppSwitcherConsumedKey(_ keyCode: CGKeyCode) -> Bool {
        switch keyCode {
        case 48, 53, 36, 76, 49, 51, 123, 124, 125, 126, 0, 1, 2, 13:
            return true
        default:
            return mapDigitFromKeyCode(keyCode) != nil
        }
    }

    private func mapDigitFromKeyCode(_ keyCode: CGKeyCode) -> Int? {
        switch keyCode {
        case 29: return 0
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        default: return nil
        }
    }

    private func showAppSwitcherOverlay() {
        movementEngine.stopAndReset()
        guard appSwitcherOverlay.show() else {
            onInfoMessage?(L10n.tr("hud.app_switcher_no_apps"))
            return
        }
    }

    private func hideAppSwitcherOverlay() {
        appSwitcherOverlay.hide()
    }

    private func scheduleCursorMoveAfterAppActivation(for app: NSRunningApplication) {
        let processIdentifier = app.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.appActivationCursorDelaySeconds) { [weak self] in
            self?.moveCursorForActivatedApp(processIdentifier: processIdentifier)
        }
    }

    private func moveCursorForActivatedApp(processIdentifier: pid_t) {
        let windowBounds = visibleWindowBounds(for: processIdentifier)

        if windowBounds.count == 1, let onlyWindow = windowBounds.first {
            warpCursor(to: CGPoint(x: onlyWindow.midX, y: onlyWindow.midY))
            return
        }

        if windowBounds.count > 1 {
            switch multiWindowCursorPolicy {
            case .doNotMove:
                return
            case .firstWindowCenter:
                if let firstWindow = windowBounds.first {
                    warpCursor(to: CGPoint(x: firstWindow.midX, y: firstWindow.midY))
                }
                return
            }
        }

        if let fallbackScreen = NSScreen.main {
            let center = CGPoint(x: fallbackScreen.frame.midX, y: fallbackScreen.frame.midY)
            warpCursor(to: center)
        }
    }

    private func visibleWindowBounds(for processIdentifier: pid_t) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfoList.compactMap { info in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPID.int32Value == processIdentifier
            else {
                return nil
            }

            guard let layer = info[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0 else {
                return nil
            }

            if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0.01 {
                return nil
            }

            guard
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                bounds.width >= Config.minimumWindowEdgeLength,
                bounds.height >= Config.minimumWindowEdgeLength
            else {
                return nil
            }

            return bounds
        }
    }

    private func warpCursor(to target: CGPoint) {
        let bounds = combinedDisplayBounds()
        let clamped = CGPoint(
            x: min(max(target.x, bounds.minX), bounds.maxX - 1),
            y: min(max(target.y, bounds.minY), bounds.maxY - 1)
        )
        markSyntheticMouseActivity()
        cachedCursorPosition = clamped
        CGWarpMouseCursorPosition(clamped)
    }

    private func shouldAutoExitFromMouseMovement() -> Bool {
        guard isControlModeEnabled else {
            return false
        }

        let now = CACurrentMediaTime()
        if now - lastMouseExitCheckTimestamp < Config.mouseExitThrottleSeconds {
            return false
        }
        lastMouseExitCheckTimestamp = now
        return now > ignoreMouseMovementUntil
    }

    func moveMouse(dx: CGFloat, dy: CGFloat) {
        let current = currentCursorPosition()

        let bounds = combinedDisplayBounds()
        var targetX = current.x + dx
        var targetY = current.y + dy

        targetX = min(max(targetX, bounds.minX), bounds.maxX - 1)
        targetY = min(max(targetY, bounds.minY), bounds.maxY - 1)

        markSyntheticMouseActivity()
        let target = CGPoint(x: targetX, y: targetY)
        cachedCursorPosition = target
        CGWarpMouseCursorPosition(target)
    }

    func rightClick() {
        click(button: .right)
    }

    func leftClick() {
        click(button: .left)
    }

    func scroll(lines: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private func moveToRegion(_ region: KeyActionRouter.QuickRegion) {
        let bounds = currentDisplayBounds()
        guard !bounds.isNull else {
            return
        }

        let target: CGPoint
        switch region {
        case .topLeft:
            target = CGPoint(x: bounds.minX + bounds.width * 0.25, y: bounds.minY + bounds.height * 0.25)
        case .topRight:
            target = CGPoint(x: bounds.minX + bounds.width * 0.75, y: bounds.minY + bounds.height * 0.25)
        case .bottomLeft:
            target = CGPoint(x: bounds.minX + bounds.width * 0.25, y: bounds.minY + bounds.height * 0.75)
        case .bottomRight:
            target = CGPoint(x: bounds.minX + bounds.width * 0.75, y: bounds.minY + bounds.height * 0.75)
        }

        markSyntheticMouseActivity()
        CGWarpMouseCursorPosition(target)
    }

    private func moveToDisplaySlot(_ slot: Int) {
        let currentLocation = currentCursorPosition()

        let orderedDisplays = orderedDisplayBounds()
        let index = slot - 1
        guard orderedDisplays.indices.contains(index) else {
            onInfoMessage?(L10n.tr("hud.display_not_available", slot))
            return
        }

        let targetDisplay = orderedDisplays[index]
        let target = CGPoint(x: targetDisplay.midX, y: targetDisplay.midY)
        markSyntheticMouseActivity()
        cachedCursorPosition = target
        CGWarpMouseCursorPosition(target)

        // Keep event tap from treating this synthetic jump as external mouse movement.
        if !targetDisplay.contains(currentLocation) {
            ignoreMouseMovementUntil = CACurrentMediaTime() + Config.syntheticMouseIgnoreSeconds
        }
    }

    private func click(button: CGMouseButton) {
        let location = currentCursorPosition()

        let downType: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp

        guard
            let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: location, mouseButton: button),
            let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: location, mouseButton: button)
        else {
            return
        }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func markSyntheticMouseActivity() {
        ignoreMouseMovementUntil = CACurrentMediaTime() + Config.syntheticMouseIgnoreSeconds
    }

    private func currentCursorPosition() -> CGPoint {
        if let cachedCursorPosition {
            return cachedCursorPosition
        }
        let location = CGEvent(source: nil)?.location ?? .zero
        cachedCursorPosition = location
        return location
    }

    private func currentMovementProfile() -> MouseMovementEngine.Profile {
        MouseMovementEngine.Profile(
            baseStep: speed.baseStep,
            maxStep: speed.maxStep,
            accelerationIncrement: speed.accelerationIncrement
        )
    }

    private func currentDisplayBounds() -> CGRect {
        guard let location = CGEvent(source: nil)?.location else {
            return combinedDisplayBounds()
        }
        return displayManager.currentDisplayBounds(at: location)
    }

    private func orderedDisplayBounds() -> [CGRect] {
        displayManager.orderedDisplayBounds()
    }

    private func combinedDisplayBounds() -> CGRect {
        displayManager.combinedDisplayBounds()
    }
}
