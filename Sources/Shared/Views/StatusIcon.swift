import AppKit

/// A small, clean version of the hand-printed Mice app mark.
/// Top-left drawing coordinates keep the running pose identical in the menu bar.
enum StatusIcon {
    static func path() -> NSBezierPath {
        let shape = NSBezierPath()
        shape.move(to: NSPoint(x: 1.5, y: 6))
        shape.curve(to: NSPoint(x: 8, y: 5.6), controlPoint1: NSPoint(x: 2, y: 5.4), controlPoint2: NSPoint(x: 6, y: 5.6))
        shape.curve(to: NSPoint(x: 11.5, y: 1), controlPoint1: NSPoint(x: 8.8, y: 2.6), controlPoint2: NSPoint(x: 9.8, y: 1))
        shape.curve(to: NSPoint(x: 16, y: 4.5), controlPoint1: NSPoint(x: 15, y: 0.3), controlPoint2: NSPoint(x: 16.6, y: 2.6))
        shape.curve(to: NSPoint(x: 12.4, y: 7.8), controlPoint1: NSPoint(x: 16, y: 7), controlPoint2: NSPoint(x: 14.6, y: 8))
        shape.curve(to: NSPoint(x: 15.9, y: 12.8), controlPoint1: NSPoint(x: 14.7, y: 9.5), controlPoint2: NSPoint(x: 15.8, y: 11))
        shape.line(to: NSPoint(x: 17, y: 12.4))
        shape.curve(to: NSPoint(x: 18.9, y: 16.7), controlPoint1: NSPoint(x: 17.7, y: 12.3), controlPoint2: NSPoint(x: 18.5, y: 15.5))
        shape.curve(to: NSPoint(x: 17.4, y: 17.5), controlPoint1: NSPoint(x: 19.2, y: 17.7), controlPoint2: NSPoint(x: 18, y: 18))
        shape.line(to: NSPoint(x: 15.8, y: 15.3))
        shape.curve(to: NSPoint(x: 9, y: 17), controlPoint1: NSPoint(x: 14.6, y: 18.1), controlPoint2: NSPoint(x: 11.3, y: 18.2))
        shape.line(to: NSPoint(x: 5.3, y: 18))
        shape.curve(to: NSPoint(x: 4.2, y: 17.4), controlPoint1: NSPoint(x: 4.8, y: 18.2), controlPoint2: NSPoint(x: 4.5, y: 18))
        shape.line(to: NSPoint(x: 2.8, y: 14.4))
        shape.curve(to: NSPoint(x: 4.3, y: 13.6), controlPoint1: NSPoint(x: 2.2, y: 13.2), controlPoint2: NSPoint(x: 3.6, y: 12.7))
        shape.line(to: NSPoint(x: 5.5, y: 15.5))
        shape.line(to: NSPoint(x: 7.2, y: 12.8))
        shape.curve(to: NSPoint(x: 1.5, y: 6), controlPoint1: NSPoint(x: 5.5, y: 11.1), controlPoint2: NSPoint(x: 2.2, y: 7.5))
        shape.close()
        return shape
    }

    static func mouse() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let scale = NSAffineTransform()
            scale.scaleX(by: 22 / 24, yBy: 18 / 20)
            scale.concat()
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 15.4, y: 12.1))
            tail.curve(to: NSPoint(x: 20, y: 6), controlPoint1: NSPoint(x: 20.5, y: 13), controlPoint2: NSPoint(x: 16.2, y: 7.6))
            tail.curve(to: NSPoint(x: 21.1, y: 8.5), controlPoint1: NSPoint(x: 24, y: 3.9), controlPoint2: NSPoint(x: 23, y: 10.5))
            tail.curve(to: NSPoint(x: 22.7, y: 1.1), controlPoint1: NSPoint(x: 18.3, y: 7.1), controlPoint2: NSPoint(x: 20.2, y: 2.4))
            tail.lineWidth = 1.25
            tail.lineCapStyle = .round
            tail.lineJoinStyle = .round
            NSColor.black.setStroke()
            tail.stroke()
            NSColor.black.setFill()
            path().fill()
            // The eye is transparent, so template tint works on either bar appearance.
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            NSBezierPath(ovalIn: NSRect(x: 4.3, y: 6.6, width: 1.9, height: 1.9)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mice"
        return image
    }
}
