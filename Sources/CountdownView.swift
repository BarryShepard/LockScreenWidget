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
    private(set) var settings = EditorSettings()
    private let preferences: UserDefaults
    private var offsets: [Double] {
        get { settings.offsets }
        set { settings.offsets = newValue }
    }
    var onSelectionChange: (() -> Void)?
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
        settings = EditorSettings.load(from: preferences)
        selectedIndices.formIntersection(settings.visibleIndices)
        needsDisplay = true
    }

    func resetPositions() {
        offsets = [0, 0, 0, 0, 0, 0]
        savePositions()
    }

    private func savePositions() {
        settings.save(to: preferences)
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
        window?.makeFirstResponder(self)
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
        onSelectionChange?()
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
            onSelectionChange?()
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
        guard settings.visibleIndices.contains(index), offset.x.isFinite, offset.y.isFinite else { return }
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

    override var acceptsFirstResponder: Bool { !isOverlay }

    func selectBlock(_ index: Int) {
        guard settings.visibleIndices.contains(index) else { return }
        selectedIndices = [index]
        needsDisplay = true
        onSelectionChange?()
    }

    func setTypography(_ typography: BlockTypography, for indices: Set<Int>) {
        for index in indices where settings.visibleIndices.contains(index) {
            var valid = typography
            valid.validate()
            settings.typography[index] = valid
        }
        savePositions()
    }

    func editSelectedTypography(_ edit: (inout BlockTypography) -> Void) {
        for index in selectedIndices {
            edit(&settings.typography[index])
            settings.typography[index].validate()
        }
        savePositions()
    }

    func setInformationVisible(_ visible: Bool) {
        settings.showInformation = visible
        selectedIndices.formIntersection(settings.visibleIndices)
        savePositions()
        onSelectionChange?()
    }

    /// Shared translation in preview points, preserving the group's relative arrangement.
    private func translateSelection(dx: CGFloat, dy: CGFloat) {
        guard !selectedIndices.isEmpty else { return }
        for index in selectedIndices { moveElement(index, to: NSPoint(x: offsets[index * 2], y: offsets[index * 2 + 1])) }
        let area = canvas(in: bounds)
        let runs = layout(in: bounds)
        let frames = selectedIndices.map { runs[$0].frame }
        let tx = min(max(dx, frames.map { area.minX - $0.minX }.max() ?? 0), frames.map { area.maxX - $0.maxX }.min() ?? 0)
        let ty = min(max(dy, frames.map { area.minY - $0.minY }.max() ?? 0), frames.map { area.maxY - $0.maxY }.min() ?? 0)
        guard area.width > 0, area.height > 0 else { return }
        for index in selectedIndices {
            offsets[index * 2] += tx / area.width
            offsets[index * 2 + 1] += ty / area.height
        }
        savePositions()
    }

    func nudgeSelection(x: CGFloat, y: CGFloat, largeStep: Bool = false) {
        let area = canvas(in: bounds)
        let reference = isOverlay ? bounds.size : previewScreenSize
        let step: CGFloat = largeStep ? 10 : 1
        translateSelection(dx: x * step * area.width / reference.width,
                           dy: y * step * area.height / reference.height)
    }

    func centerSelection(horizontal: Bool) {
        guard !selectedIndices.isEmpty else { return }
        let runs = layout(in: bounds)
        let group = selectedIndices.map { runs[$0].frame }.reduce(NSRect.null) { $0.union($1) }
        let area = canvas(in: bounds)
        translateSelection(dx: horizontal ? area.midX - group.midX : 0,
                           dy: horizontal ? 0 : area.midY - group.midY)
    }

    override func keyDown(with event: NSEvent) {
        let step = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123: nudgeSelection(x: -1, y: 0, largeStep: step)
        case 124: nudgeSelection(x: 1, y: 0, largeStep: step)
        case 125: nudgeSelection(x: 0, y: 1, largeStep: step)
        case 126: nudgeSelection(x: 0, y: -1, largeStep: step)
        case 53:
            selectedIndices = []
            needsDisplay = true
            onSelectionChange?()
        default: super.keyDown(with: event)
        }
    }

    init(overlay: Bool, preferences: UserDefaults = .standard) {
        isOverlay = overlay
        self.preferences = preferences
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
        let availableWidth = max(1, area.width * 0.88 - 32 * scale)
        let title = event?.title ?? "Новых предсказаний пока нет"
        let timer = event?.counterText(now: now) ?? "00:00:00"
        let information = event.map { $0.information + "\n\n" + $0.source }
            ?? "Все назначенные даты прошли. Планета продолжает работу."
        let texts = [title, timer, information]
        var runs: [TextRun] = []
        var defaultY: CGFloat = 10 * scale
        for index in settings.visibleIndices {
            var typography = settings.typography[index]
            if index == 1, event?.hasCountdown == false {
                // A period is a label, never a fabricated ticking deadline.
                typography.size = min(typography.size, 42)
            }
            let attributes = style(typography, scale: scale, digits: index == 1 && (event?.hasCountdown ?? true))
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

    private func style(_ typography: BlockTypography, scale: CGFloat, digits: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = [NSTextAlignment.left, .center, .right][typography.alignment]
        if typography.lineHeight > 0 {
            paragraph.minimumLineHeight = typography.lineHeight * scale
            paragraph.maximumLineHeight = typography.lineHeight * scale
        }
        return [.font: typography.font(scale: scale, digits: digits),
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
