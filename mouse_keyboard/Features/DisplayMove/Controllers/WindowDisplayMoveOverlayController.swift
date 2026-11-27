import AppKit
import SwiftUI

final class WindowDisplayMoveOverlayController {
    private enum Config {
        static let itemWidth: CGFloat = 176
        static let horizontalPadding: CGFloat = 56
        static let minimumWidth: CGFloat = 440
        static let height: CGFloat = 360
        static let screenMargin: CGFloat = 24
        static let fadeDuration: TimeInterval = 0.16
    }

    private var window: NSPanel?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(session: WindowDisplayMoveSession) {
        hide()

        let targetScreen = screen(containing: session.windowFrame) ?? NSScreen.main
        let panelSize = windowSize(targetCount: session.targets.count, screen: targetScreen)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: WindowDisplayMoveOverlayView(
                appName: session.appName,
                targets: session.targets
            )
        )

        panel.setFrame(targetFrame(for: session.windowFrame, size: panelSize, screen: targetScreen), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.fadeDuration
            panel.animator().alphaValue = 1
        }
        window = panel
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func windowSize(targetCount: Int, screen: NSScreen?) -> NSSize {
        let desiredWidth = max(Config.minimumWidth, CGFloat(targetCount) * Config.itemWidth + Config.horizontalPadding)
        let availableWidth = max(1, (screen?.visibleFrame.width ?? desiredWidth) - Config.screenMargin * 2)
        let availableHeight = max(1, (screen?.visibleFrame.height ?? Config.height) - Config.screenMargin * 2)
        return NSSize(width: min(desiredWidth, availableWidth), height: min(Config.height, availableHeight))
    }

    private func targetFrame(for windowFrame: CGRect, size: NSSize, screen: NSScreen?) -> NSRect {
        guard
            let screen,
            let primaryScreen = NSScreen.screens.first(where: { displayID(for: $0) == CGMainDisplayID() })
        else {
            return NSRect(origin: .zero, size: size)
        }

        let appKitWindowCenter = CGPoint(
            x: windowFrame.midX,
            y: primaryScreen.frame.maxY - windowFrame.midY
        )
        let proposedOrigin = CGPoint(
            x: appKitWindowCenter.x - size.width / 2,
            y: appKitWindowCenter.y - size.height / 2
        )
        let visibleFrame = screen.visibleFrame.insetBy(dx: Config.screenMargin, dy: Config.screenMargin)
        let origin = CGPoint(
            x: min(max(proposedOrigin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(proposedOrigin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
        return NSRect(origin: origin, size: size)
    }

    private func screen(containing windowFrame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(cgBounds(for: lhs), windowFrame)
                < intersectionArea(cgBounds(for: rhs), windowFrame)
        }
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func cgBounds(for screen: NSScreen) -> CGRect {
        guard let displayID = displayID(for: screen) else {
            return .null
        }
        return CGDisplayBounds(displayID)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
