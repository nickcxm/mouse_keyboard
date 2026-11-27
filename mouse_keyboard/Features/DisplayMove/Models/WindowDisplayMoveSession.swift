import ApplicationServices
import CoreGraphics

struct WindowDisplayMoveSession {
    let processIdentifier: pid_t
    let window: AXUIElement
    let appName: String
    let windowFrame: CGRect
    let targets: [WindowDisplayMoveTarget]
}
