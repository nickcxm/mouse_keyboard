import AppKit
import QuartzCore

final class ModeHUDController {
    private enum Config {
        static let size = NSSize(width: 340, height: 96)
        static let topOffset: CGFloat = 118
        static let cornerRadius: CGFloat = 20

        static let fadeInDuration: TimeInterval = 0.30
        static let fadeOutDuration: TimeInterval = 0.36
        static let visibleDuration: TimeInterval = 1.0
        static let enterOffsetY: CGFloat = -8
        static let exitOffsetY: CGFloat = 8

        static let textHeight: CGFloat = 30
    }

    private var hudWindow: NSWindow?
    private var messageLabel: NSTextField?
    private var statusDotLayer: CAShapeLayer?
    private var hideWorkItem: DispatchWorkItem?

    func show(message: String, enabled: Bool) {
        let window = makeWindowIfNeeded()
        guard let label = messageLabel else {
            return
        }

        hideWorkItem?.cancel()

        let accentColor: NSColor = enabled ? .systemGreen : .systemGray
        label.stringValue = message
        label.textColor = accentColor
        statusDotLayer?.fillColor = accentColor.cgColor

        let finalFrame = targetFrame()
        var startFrame = finalFrame
        startFrame.origin.y += Config.enterOffsetY

        if !window.isVisible {
            window.alphaValue = 0
            window.setFrame(startFrame, display: false)
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = Config.fadeInDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
                window.animator().setFrame(finalFrame, display: false)
            }
        } else {
            window.setFrame(finalFrame, display: false)
            window.alphaValue = 1
        }

        scheduleHide(window: window, fromFrame: finalFrame)
    }

    private func scheduleHide(window: NSWindow, fromFrame: NSRect) {
        let workItem = DispatchWorkItem { [weak self, weak window] in
            guard let self, let window else {
                return
            }

            var endFrame = fromFrame
            endFrame.origin.y += Config.exitOffsetY

            NSAnimationContext.runAnimationGroup { context in
                context.duration = Config.fadeOutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                context.completionHandler = {
                    window.orderOut(nil)
                }
                window.animator().alphaValue = 0
                window.animator().setFrame(endFrame, display: false)
            }
        }

        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.visibleDuration, execute: workItem)
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let existing = hudWindow {
            updateLayerFramesIfNeeded(for: existing)
            return existing
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Config.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = NSView(frame: NSRect(origin: .zero, size: Config.size))
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = Config.cornerRadius
        rootView.layer?.masksToBounds = true

        let blurView = NSVisualEffectView(frame: rootView.bounds)
        blurView.material = .hudWindow
        blurView.blendingMode = .withinWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        rootView.addSubview(blurView)

        if let layer = rootView.layer {
            let fillGradient = CAGradientLayer()
            fillGradient.frame = rootView.bounds
            fillGradient.colors = [
                NSColor.white.withAlphaComponent(0.15).cgColor,
                NSColor.white.withAlphaComponent(0.04).cgColor,
                NSColor.black.withAlphaComponent(0.13).cgColor
            ]
            fillGradient.startPoint = CGPoint(x: 0.12, y: 1.0)
            fillGradient.endPoint = CGPoint(x: 0.92, y: 0.0)
            layer.addSublayer(fillGradient)

            let highlight = CAShapeLayer()
            highlight.path = CGPath(ellipseIn: CGRect(x: 44, y: Config.size.height - 48, width: 252, height: 58), transform: nil)
            highlight.fillColor = NSColor.white.withAlphaComponent(0.08).cgColor
            layer.addSublayer(highlight)

        }

        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 21, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = true
        label.frame = centeredLabelFrame(in: rootView.bounds)
        rootView.addSubview(label)

        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: Config.size.width - 30, y: Config.size.height - 24, width: 8, height: 8), transform: nil)
        dot.fillColor = NSColor.systemGreen.cgColor
        rootView.layer?.addSublayer(dot)

        messageLabel = label
        statusDotLayer = dot
        window.contentView = rootView
        hudWindow = window
        return window
    }

    private func updateLayerFramesIfNeeded(for window: NSWindow) {
        guard let rootView = window.contentView else {
            return
        }

        messageLabel?.frame = centeredLabelFrame(in: rootView.bounds)
    }

    private func targetFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: Config.size)
        }

        return NSRect(
            x: screen.frame.midX - (Config.size.width / 2),
            y: screen.frame.maxY - Config.size.height - Config.topOffset,
            width: Config.size.width,
            height: Config.size.height
        )
    }

    private func centeredLabelFrame(in bounds: NSRect) -> NSRect {
        let width = max(bounds.width - 36, 120)
        let x = (bounds.width - width) / 2
        let y = (bounds.height - Config.textHeight) / 2
        return NSRect(x: x, y: y, width: width, height: Config.textHeight)
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            let type = element(at: index, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}
