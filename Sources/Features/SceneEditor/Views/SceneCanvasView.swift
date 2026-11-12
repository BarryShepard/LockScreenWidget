import AppKit

private final class SceneInputView: NSTextView {
    var onWidthGesture: ((NSEvent, Int, Int) -> Void)?
    var onHistoryStart: (() -> Void)?
    var onHistoryEnd: ((Bool, Bool) -> Void)?
    var contentClip: CGRect?
    override func draw(_ dirtyRect: NSRect) {
        guard let contentClip else { super.draw(dirtyRect); return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: contentClip).addClip()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
    private var widthSide = 0
    func cancelWidthGesture() { widthSide = 0 }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let origin = convert(CGPoint.zero, to: nil)
        let unit = convert(CGPoint(x: 1, y: 0), to: nil)
        let hit: CGFloat = 6 / max(0.0001, hypot(unit.x-origin.x, unit.y-origin.y))
        widthSide = p.x <= bounds.minX + hit ? -1 : (p.x >= bounds.maxX - hit ? 1 : 0)
        if widthSide != 0 && !hasMarkedText() { onWidthGesture?(event, widthSide, 0) } else { widthSide = 0; super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if widthSide != 0 { onWidthGesture?(event, widthSide, 1) } else { super.mouseDragged(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if widthSide != 0 { onWidthGesture?(event, widthSide, 2); widthSide = 0 } else { super.mouseUp(with: event) }
    }
    private let localHistory = UndoManager()
    override var undoManager: UndoManager? { localHistory }
    @objc func undo(_ sender: Any?) { let before = string; onHistoryStart?(); localHistory.undo(); onHistoryEnd?(true, string != before) }
    @objc func redo(_ sender: Any?) { let before = string; onHistoryStart?(); localHistory.redo(); onHistoryEnd?(false, string != before) }
    func registerWidthHistory(_ action: @escaping (Bool) -> Void) {
        localHistory.registerUndo(withTarget: self) { target in
            target.registerWidthHistory(action)
            action(target.localHistory.isUndoing)
        }
    }
    func addWidthHistory(_ action: @escaping (Bool) -> Void) {
        breakUndoCoalescing()
        localHistory.beginUndoGrouping()
        registerWidthHistory(action)
        localHistory.endUndoGrouping()
    }
}

private final class SceneTextContainerView: NSView {
    override var isFlipped: Bool { true }
}

enum SceneCanvasAction {
    case armText, createText, editSelection, finishText, cancel, delete, selectAll
    case copy, cut, paste, duplicate, undo, redo, forward, backward, front, back
}

struct SceneCanvasHandle: Equatable {
    let point: CGPoint
    let rotation: Bool
}

struct SceneCanvasPresentation: Equatable {
    var content = SceneRenderContent(canvasSize: CGSize(width: 1, height: 1), elements: [])
    var selectionOutlines: [[CGPoint]] = []
    var handles: [SceneCanvasHandle] = []
    var selectionBounds: CGRect?
    var marquee: CGRect?
    var dropOutline: [CGPoint]?
    var badge: String?
    var textTool = false
    var editingID: UUID?
}

struct SceneTextInputPresentation {
    let frame: CGRect
    let rotation: Double
    let opacity: Double
    let scaleX: CGFloat, scaleY: CGFloat
    let yOffset: CGFloat
    var xInset: CGFloat = 0
    var contentClip: CGRect? = nil
    let attributes: [NSAttributedString.Key: Any]
    let color: NSColor
}

final class SceneCanvasView: NSView, NSTextViewDelegate {
    var onCursor: ((CGPoint) -> NSCursor?)?
    private var cursorTracking: NSTrackingArea?
    var onAction: ((SceneCanvasAction) -> Void)?
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onTextChange: ((String) -> Void)?
    var onTextWidthGesture: ((NSEvent, Int, Int) -> Void)?
    var onTextHistoryStart: (() -> Void)?
    var onTextHistoryEnd: ((Bool) -> Void)?
    var onLayout: (() -> Void)?
    var onDragUpdate: ((CGPoint?) -> Bool)?
    var onDrop: ((NSPasteboard, CGPoint) -> Bool)?
    var guides = true { didSet { needsDisplay = true } }
    var clock = true { didSet { needsDisplay = true } }
    private let renderer = SceneRenderer()
    private var presentation = SceneCanvasPresentation()
    var renderedContent: SceneRenderContent { presentation.content }
    private var input: SceneInputView?
    private var inputContainer: SceneTextContainerView?
    var viewport: SceneViewport {
        SceneViewport(size: presentation.content.canvasSize, in: bounds.insetBy(dx: 22, dy: 22))
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Холст")
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }
    required init?(coder: NSCoder) { fatalError() }

    func refreshContent(_ content: SceneRenderContent) {
        guard content != presentation.content else { return }
        presentation.content = content
        needsDisplay = true
    }
    func render(_ presentation: SceneCanvasPresentation) {
        guard presentation != self.presentation else { return }
        let cursorChanged = self.presentation.textTool != presentation.textTool || self.presentation.handles != presentation.handles
        self.presentation = presentation
        if cursorChanged { window?.invalidateCursorRects(for: self) }
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); cursorTracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        let point = scenePoint(event.locationInWindow)
        (presentation.textTool ? NSCursor.crosshair : (onCursor?(point) ?? .arrow)).set()
    }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    func cancelTextWidthGesture() { input?.cancelWidthGesture() }
    func registerTextWidthHistory(_ action: @escaping (Bool) -> Void) { input?.addWidthHistory(action) }
    func focus() { window?.makeFirstResponder(self) }
    func createCenteredText() { onAction?(.createText) }
    func editSelection() { onAction?(.editSelection) }
    func finishText() { onAction?(.finishText) }
    func scenePoint(_ point: CGPoint) -> CGPoint { viewport.scenePoint(convert(point, from: nil)) }
    func contains(_ point: CGPoint) -> Bool { viewport.rect.contains(convert(point, from: nil)) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let viewport = viewport
        NSColor(srgbRed: 0.12, green: 0.15, blue: 0.19, alpha: 1).setFill()
        viewport.rect.fill()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: viewport.rect).addClip()
        if guides { drawGuides(in: viewport.rect) }
        renderer.draw(presentation.content, in: viewport, excluding: presentation.editingID)
        for outline in presentation.selectionOutlines { drawOutline(outline, color: .controlAccentColor) }
        if let bounds = presentation.selectionBounds {
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: viewport.viewRect(bounds)).stroke()
        }
        for handle in presentation.handles where !handle.rotation {
            let p = viewport.viewPoint(handle.point), r = CGRect(x: p.x-3.5, y: p.y-3.5, width: 7, height: 7)
            NSColor.white.setFill(); r.fill(); NSColor.controlAccentColor.setStroke(); r.frame()
        }
        if let marquee = presentation.marquee {
            let box = viewport.viewRect(marquee)
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            box.fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: box).stroke()
        }
        if let outline = presentation.dropOutline { drawOutline(outline, color: .systemOrange) }
        if let text = presentation.badge {
            badge(text, at: CGPoint(x: viewport.rect.minX + 12, y: viewport.rect.minY + 12))
        }
    }
    private func drawOutline(_ points: [CGPoint], color: NSColor) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: viewport.viewPoint(first))
        for point in points.dropFirst() { path.line(to: viewport.viewPoint(point)) }
        path.close()
        color.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
    private func badge(_ text: String, at point: CGPoint) {
        let s = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                             .foregroundColor: NSColor.white])
        let box = CGRect(origin: point, size: CGSize(width: s.size().width+16, height: s.size().height+8))
        NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        s.draw(at: CGPoint(x: point.x+8, y: point.y+4))
    }
    private func drawGuides(in r: CGRect) {
        let color = NSColor.white.withAlphaComponent(0.33)
        if clock {
            let s = NSAttributedString(string: "09:41", attributes: [.font: NSFont.systemFont(ofSize: max(12, r.height*0.105),
                                                                                               weight: .medium), .foregroundColor: color])
            s.draw(at: CGPoint(x: r.midX-s.size().width/2, y: r.minY+r.height*0.075))
        }
        color.setStroke()
        let d = r.height*0.065
        NSBezierPath(ovalIn: CGRect(x: r.midX-d/2, y: r.maxY-r.height*0.17, width: d, height: d)).stroke()
        let bar = CGRect(x: r.midX-r.width*0.07, y: r.maxY-r.height*0.09, width: r.width*0.14, height: r.height*0.027)
        NSBezierPath(roundedRect: bar, xRadius: bar.height/2, yRadius: bar.height/2).stroke()
    }

    func beginText(_ text: String, presentation: SceneTextInputPresentation, click: CGPoint?) {
        let field = SceneInputView(frame: .zero)
        field.isRichText = false; field.importsGraphics = false; field.allowsUndo = true
        field.isAutomaticQuoteSubstitutionEnabled = false; field.drawsBackground = false
        field.textContainerInset = .zero; field.textContainer?.lineFragmentPadding = 0
        field.isHorizontallyResizable = false; field.isVerticallyResizable = false
        field.textContainer?.widthTracksTextView = true; field.textContainer?.heightTracksTextView = false
        field.textContainer?.containerSize.height = CGFloat.greatestFiniteMagnitude

        field.string = text
        field.onHistoryStart = { [weak self] in self?.onTextHistoryStart?() }
        field.onHistoryEnd = { [weak self, weak field] undo, changed in
            if changed, let field, !field.hasMarkedText() { self?.onTextChange?(field.string) }
            self?.onTextHistoryEnd?(undo)
        }
        field.onWidthGesture = { [weak self] event, side, phase in self?.onTextWidthGesture?(event, side, phase) }
        field.delegate = self
        field.textStorage?.setAttributes(presentation.attributes, range: NSRange(location: 0, length: (text as NSString).length))
        field.typingAttributes = presentation.attributes
        field.insertionPointColor = presentation.color
        input = field
        let container = SceneTextContainerView(frame: .zero)
        inputContainer = container
        addSubview(container)
        container.addSubview(field)
        updateText(presentation)
        window?.makeFirstResponder(field)
        let end = (text as NSString).length
        let cursor = click.map { field.characterIndexForInsertion(at: field.convert($0, from: nil)) } ?? end
        field.setSelectedRange(NSRange(location: min(cursor, end), length: 0))
        needsDisplay = true
    }
    func updateText(_ presentation: SceneTextInputPresentation) {
        guard let input else { return }
        let viewport = viewport
        guard let container = inputContainer else { return }
        container.frameCenterRotation = 0
        container.frame = viewport.viewRect(presentation.frame)
        let logicalSize = CGSize(width: presentation.frame.width / presentation.scaleX, height: presentation.frame.height / presentation.scaleY)
        container.bounds = CGRect(origin: .zero, size: logicalSize)
        input.frame = CGRect(origin: .zero, size: logicalSize)
        input.textContainerInset = CGSize(width: presentation.xInset, height: presentation.yOffset)
        input.contentClip = presentation.contentClip
        input.needsDisplay = true
        container.frameCenterRotation = presentation.rotation
        // AppKit adjusts the frame origin when bounds scale or rotation changes.
        // Anchor the transformed local center to the renderer’s scene center.
        let center = convert(CGPoint(x: logicalSize.width/2, y: logicalSize.height/2), from: container)
        let desired = viewport.viewPoint(CGPoint(x: presentation.frame.midX, y: presentation.frame.midY))
        container.setFrameOrigin(CGPoint(x: container.frame.origin.x + desired.x-center.x, y: container.frame.origin.y + desired.y-center.y))
        input.alphaValue = max(0.2, presentation.opacity)
    }
    func endText() {
        input?.delegate = nil
        inputContainer?.removeFromSuperview()
        inputContainer = nil
        input = nil
        needsDisplay = true
    }
    override func layout() { super.layout(); onLayout?() }
    func textDidChange(_ notification: Notification) {
        guard let input, !input.hasMarkedText() else { return }
        onTextChange?(input.string)
    }
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(cancelOperation(_:)) { onAction?(.cancel); return true }
        return false
    }
    func textDidEndEditing(_ notification: Notification) { finishText() }
    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(event) }
    override func keyDown(with event: NSEvent) {
        if input != nil || onKeyDown?(event) != true { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onAction?(.cancel) }
    override func deleteBackward(_ sender: Any?) { onAction?(.delete) }
    override func selectAll(_ sender: Any?) { onAction?(.selectAll) }
    @objc func copy(_ sender: Any?) { onAction?(.copy) }
    @objc func cut(_ sender: Any?) { onAction?(.cut) }
    @objc func paste(_ sender: Any?) { onAction?(.paste) }
    @objc func duplicate(_ sender: Any?) { onAction?(.duplicate) }
    @objc func undo(_ sender: Any?) { onAction?(.undo) }
    @objc func redo(_ sender: Any?) { onAction?(.redo) }
    @objc func bringForward(_ sender: Any?) { onAction?(.forward) }
    @objc func sendBackward(_ sender: Any?) { onAction?(.backward) }
    @objc func bringToFront(_ sender: Any?) { onAction?(.front) }
    @objc func sendToBack(_ sender: Any?) { onAction?(.back) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = contains(sender.draggingLocation) ? scenePoint(sender.draggingLocation) : nil
        return onDragUpdate?(point) == true ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { _ = onDragUpdate?(nil) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard, scenePoint(sender.draggingLocation)) ?? false
    }
}
