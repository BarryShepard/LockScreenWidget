import AppKit

/// Shared vector silhouette for the menu bar and app icon.
enum StatusIcon {
    static func path() -> NSBezierPath {
        let shape = NSBezierPath()
        shape.move(to: NSPoint(x: 5, y: 1))
        shape.line(to: NSPoint(x: 13, y: 1))
        shape.line(to: NSPoint(x: 13, y: 5))
        shape.curve(to: NSPoint(x: 16, y: 10), controlPoint1: NSPoint(x: 15, y: 6), controlPoint2: NSPoint(x: 16, y: 7))
        shape.curve(to: NSPoint(x: 9, y: 17), controlPoint1: NSPoint(x: 16, y: 14), controlPoint2: NSPoint(x: 13, y: 17))
        shape.curve(to: NSPoint(x: 2, y: 10), controlPoint1: NSPoint(x: 5, y: 17), controlPoint2: NSPoint(x: 2, y: 14))
        shape.curve(to: NSPoint(x: 5, y: 5), controlPoint1: NSPoint(x: 2, y: 7), controlPoint2: NSPoint(x: 3, y: 6))
        shape.close()
        shape.windingRule = .evenOdd
        shape.appendOval(in: NSRect(x: 4, y: 7, width: 4, height: 4))
        shape.appendOval(in: NSRect(x: 10, y: 7, width: 4, height: 4))
        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: 9, y: 7))
        nose.line(to: NSPoint(x: 7.5, y: 4.5))
        nose.line(to: NSPoint(x: 10.5, y: 4.5))
        nose.close()
        shape.append(nose)
        for x in [7.0, 10.0] { shape.appendRect(NSRect(x: x, y: 1, width: 1, height: 2.5)) }
        return shape
    }

    static func skull() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            path().fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Следующий конец света"
        return image
    }
}
