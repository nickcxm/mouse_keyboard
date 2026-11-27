import AppKit
import ApplicationServices

final class ApplicationWindowTiler {
    private struct Placement {
        let window: AXUIElement
        let frame: CGRect
    }

    private struct BrowseSession {
        let application: NSRunningApplication
        let windows: [AXUIElement]
        let originalFrames: [CGRect]
        let displayID: CGDirectDisplayID
        let displayBounds: CGRect
        let visibleBounds: CGRect
        var currentIndex: Int?
        var lastIndex: Int?
    }

    struct Result {
        let message: String
        let focusedFrame: CGRect?
    }

    private let geometry = WindowDisplayMoveService()
    private let axQueue = DispatchQueue(label: "com.neptuno.mouse-keyboard.ax-tiler", qos: .userInteractive)
    private var browseSessions: [pid_t: BrowseSession] = [:]
    private(set) var isBusy = false

    // MARK: - 1. End + PgDn / End + PgUp: Arrange all windows

    func perform(maximizeAll: Bool, session: WindowDisplayMoveSession) async -> Result {
        guard !isBusy else { return Result(message: L10n.tr("tile.busy"), focusedFrame: nil) }
        isBusy = true
        defer { isBusy = false }

        browseSessions = browseSessions.filter { !$0.value.application.isTerminated }
        browseSessions[session.processIdentifier] = nil

        guard let app = NSRunningApplication(processIdentifier: session.processIdentifier),
              !app.isTerminated,
              let target = session.targets.first(where: \.containsCurrentWindow) else {
            return Result(message: L10n.tr("hud.display_move_no_window"), focusedFrame: nil)
        }

        let connectedDisplays = DisplayTopologyService().currentDisplays()
        guard let connected = connectedDisplays.first(where: { $0.id == target.displayID }),
              connected.bounds == target.bounds else {
            return Result(message: L10n.tr("tile.display_changed"), focusedFrame: nil)
        }

        let wasEnhanced = await runOnAXQueue {
            self.geometry.disableEnhancedUserInterface(for: session.processIdentifier)
        }
        defer {
            let pid = session.processIdentifier
            axQueue.async { self.geometry.restoreEnhancedUserInterface(wasEnhanced, for: pid) }
        }

        let (eligible, skipped) = await runOnAXQueue { self.eligibleWindows(session: session) }
        guard !eligible.isEmpty else {
            return Result(message: L10n.tr("tile.no_windows"), focusedFrame: nil)
        }

        if maximizeAll {
            let frames = WindowTileGeometry.maximizedFrames(count: eligible.count, in: target.visibleBounds)
            let requests = zip(eligible, frames).map { Placement(window: $0.0.window, frame: $0.1) }
            let applied = await runOnAXQueue { self.applyTilingSync(requests, in: target.visibleBounds) }
            return await runOnAXQueue {
                self.finish(session: session, message: L10n.tr(applied ? "tile.all_maximized" : "tile.maximize_failed"))
            }
        }

        let candidates = WindowTileGeometry.layoutCandidates(count: eligible.count, in: target.visibleBounds)
        let (arranged, rolledBack) = await runOnAXQueue { () -> (Bool, Bool) in
            var failedWidth = Array(repeating: CGFloat(0), count: eligible.count)
            var failedHeight = Array(repeating: CGFloat(0), count: eligible.count)
            for (index, placement) in eligible.enumerated() {
                if let minSize = self.minimumSize(of: placement.window) {
                    if minSize.width > 3 { failedWidth[index] = minSize.width - 3.01 }
                    if minSize.height > 3 { failedHeight[index] = minSize.height - 3.01 }
                }
            }

            for frames in candidates {
                guard !app.isTerminated else { break }
                let violatesConstraint = frames.enumerated().contains { index, frame in
                    frame.width <= failedWidth[index] || frame.height <= failedHeight[index]
                }
                if violatesConstraint { continue }

                let requests = zip(eligible, frames).map { Placement(window: $0.0.window, frame: $0.1) }
                if self.applyTilingSync(requests, in: target.visibleBounds) {
                    return (true, false)
                }

                for (index, request) in requests.enumerated() {
                    guard let actual = self.geometry.frame(of: request.window) else { continue }
                    let initial = eligible[index].frame
                    if actual.width > request.frame.width + 3 && request.frame.width < initial.width {
                        failedWidth[index] = max(failedWidth[index], request.frame.width)
                    }
                    if actual.height > request.frame.height + 3
                        && request.frame.height < initial.height
                        && actual.width <= request.frame.width + 3 {
                        failedHeight[index] = max(failedHeight[index], request.frame.height)
                    }
                }
            }
            return (false, self.applyExactSync(eligible))
        }

        if !arranged {
            return await runOnAXQueue {
                self.finish(
                    session: session,
                    message: L10n.tr(rolledBack ? "tile.failed" : "tile.rollback_failed")
                )
            }
        }
        return await runOnAXQueue {
            self.finish(session: session, message: L10n.tr("tile.done", eligible.count, skipped))
        }
    }

    // MARK: - 2 & 3. PageUp (enlarge / cycle) & PageDown (restore current)

    func setMaximized(
        restore: Bool,
        session: WindowDisplayMoveSession,
        shouldFinishImmediately: () -> Bool = { false }
    ) async -> Result {
        guard !isBusy else { return Result(message: L10n.tr("tile.busy"), focusedFrame: nil) }
        isBusy = true
        defer { isBusy = false }

        browseSessions = browseSessions.filter { !$0.value.application.isTerminated }
        let pid = session.processIdentifier

        let connectedDisplays = DisplayTopologyService().currentDisplays()
        let wasEnhanced = await runOnAXQueue {
            self.geometry.disableEnhancedUserInterface(for: pid)
        }
        defer {
            axQueue.async { self.geometry.restoreEnhancedUserInterface(wasEnhanced, for: pid) }
        }

        // 3. Standalone PageDown: restore the currently enlarged window to its original position/size.
        if restore {
            guard var browse = browseSessions[pid], let currentIndex = browse.currentIndex else {
                return Result(message: L10n.tr("tile.no_maximize_history"), focusedFrame: nil)
            }
            let window = browse.windows[currentIndex]
            let original = reachableFrame(browse.originalFrames[currentIndex], displays: connectedDisplays, fallback: session)
            browse.currentIndex = nil
            browseSessions[pid] = nil
            return await runOnAXQueue {
                self.placeWindowSync(window, to: original)
                return self.finish(session: session, message: L10n.tr("tile.unmaximized"), focusedWindow: window)
            }
        }

        // Initialize browse session on first PageUp for this app.
        if browseSessions[pid] == nil {
            let eligible = await runOnAXQueue { self.eligibleWindows(session: session).0 }
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  eligible.contains(where: { CFEqual($0.window, session.window) }),
                  let target = session.targets.first(where: \.containsCurrentWindow) else {
                return Result(message: L10n.tr("tile.no_windows"), focusedFrame: nil)
            }
            browseSessions[pid] = BrowseSession(
                application: app,
                windows: eligible.map(\.window),
                originalFrames: eligible.map(\.frame),
                displayID: target.displayID,
                displayBounds: target.bounds,
                visibleBounds: target.visibleBounds,
                currentIndex: nil,
                lastIndex: nil
            )
        }

        guard var browse = browseSessions[pid] else {
            return Result(message: L10n.tr("tile.no_windows"), focusedFrame: nil)
        }

        // Step A: Shrink the previously enlarged window back to its original position/size first.
        if let currentIndex = browse.currentIndex {
            let previousWindow = browse.windows[currentIndex]
            let original = reachableFrame(browse.originalFrames[currentIndex], displays: connectedDisplays, fallback: session)
            await runOnAXQueue {
                if self.windows(for: pid).contains(where: { CFEqual($0, previousWindow) }) {
                    self.placeWindowSync(previousWindow, to: original)
                }
            }
            browse.currentIndex = nil
            browseSessions[pid] = browse
        }

        if shouldFinishImmediately() {
            browseSessions[pid] = nil
            return Result(message: L10n.tr("tile.unmaximized"), focusedFrame: nil)
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              connectedDisplays.contains(where: {
                  $0.id == browse.displayID && $0.bounds == browse.displayBounds
              }) else {
            return Result(message: L10n.tr("tile.display_changed"), focusedFrame: nil)
        }

        // Step B: Pick the next available window.
        let eligible = await runOnAXQueue { self.eligibleWindows(session: session).0 }
        let start = browse.lastIndex.map { ($0 + 1) % browse.windows.count } ?? 0
        var nextIndex: Int?
        for offset in browse.windows.indices {
            let candidate = (start + offset) % browse.windows.count
            if eligible.contains(where: { CFEqual($0.window, browse.windows[candidate]) }) {
                nextIndex = candidate
                break
            }
        }
        guard let next = nextIndex else {
            browseSessions[pid] = nil
            return Result(message: L10n.tr("tile.no_windows"), focusedFrame: nil)
        }

        // Step C: Enlarge the next window to full visibleBounds, then bring it to front.
        let nextWindow = browse.windows[next]
        let targetBounds = browse.visibleBounds
        browse.currentIndex = next
        browse.lastIndex = next
        browseSessions[pid] = browse
        return await runOnAXQueue {
            self.placeWindowSync(nextWindow, to: targetBounds)
            return self.finish(session: session, message: L10n.tr("tile.maximized"), focusedWindow: nextWindow)
        }
    }

    // MARK: - Background AX Execution

    private func runOnAXQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            axQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    /// Moves and resizes a single window sequentially on `axQueue` so position and size never fight each other:
    /// - Shrinking: resize first (safe in current bounds), wait for size to settle, then move.
    /// - Growing: move to target origin first, wait until positioned, then resize.
    private func placeWindowSync(_ window: AXUIElement, to target: CGRect) {
        for attempt in 0..<2 {
            let current = geometry.frame(of: window)
            let isGrowing = current.map {
                target.width > $0.width + 3 || target.height > $0.height + 3
            } ?? true

            if isGrowing {
                _ = geometry.setPoint(target.origin, attribute: kAXPositionAttribute, on: window)
                waitUntilSync(window: window, matchesOrigin: target.origin)
                _ = geometry.setSize(target.size, on: window)
                waitUntilSync(window: window, matchesSize: target.size)
            } else {
                _ = geometry.setSize(target.size, on: window)
                waitUntilSync(window: window, matchesSize: target.size)
                _ = geometry.setPoint(target.origin, attribute: kAXPositionAttribute, on: window)
                waitUntilSync(window: window, matchesOrigin: target.origin)
            }

            if let actual = geometry.frame(of: window), WindowTileGeometry.matches(actual, target) {
                return
            }
            if attempt == 0 {
                _ = geometry.setPoint(target.origin, attribute: kAXPositionAttribute, on: window)
                Thread.sleep(forTimeInterval: 0.04)
            }
        }
    }

    private func waitUntilSync(window: AXUIElement, matchesOrigin origin: CGPoint) {
        for _ in 0..<15 {
            if let actual = geometry.frame(of: window),
               abs(actual.minX - origin.x) <= 6 && abs(actual.minY - origin.y) <= 6 {
                return
            }
            Thread.sleep(forTimeInterval: 0.015)
        }
    }

    private func waitUntilSync(window: AXUIElement, matchesSize size: CGSize) {
        for _ in 0..<18 {
            if let actual = geometry.frame(of: window),
               abs(actual.width - size.width) <= 8 && abs(actual.height - size.height) <= 8 {
                return
            }
            Thread.sleep(forTimeInterval: 0.015)
        }
    }

    // MARK: - Multi-window Tiling Helpers

    private func applyTilingSync(_ requests: [Placement], in bounds: CGRect) -> Bool {
        if allFit(requests, in: bounds) { return true }
        for _ in 0..<2 {
            for request in requests {
                let current = geometry.frame(of: request.window)
                _ = geometry.prepareAndResize(request.frame, currentFrame: current, in: bounds, on: request.window)
            }
            Thread.sleep(forTimeInterval: 0.18)
            for request in requests {
                _ = geometry.setPoint(request.frame.origin, attribute: kAXPositionAttribute, on: request.window)
            }
            Thread.sleep(forTimeInterval: 0.08)
            if allFit(requests, in: bounds) { return true }
        }
        return false
    }

    private func applyExactSync(_ requests: [Placement]) -> Bool {
        for _ in 0..<2 {
            for request in requests {
                _ = geometry.setFrame(request.frame, on: request.window)
            }
            Thread.sleep(forTimeInterval: 0.12)
            if requests.allSatisfy({
                guard let actual = geometry.frame(of: $0.window) else { return false }
                return WindowTileGeometry.matches(actual, $0.frame)
            }) { return true }
        }
        return false
    }

    private func allFit(_ requests: [Placement], in bounds: CGRect) -> Bool {
        let actuals = requests.compactMap { geometry.frame(of: $0.window) }
        guard actuals.count == requests.count else { return false }
        return WindowTileGeometry.allFit(actuals, expected: requests.map(\.frame), in: bounds)
    }

    // MARK: - Window Discovery & Focus

    private func eligibleWindows(session: WindowDisplayMoveSession) -> ([Placement], Int) {
        let all = windows(for: session.processIdentifier)
        let visible = visibleFrames(for: session.processIdentifier)
        var eligible = all.compactMap { window -> Placement? in
            guard geometry.copyAttribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                  geometry.copyAttribute(window, kAXMinimizedAttribute) as? Bool != true,
                  geometry.copyAttribute(window, "AXFullScreen") as? Bool != true,
                  let frame = geometry.frame(of: window),
                  visible.contains(where: { WindowTileGeometry.matches($0, frame) }),
                  isSettable(kAXPositionAttribute, on: window),
                  isSettable(kAXSizeAttribute, on: window) else { return nil }
            return Placement(window: window, frame: frame)
        }
        let skipped = all.count - eligible.count
        eligible.sort { lhs, rhs in
            if CFEqual(lhs.window, rhs.window) { return false }
            if CFEqual(lhs.window, session.window) { return true }
            if CFEqual(rhs.window, session.window) { return false }
            if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
            return lhs.frame.minX < rhs.frame.minX
        }
        return (eligible, skipped)
    }

    private func reachableFrame(
        _ original: CGRect,
        displays: [LayoutDisplayDescriptor],
        fallback session: WindowDisplayMoveSession
    ) -> CGRect {
        let center = CGPoint(x: original.midX, y: original.midY)
        if displays.contains(where: { $0.bounds.contains(center) }) {
            return original
        }
        return session.targets.first(where: \.containsCurrentWindow)?.visibleBounds ?? original
    }

    private func finish(session: WindowDisplayMoveSession, message: String, focusedWindow: AXUIElement? = nil) -> Result {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == session.processIdentifier else {
            return Result(message: message, focusedFrame: nil)
        }
        let window = focusedWindow ?? session.window
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
            return Result(message: message, focusedFrame: nil)
        }
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return Result(message: message, focusedFrame: geometry.frame(of: window))
    }

    private func windows(for pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let windows = geometry.copyAttribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows { AXUIElementSetMessagingTimeout(window, 0.25) }
        return windows
    }

    private func minimumSize(of window: AXUIElement) -> CGSize? {
        guard let value = geometry.copyAttribute(window, "AXMinimumSize"),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func isSettable(_ attribute: String, on window: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, attribute as CFString, &settable) == .success && settable.boolValue
    }

    private func visibleFrames(for pid: pid_t) -> [CGRect] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return info.compactMap { item in
            guard item[kCGWindowOwnerPID as String] as? pid_t == pid,
                  item[kCGWindowLayer as String] as? Int == 0,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }
}
