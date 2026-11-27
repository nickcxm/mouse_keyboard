import CoreGraphics

nonisolated enum WindowBrowseTransition {
    static let restoreDuration = 0.12
    static let maximizeDuration = 0.16

    /// Cubic-bezier(0.77, 0, 0.175, 1): ease in and out without overshoot.
    static func frame(from start: CGRect, to end: CGRect, progress: Double) -> CGRect {
        guard progress > 0 else { return start }
        guard progress < 1 else { return end }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<20 {
            let t = (lower + upper) / 2
            let x = 3 * (1 - t) * (1 - t) * t * 0.77
                + 3 * (1 - t) * t * t * 0.175 + t * t * t
            if x < progress { lower = t } else { upper = t }
        }
        let t = (lower + upper) / 2
        let fraction = CGFloat(3 * (1 - t) * t * t + t * t * t)
        return CGRect(
            x: start.minX + (end.minX - start.minX) * fraction,
            y: start.minY + (end.minY - start.minY) * fraction,
            width: start.width + (end.width - start.width) * fraction,
            height: start.height + (end.height - start.height) * fraction
        )
    }
}
