import AppKit

enum StatusBarIconFactory {
    static func makeIcon(isActive: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        if isActive {
            drawKeyboardIcon()
        } else {
            drawMouseIcon()
        }

        image.isTemplate = true
        return image
    }

    private static func drawKeyboardIcon() {
        let keyboardRect = NSRect(x: 2.0, y: 4.0, width: 14.0, height: 10.0)
        let keyboard = NSBezierPath(roundedRect: keyboardRect, xRadius: 2.2, yRadius: 2.2)
        keyboard.lineWidth = 1.5
        keyboard.stroke()

        for row in 0..<2 {
            for column in 0..<4 {
                let keyRect = NSRect(
                    x: 3.6 + (CGFloat(column) * 3.0),
                    y: 9.0 - (CGFloat(row) * 2.8),
                    width: 1.8,
                    height: 1.5
                )
                NSBezierPath(roundedRect: keyRect, xRadius: 0.4, yRadius: 0.4).fill()
            }
        }
    }

    private static func drawMouseIcon() {
        let mouseRect = NSRect(x: 4.2, y: 2.2, width: 9.6, height: 13.6)
        let mouse = NSBezierPath(roundedRect: mouseRect, xRadius: 4.8, yRadius: 4.8)
        mouse.lineWidth = 1.5
        mouse.stroke()

        let splitLine = NSBezierPath()
        splitLine.move(to: NSPoint(x: 9.0, y: 11.6))
        splitLine.line(to: NSPoint(x: 9.0, y: 8.0))
        splitLine.lineWidth = 1.4
        splitLine.stroke()

        let wheel = NSBezierPath(roundedRect: NSRect(x: 8.25, y: 9.6, width: 1.5, height: 1.8), xRadius: 0.6, yRadius: 0.6)
        wheel.fill()
    }
}
