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
