import AppKit

enum AppFont {
    // Keep the font choice here so a custom face can replace the system font later.
    static func font(_ size: CGFloat, digits: Bool = false) -> NSFont {
        guard digits else { return NSFont.systemFont(ofSize: size, weight: .bold) }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }
}

final class CountdownView: NSView {
    struct TextRun {
        let text: String
        let attributes: [NSAttributedString.Key: Any]
        let frame: NSRect
    }
    var event: ApocalypseEvent? { didSet { needsDisplay = true } }
    var now = Date() { didSet { needsDisplay = true } }
    let isOverlay: Bool
    private(set) var drawCount = 0
    var onLayoutChange: (() -> Void)?
    var previewScreenSize = NSSize(width: 1512, height: 982)
    private var offsets = UserDefaults.standard.array(forKey: "elementOffsets") as? [Double] ?? [0, 0, 0, 0]
    private(set) var selectedIndices: Set<Int> = []
    private var dragStart = NSPoint.zero
    private var originalOffsets: [Double] = []
    private var originalFrames: [NSRect] = []
    private var draggingElements = false
    private var marquee: NSRect?
    private var selectionBeforeMarquee: Set<Int> = []
    private enum Axis { case horizontal, vertical }
    private var lockedAxis: Axis?

    func reloadPositions() {
        offsets = UserDefaults.standard.array(forKey: "elementOffsets") as? [Double] ?? [0, 0, 0, 0]
        if offsets.count != 4 || offsets.contains(where: { !$0.isFinite }) { offsets = [0, 0, 0, 0] }
        needsDisplay = true
    }

    func resetPositions() {
        offsets = [0, 0, 0, 0]
        savePositions()
    }

    private func savePositions() {
        UserDefaults.standard.set(offsets, forKey: "elementOffsets")
        needsDisplay = true
        onLayoutChange?()
    }

    private func canvas(in bounds: NSRect) -> NSRect {
        guard !isOverlay else { return bounds }
        let scale = min(max(1, bounds.width - 32) / previewScreenSize.width,
                        max(1, bounds.height - 32) / previewScreenSize.height)
        let size = NSSize(width: previewScreenSize.width * scale, height: previewScreenSize.height * scale)
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func mouseDown(with event: NSEvent) {
        beginInteraction(at: convert(event.locationInWindow, from: nil),
                         extendingSelection: event.modifierFlags.contains(.shift))
        if draggingElements { NSCursor.closedHand.push() }
    }

    func beginInteraction(at point: NSPoint, extendingSelection: Bool) {
        guard !isOverlay else { return }
        let runs = layout(in: bounds)
        let hit = runs.indices.reversed().first { runs[$0].frame.contains(point) }
        dragStart = point
        lockedAxis = nil
        marquee = nil
        if let index = hit {
            if extendingSelection { selectedIndices.insert(index) }
            else if !selectedIndices.contains(index) { selectedIndices = [index] }
            for selected in selectedIndices {
                moveElement(selected, to: NSPoint(x: offsets[selected * 2], y: offsets[selected * 2 + 1]))
            }
            originalOffsets = offsets
            originalFrames = layout(in: bounds).map(\.frame)
            draggingElements = true
        } else {
            draggingElements = false
            selectionBeforeMarquee = extendingSelection ? selectedIndices : []
            selectedIndices = selectionBeforeMarquee
            marquee = NSRect(origin: point, size: .zero)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragInteraction(to: convert(event.locationInWindow, from: nil),
                        constrainAxis: event.modifierFlags.contains(.shift))
    }

    func dragInteraction(to point: NSPoint, constrainAxis: Bool) {
        guard !isOverlay else { return }
        if marquee != nil {
            let rect = NSRect(x: min(point.x, dragStart.x), y: min(point.y, dragStart.y),
                              width: abs(point.x - dragStart.x), height: abs(point.y - dragStart.y))
            marquee = rect
            let runs = layout(in: bounds)
            let hits = runs.indices.filter { runs[$0].frame.intersects(rect) }
            selectedIndices = selectionBeforeMarquee.union(hits)
        } else if draggingElements {
            var dx = point.x - dragStart.x
            var dy = point.y - dragStart.y
            if constrainAxis {
                if lockedAxis == nil, max(abs(dx), abs(dy)) >= 3 {
                    lockedAxis = abs(dx) >= abs(dy) ? .horizontal : .vertical
                }
                // Wait for a clear direction before moving, then retain that axis.
                if lockedAxis == .horizontal { dy = 0 }
                else if lockedAxis == .vertical { dx = 0 }
                else { dx = 0; dy = 0 }
            } else { lockedAxis = nil }
            let area = canvas(in: bounds)
            guard area.width > 0, area.height > 0 else { return }
            // Clamp the shared translation, preserving spacing when a group reaches an edge.
            let frames = selectedIndices.map { originalFrames[$0] }
            let minDX = frames.map { area.minX - $0.minX }.max() ?? 0
            let maxDX = frames.map { area.maxX - $0.maxX }.min() ?? 0
            let minDY = frames.map { area.minY - $0.minY }.max() ?? 0
            let maxDY = frames.map { area.maxY - $0.maxY }.min() ?? 0
            dx = min(max(dx, minDX), maxDX)
            dy = min(max(dy, minDY), maxDY)
            for index in selectedIndices {
                offsets[index * 2] = originalOffsets[index * 2] + dx / area.width
                offsets[index * 2 + 1] = originalOffsets[index * 2 + 1] + dy / area.height
            }
        }
        needsDisplay = true
    }

    func moveElement(_ index: Int, to offset: NSPoint) {
        guard (0..<2).contains(index), offset.x.isFinite, offset.y.isFinite else { return }
        offsets[index * 2] = 0
        offsets[index * 2 + 1] = 0
        let base = layout(in: bounds)[index].frame
        let area = canvas(in: bounds)
        guard area.width > 0, area.height > 0 else { return }
        offsets[index * 2] = min(max(offset.x, (area.minX - base.minX) / area.width),
                                (area.maxX - base.maxX) / area.width)
        offsets[index * 2 + 1] = min(max(offset.y, (area.minY - base.minY) / area.height),
                                    (area.maxY - base.maxY) / area.height)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = draggingElements
        if wasDragging { NSCursor.pop() }
        draggingElements = false
        marquee = nil
        lockedAxis = nil
        if wasDragging { savePositions() }
        needsDisplay = true
    }

    init(overlay: Bool) {
        isOverlay = overlay
        super.init(frame: .zero)
        reloadPositions()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        if !isOverlay {
            NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
            bounds.fill()
            NSColor.black.setFill()
            canvas(in: bounds).fill()
            NSColor.white.withAlphaComponent(0.15).setStroke()
            NSBezierPath(rect: canvas(in: bounds)).stroke()
        }
        let runs = layout(in: bounds)
        for run in runs {
            (run.text as NSString).draw(with: run.frame, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: run.attributes)
        }
        if !isOverlay {
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            for index in selectedIndices {
                let path = NSBezierPath(rect: runs[index].frame.insetBy(dx: -3, dy: -3))
                path.lineWidth = 1
                path.stroke()
            }
            if let rect = marquee {
                NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
                rect.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
                NSBezierPath(rect: rect).stroke()
            }
        }
    }

    /// Reference: 1512 × 982 logical points, matching the supplied lock-screen mockup.
    static func overlayFrame(in screen: NSRect) -> NSRect {
        screen
    }

    func layout(in bounds: NSRect) -> [TextRun] {
        let area = canvas(in: bounds)
        let scale = min(area.width / 1512, area.height / 982)
        let availableWidth = area.width * 0.88 - 32 * scale
        let title = event?.title ?? "Новых предсказаний пока нет"
        let timer = event.map { Countdown.string(until: $0.target, now: now) } ?? "00:00:00"
        // The mockup uses white at 60% opacity, including over non-black wallpapers.
        let color = NSColor.white.withAlphaComponent(0.60)
        var titleSize = 26 * scale
        while (title as NSString).size(withAttributes: [.font: AppFont.font(titleSize)]).width > availableWidth && titleSize > 12 * scale {
            titleSize -= scale
        }
        var timerSize = 112 * scale
        while (timer as NSString).size(withAttributes: [.font: AppFont.font(timerSize, digits: true),
                                                       .kern: -0.02 * timerSize]).width > availableWidth && timerSize > 28 * scale {
            timerSize -= scale
        }
        let titleStyle = style(size: titleSize, color: color)
        let timerStyle = style(size: timerSize, color: color, kern: -0.02 * timerSize, digits: true)
        let titleHeight = textHeight(title, attributes: titleStyle, width: availableWidth)
        let timerHeight = textHeight(timer, attributes: timerStyle, width: availableWidth)
        let titleY = 10 * scale
        let runs = [
            TextRun(text: title, attributes: titleStyle,
                    frame: NSRect(x: (bounds.width - availableWidth) / 2, y: titleY,
                                  width: availableWidth, height: titleHeight)),
            TextRun(text: timer, attributes: timerStyle,
                    frame: NSRect(x: (bounds.width - availableWidth) / 2,
                                  y: titleY + titleHeight,
                                  width: availableWidth, height: timerHeight))
        ]
        return runs.enumerated().map { index, run in
            var frame = run.frame
            let textWidth = min(frame.width, ceil((run.text as NSString).size(withAttributes: run.attributes).width) + 4)
            frame.origin.x += (frame.width - textWidth) / 2
            frame.size.width = textWidth
            frame.origin.y += area.minY + area.height * 0.065 + offsets[index * 2 + 1] * area.height
            frame.origin.x += area.midX - bounds.width / 2 + offsets[index * 2] * area.width
            frame.origin.x = min(max(area.minX, frame.minX), max(area.minX, area.maxX - frame.width))
            frame.origin.y = min(max(area.minY, frame.minY), max(area.minY, area.maxY - frame.height))
            return TextRun(text: run.text, attributes: run.attributes, frame: frame)
        }
    }

    private func style(size: CGFloat, color: NSColor, kern: CGFloat = 0,
                       digits: Bool = false) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return [.font: AppFont.font(size, digits: digits), .foregroundColor: color,
                .kern: kern, .paragraphStyle: paragraph]
    }

    private func textHeight(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(with: NSSize(width: width, height: 2000),
              options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).height) + 2
    }
}
