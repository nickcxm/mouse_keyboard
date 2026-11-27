import CoreGraphics

struct WindowDisplayMoveTarget: Identifiable {
    let id: Int
    let displayID: CGDirectDisplayID
    let name: String
    let bounds: CGRect
    let visibleBounds: CGRect
    let isBuiltIn: Bool
    let containsCurrentWindow: Bool

    var aspectRatio: CGFloat {
        guard bounds.height > 0 else { return 16.0 / 9.0 }
        return bounds.width / bounds.height
    }
}
