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

    enum KeyMapping {
        static let f8: CGKeyCode = 100
        static let one: CGKeyCode = 18
        static let two: CGKeyCode = 19
        static let three: CGKeyCode = 20
        static let w: CGKeyCode = 13
        static let a: CGKeyCode = 0
        static let s: CGKeyCode = 1
        static let d: CGKeyCode = 2
        static let i: CGKeyCode = 34
        static let o: CGKeyCode = 31
        static let j: CGKeyCode = 38
        static let k: CGKeyCode = 40
        static let y: CGKeyCode = 16
        static let h: CGKeyCode = 4
        static let minus: CGKeyCode = 27
        static let equal: CGKeyCode = 24
        static let leftBracket: CGKeyCode = 33
        static let rightBracket: CGKeyCode = 30
        static let escape: CGKeyCode = 53
    }

    private enum Config {
        static let syntheticMouseIgnoreSeconds: CFTimeInterval = 0.12
    }

    private enum QuickRegion {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
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
    private let eventTapService = EventTapService()
    private let movementEngine: MouseMovementEngine

    private var ignoreMouseMovementUntil: CFTimeInterval = 0

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

        let keyDownMask = (1 as CGEventMask) << CGEventType.keyDown.rawValue
        let keyUpMask = (1 as CGEventMask) << CGEventType.keyUp.rawValue
        let mouseMovedMask = (1 as CGEventMask) << CGEventType.mouseMoved.rawValue
        let leftDraggedMask = (1 as CGEventMask) << CGEventType.leftMouseDragged.rawValue
        let rightDraggedMask = (1 as CGEventMask) << CGEventType.rightMouseDragged.rawValue
        let otherDraggedMask = (1 as CGEventMask) << CGEventType.otherMouseDragged.rawValue
        let events: CGEventMask = keyDownMask | keyUpMask | mouseMovedMask | leftDraggedMask | rightDraggedMask | otherDraggedMask

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
            if shouldAutoExitFromMouseMovement() {
                setControlModeEnabled(false)
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ keyCode: CGKeyCode, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if keyCode == KeyMapping.f8 {
            toggleControlMode()
            return nil
        }

        guard isControlModeEnabled else {
            return Unmanaged.passUnretained(originalEvent)
        }

        if keyCode == KeyMapping.escape {
            setControlModeEnabled(false)
            return nil
        }

        if handleMappedKeyDown(keyCode) {
            return nil
        }

        setControlModeEnabled(false)
        return Unmanaged.passUnretained(originalEvent)
    }

    private func handleKeyUp(_ keyCode: CGKeyCode, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if keyCode == KeyMapping.f8 {
            return nil
        }

        guard isControlModeEnabled else {
            return Unmanaged.passUnretained(originalEvent)
        }

        if handleMappedKeyUp(keyCode) {
            return nil
        }

        return Unmanaged.passUnretained(originalEvent)
    }

    private func handleMappedKeyDown(_ keyCode: CGKeyCode) -> Bool {
        switch keyCode {
        case KeyMapping.w:
            movementEngine.setDirection(.up, isPressed: true)
            return true
        case KeyMapping.s:
            movementEngine.setDirection(.down, isPressed: true)
            return true
        case KeyMapping.a:
            movementEngine.setDirection(.left, isPressed: true)
            return true
        case KeyMapping.d:
            movementEngine.setDirection(.right, isPressed: true)
            return true

        case KeyMapping.j:
            scroll(lines: isKeyboardScrollInverted ? speed.scrollLines : -speed.scrollLines)
            return true
        case KeyMapping.k:
            scroll(lines: isKeyboardScrollInverted ? -speed.scrollLines : speed.scrollLines)
            return true

        case KeyMapping.i:
            leftClick()
            return true
        case KeyMapping.o:
            rightClick()
            return true

        case KeyMapping.y:
            movementEngine.setBoostEnabled(true)
            return true
        case KeyMapping.h:
            movementEngine.setFineTuneEnabled(true)
            return true

        case KeyMapping.minus:
            moveToRegion(.topLeft)
            return true
        case KeyMapping.equal:
            moveToRegion(.topRight)
            return true
        case KeyMapping.leftBracket:
            moveToRegion(.bottomLeft)
            return true
        case KeyMapping.rightBracket:
            moveToRegion(.bottomRight)
            return true
        case KeyMapping.one:
            moveToDisplaySlot(1)
            return true
        case KeyMapping.two:
            moveToDisplaySlot(2)
            return true
        case KeyMapping.three:
            moveToDisplaySlot(3)
            return true

        default:
            movementEngine.resetState()
            return false
        }
    }

    private func handleMappedKeyUp(_ keyCode: CGKeyCode) -> Bool {
        switch keyCode {
        case KeyMapping.w:
            movementEngine.setDirection(.up, isPressed: false)
            return true
        case KeyMapping.a:
            movementEngine.setDirection(.left, isPressed: false)
            return true
        case KeyMapping.s:
            movementEngine.setDirection(.down, isPressed: false)
            return true
        case KeyMapping.d:
            movementEngine.setDirection(.right, isPressed: false)
            return true

        case KeyMapping.y:
            movementEngine.setBoostEnabled(false)
            return true
        case KeyMapping.h:
            movementEngine.setFineTuneEnabled(false)
            return true

        case KeyMapping.j, KeyMapping.k,
             KeyMapping.minus, KeyMapping.equal,
             KeyMapping.leftBracket, KeyMapping.rightBracket,
             KeyMapping.one, KeyMapping.two, KeyMapping.three,
             KeyMapping.i, KeyMapping.o, KeyMapping.escape:
            return true

        default:
            return false
        }
    }

    private func shouldAutoExitFromMouseMovement() -> Bool {
        guard isControlModeEnabled else {
            return false
        }

        let now = CACurrentMediaTime()
        return now > ignoreMouseMovementUntil
    }

    func moveMouse(dx: CGFloat, dy: CGFloat) {
        guard let current = CGEvent(source: nil)?.location else {
            return
        }

        let bounds = combinedDisplayBounds()
        var targetX = current.x + dx
        var targetY = current.y + dy

        targetX = min(max(targetX, bounds.minX), bounds.maxX - 1)
        targetY = min(max(targetY, bounds.minY), bounds.maxY - 1)

        markSyntheticMouseActivity()
        CGWarpMouseCursorPosition(CGPoint(x: targetX, y: targetY))
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

    private func moveToRegion(_ region: QuickRegion) {
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
        guard let currentLocation = CGEvent(source: nil)?.location else {
            return
        }

        let orderedDisplays = orderedDisplayBounds()
        let index = slot - 1
        guard orderedDisplays.indices.contains(index) else {
            onInfoMessage?(L10n.tr("hud.display_not_available", slot))
            return
        }

        let targetDisplay = orderedDisplays[index]
        let target = CGPoint(x: targetDisplay.midX, y: targetDisplay.midY)
        markSyntheticMouseActivity()
        CGWarpMouseCursorPosition(target)

        // Keep event tap from treating this synthetic jump as external mouse movement.
        if !targetDisplay.contains(currentLocation) {
            ignoreMouseMovementUntil = CACurrentMediaTime() + Config.syntheticMouseIgnoreSeconds
        }
    }

    private func click(button: CGMouseButton) {
        guard let location = CGEvent(source: nil)?.location else {
            return
        }

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
