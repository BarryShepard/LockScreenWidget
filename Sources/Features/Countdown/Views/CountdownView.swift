import AppKit

final class CountdownView: NSView {
    struct TextRun {
        let text: String
        let attributes: [NSAttributedString.Key: Any]
        let frame: NSRect
    }
    private(set) var content = CountdownDisplayModel()
    private(set) var settings = EditorSettingsModel()
    private(set) var selectedIndices: Set<Int> = []
    private var marquee: NSRect?
    let isOverlay: Bool
    private(set) var drawCount = 0
    var previewScreenSize = NSSize(width: 1512, height: 982)
    var onMouseDown: ((NSPoint, Bool) -> Bool)?
    var onMouseDragged: ((NSPoint, Bool) -> Void)?
    var onMouseUp: (() -> Void)?
    var onKeyDown: ((UInt16, Bool) -> Bool)?
    private var pushedDragCursor = false

    init(overlay: Bool) {
        isOverlay = overlay
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { !isOverlay }

    func render(content: CountdownDisplayModel, settings: EditorSettingsModel,
                selectedIndices: Set<Int> = [], marquee: NSRect? = nil) {
        self.content = content
        self.settings = settings
        self.selectedIndices = selectedIndices
        self.marquee = marquee
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard !isOverlay else { return }
        window?.makeFirstResponder(self)
        pushedDragCursor = onMouseDown?(convert(event.locationInWindow, from: nil),
                                       event.modifierFlags.contains(.shift)) ?? false
        if pushedDragCursor { NSCursor.closedHand.push() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard !isOverlay else { return }
        onMouseDragged?(convert(event.locationInWindow, from: nil), event.modifierFlags.contains(.shift))
    }
    override func mouseUp(with event: NSEvent) {
        guard !isOverlay else { return }
        if pushedDragCursor { NSCursor.pop(); pushedDragCursor = false }
        onMouseUp?()
    }
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event.keyCode, event.modifierFlags.contains(.shift)) != true { super.keyDown(with: event) }
    }

    func canvasFrame(in bounds: NSRect) -> NSRect {
        guard !isOverlay else { return bounds }
        let scale = min(max(1, bounds.width - 32) / previewScreenSize.width,
                        max(1, bounds.height - 32) / previewScreenSize.height)
        let size = NSSize(width: previewScreenSize.width * scale, height: previewScreenSize.height * scale)
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        if !isOverlay {
            NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
            bounds.fill()
            NSColor.black.setFill()
            canvasFrame(in: bounds).fill()
            NSColor.white.withAlphaComponent(0.15).setStroke()
            NSBezierPath(rect: canvasFrame(in: bounds)).stroke()
        }
        let runs = layout(in: bounds)
        for (index, run) in runs.enumerated() {
            let measuredHeight = textHeight(run.text, attributes: run.attributes, width: run.frame.width)
            let freeHeight = max(0, run.frame.height - measuredHeight)
            let alignment = settings.typography[index].verticalAlignment
            var textFrame = run.frame
            textFrame.origin.y += freeHeight * CGFloat(alignment) / 2
            textFrame.size.height -= freeHeight * CGFloat(alignment) / 2
            (run.text as NSString).draw(with: textFrame, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: run.attributes)
        }
        if !isOverlay {
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            for index in selectedIndices where runs.indices.contains(index) {
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

    func layout(in bounds: NSRect, settings suppliedSettings: EditorSettingsModel? = nil) -> [TextRun] {
        let settings = suppliedSettings ?? self.settings
        let offsets = settings.offsets
        let area = canvasFrame(in: bounds)
        let scale = min(area.width / 1512, area.height / 982)
        let availableWidth = max(1, area.width * 0.88 - 32 * scale)
        let texts = [content.title, content.counter, content.information]
        var runs: [TextRun] = []
        var defaultY: CGFloat = 10 * scale
        for index in visibleBlockIndices(in: settings) {
            var typography = settings.typography[index]
            if index == 1, !content.usesCountdown {
                // A period is a label, never a fabricated ticking deadline.
                typography.size = min(typography.size, 42)
            }
            let attributes = style(typography, scale: scale, digits: index == 1 && content.usesCountdown)
            let text = texts[index]
            let measuredWidth = (text as NSString).size(withAttributes: attributes).width
            let preferredWidth: CGFloat = index == 0 ? 740 : (index == 1 ? 620 : 810)
            let width = min(availableWidth, max(preferredWidth * scale, ceil(measuredWidth) + 4))
            let textHeight = self.textHeight(text, attributes: attributes, width: width)
            // A text box gives horizontal and vertical text alignment a visible effect.
            let minimumHeight: CGFloat = index == 0 ? 0 : (index == 1 ? 150 : 130)
            let height = min(area.height, max(textHeight, minimumHeight * scale))
            let baseY = defaultY
            if index == 0 { defaultY += textHeight }
            else if index == 1 { defaultY += height + 24 * scale }
            var frame = NSRect(x: area.midX - width / 2 + offsets[index * 2] * area.width,
                               y: area.minY + area.height * 0.065 + baseY + offsets[index * 2 + 1] * area.height,
                               width: width, height: height)
            frame.origin.x = min(max(area.minX, frame.minX), max(area.minX, area.maxX - frame.width))
            frame.origin.y = min(max(area.minY, frame.minY), max(area.minY, area.maxY - frame.height))
            runs.append(TextRun(text: text, attributes: attributes, frame: frame))
        }
        return runs
    }

    private func style(_ typography: BlockTypographyModel, scale: CGFloat, digits: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = [NSTextAlignment.left, .center, .right][typography.alignment]
        if typography.lineHeight > 0 {
            paragraph.minimumLineHeight = typography.lineHeight * scale
            paragraph.maximumLineHeight = typography.lineHeight * scale
        }
        return [.font: makeTypographyFont(typography, scale: scale, digits: digits),
                .foregroundColor: NSColor.white.withAlphaComponent(0.60),
                .kern: typography.spacing / 100 * typography.size * scale, .paragraphStyle: paragraph]
    }

    private func textHeight(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        let measured = (text as NSString).boundingRect(with: NSSize(width: width, height: 10000),
              options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).height
        let font = attributes[.font] as! NSFont
        let natural = ceil(font.ascender - font.descender + font.leading)
        let paragraph = attributes[.paragraphStyle] as! NSParagraphStyle
        // Line spacing may be tighter than the glyphs; retain ink room for the last line.
        let inkOverflow = paragraph.maximumLineHeight > 0 ? max(0, natural - paragraph.maximumLineHeight) : 0
        return max(natural, ceil(measured + inkOverflow)) + 2
    }
}
