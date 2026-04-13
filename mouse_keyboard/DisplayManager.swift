import AppKit
import CoreGraphics

final class DisplayManager {
    private var cachedOrderedDisplayBounds: [CGRect]?
    private var cachedCombinedDisplayBounds: CGRect?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func screenParametersDidChange() {
        invalidateCache()
    }

    private func invalidateCache() {
        cachedOrderedDisplayBounds = nil
        cachedCombinedDisplayBounds = nil
    }

    func currentDisplayBounds(at location: CGPoint) -> CGRect {
        let displays = orderedDisplayBounds()
        if let hit = displays.first(where: { $0.contains(location) }) {
            return hit
        }
        return combinedDisplayBounds()
    }

    func orderedDisplayBounds() -> [CGRect] {
        if let cachedOrderedDisplayBounds {
            return cachedOrderedDisplayBounds
        }

        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return []
        }

        let mainID = CGMainDisplayID()
        let bounded = displays.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) }

        let ordered = bounded.sorted { lhs, rhs in
            if lhs.0 == mainID { return true }
            if rhs.0 == mainID { return false }
            if lhs.1.minX != rhs.1.minX { return lhs.1.minX < rhs.1.minX }
            return lhs.1.minY < rhs.1.minY
        }.map { $0.1 }

        cachedOrderedDisplayBounds = ordered
        return ordered
    }

    func combinedDisplayBounds() -> CGRect {
        if let cachedCombinedDisplayBounds {
            return cachedCombinedDisplayBounds
        }

        let combined = orderedDisplayBounds().reduce(CGRect.null) { partial, displayBounds in
            partial.union(displayBounds)
        }

        let bounds = combined.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : combined
        cachedCombinedDisplayBounds = bounds
        return bounds
    }
}
