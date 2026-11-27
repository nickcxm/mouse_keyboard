import AppKit
import ApplicationServices
import CoreGraphics

final class WindowDisplayMoveService {
    private enum Config {
        static let accessibilityMessagingTimeout: Float = 0.4
        static let fullscreenExitDelay: TimeInterval = 0.15
    }

    private let displayTopology: DisplayTopologyService
    private let axQueue = DispatchQueue(label: "com.neptuno.mouse-keyboard.ax-move", qos: .userInteractive)

    init(displayTopology: DisplayTopologyService = DisplayTopologyService()) {
        self.displayTopology = displayTopology
    }

    func makeSession() -> WindowDisplayMoveSession? {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, Config.accessibilityMessagingTimeout)
        guard
            let window = focusedWindow(for: appElement),
            let windowFrame = frame(of: window)
        else {
            return nil
        }

        let displays = displayTopology.currentDisplays().sorted { lhs, rhs in
            if lhs.id == CGMainDisplayID() { return true }
            if rhs.id == CGMainDisplayID() { return false }
            if lhs.bounds.minX != rhs.bounds.minX { return lhs.bounds.minX < rhs.bounds.minX }
            if lhs.bounds.minY != rhs.bounds.minY { return lhs.bounds.minY < rhs.bounds.minY }
            return lhs.stableIdentifier < rhs.stableIdentifier
        }
        guard !displays.isEmpty else {
            return nil
        }

        let currentDisplayID = displays.max { lhs, rhs in
            lhs.bounds.intersection(windowFrame).area < rhs.bounds.intersection(windowFrame).area
        }?.id
        let targets = displays.enumerated().map { index, display in
            WindowDisplayMoveTarget(
                id: index + 1,
                displayID: display.id,
                name: display.name,
                bounds: display.bounds,
                visibleBounds: visibleBounds(for: display.id) ?? display.bounds,
                isBuiltIn: CGDisplayIsBuiltin(display.id) == 1,
                containsCurrentWindow: display.id == currentDisplayID
            )
        }

        return WindowDisplayMoveSession(
            processIdentifier: application.processIdentifier,
            window: window,
            appName: application.localizedName ?? L10n.tr("display_move.unknown_app"),
            windowFrame: windowFrame,
            targets: targets
        )
    }

    func moveWindowAsync(in session: WindowDisplayMoveSession, toDisplayNumber number: Int) async -> CGRect? {
        await withCheckedContinuation { continuation in
            axQueue.async {
                let wasEnhanced = self.disableEnhancedUserInterface(for: session.processIdentifier)
                defer { self.restoreEnhancedUserInterface(wasEnhanced, for: session.processIdentifier) }
                continuation.resume(returning: self.moveWindow(in: session, toDisplayNumber: number))
            }
        }
    }

    func moveWindow(in session: WindowDisplayMoveSession, toDisplayNumber number: Int) -> CGRect? {
        guard let target = session.targets.first(where: { $0.id == number }) else {
            return nil
        }

        AXUIElementSetMessagingTimeout(session.window, Config.accessibilityMessagingTimeout)
        if copyAttribute(session.window, "AXFullScreen") as? Bool == true {
            guard setBoolean(false, attribute: "AXFullScreen", on: session.window) else {
                return nil
            }
            Thread.sleep(forTimeInterval: Config.fullscreenExitDelay)
        }

        guard let currentFrame = frame(of: session.window) else {
            return nil
        }

        let destination = target.visibleBounds
        let targetOrigin = CGPoint(
            x: destination.midX - currentFrame.width / 2,
            y: destination.midY - currentFrame.height / 2
        )
        guard setPoint(targetOrigin, attribute: kAXPositionAttribute, on: session.window) else {
            return nil
        }
        return frame(of: session.window) ?? CGRect(origin: targetOrigin, size: currentFrame.size)
    }

    private func focusedWindow(for appElement: AXUIElement) -> AXUIElement? {
        if let focusedWindow = copyElement(appElement, attribute: kAXFocusedWindowAttribute) {
            return focusedWindow
        }
        if let mainWindow = copyElement(appElement, attribute: kAXMainWindowAttribute) {
            return mainWindow
        }
        return (copyAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement])?.first
    }

    private func visibleBounds(for targetDisplayID: CGDirectDisplayID) -> CGRect? {
        guard
            let primaryScreen = NSScreen.screens.first(where: { displayID(for: $0) == CGMainDisplayID() }),
            let screen = NSScreen.screens.first(where: { displayID(for: $0) == targetDisplayID })
        else {
            return nil
        }

        let frame = screen.visibleFrame
        return CGRect(
            x: frame.minX,
            y: primaryScreen.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    func frame(of window: AXUIElement) -> CGRect? {
        guard
            let positionValue = copyAttribute(window, kAXPositionAttribute),
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            let sizeValue = copyAttribute(window, kAXSizeAttribute),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        guard
            let value = copyAttribute(element, attribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func setBoolean(_ value: Bool, attribute: String, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            attribute as CFString,
            value ? kCFBooleanTrue : kCFBooleanFalse
        ) == .success
    }

    func setPoint(_ point: CGPoint, attribute: String, on element: AXUIElement) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    func disableEnhancedUserInterface(for pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let wasEnabled = copyAttribute(app, "AXEnhancedUserInterface") as? Bool == true
        if wasEnabled {
            _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        return wasEnabled
    }

    func restoreEnhancedUserInterface(_ wasEnabled: Bool, for pid: pid_t) {
        guard wasEnabled else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// Move within `bounds` so the window never straddles displays, resize, then move to `frame.origin` after settle.
    @discardableResult
    func prepareAndResize(_ frame: CGRect, currentFrame: CGRect?, in bounds: CGRect?, on window: AXUIElement) -> (pos1: AXError, size: AXError) {
        let preOrigin: CGPoint
        if let bounds, let current = currentFrame {
            let maxX = max(bounds.minX, bounds.maxX - current.width)
            let maxY = max(bounds.minY, bounds.maxY - current.height)
            preOrigin = CGPoint(
                x: min(max(frame.minX, bounds.minX), maxX),
                y: min(max(frame.minY, bounds.minY), maxY)
            )
        } else {
            preOrigin = frame.origin
        }
        let pos1 = setPointError(preOrigin, attribute: kAXPositionAttribute, on: window)
        var size = frame.size
        let sizeErr: AXError
        if let value = AXValueCreate(.cgSize, &size) {
            sizeErr = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        } else {
            sizeErr = .illegalArgument
        }
        return (pos1, sizeErr)
    }

    /// Move before resizing so the destination display's constraints apply.
    @discardableResult
    func setFrame(_ frame: CGRect, on window: AXUIElement) -> (pos1: AXError, size: AXError, pos2: AXError) {
        let pos1 = setPointError(frame.origin, attribute: kAXPositionAttribute, on: window)
        var size = frame.size
        let sizeErr: AXError
        if let value = AXValueCreate(.cgSize, &size) {
            sizeErr = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        } else {
            sizeErr = .illegalArgument
        }
        let pos2 = setPointError(frame.origin, attribute: kAXPositionAttribute, on: window)
        return (pos1, sizeErr, pos2)
    }

    @discardableResult
    func setSize(_ size: CGSize, on element: AXUIElement) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            return .illegalArgument
        }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    private func setPointError(_ point: CGPoint, attribute: String, on element: AXUIElement) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            return .illegalArgument
        }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}
