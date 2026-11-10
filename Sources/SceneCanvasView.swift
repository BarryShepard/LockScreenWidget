import AppKit

/// The text system owns its own undo stack while typing; the canvas records the finished session once.
private final class SceneInputView: NSTextView {
    private let localHistory = UndoManager()
    override var undoManager: UndoManager? { localHistory }
    @objc func undo(_ sender: Any?) { localHistory.undo() }
    @objc func redo(_ sender: Any?) { localHistory.redo() }
}
final class SceneCanvasView: NSView, NSTextViewDelegate {
    let state: SceneEditingState
    let renderer: SceneRenderer
    var onPickReplacement: ((UUID) -> Void)?
    var onPaste: ((NSPasteboard, SceneImageDestination?) -> Bool)?
    var onError: ((String) -> Void)?
    var onRestoreTypedScene: (() -> Void)?
    var guides = true { didSet { needsDisplay = true } }
    var clock = true { didSet { needsDisplay = true } }
    private var textTool = false { didSet { window?.invalidateCursorRects(for: self); needsDisplay = true } }
    private var input: SceneInputView?
    private var editingID: UUID?
    private var initialText: SceneSnapshot?
    private var newText = false
    private var typed = false
    private var inputScale: CGFloat = 1
    private var minimumHeight: CGFloat = 1
    private var dragStart = CGPoint.zero, dragCurrent = CGPoint.zero
    private var original: SceneSnapshot?, moveBase: SceneSnapshot?
    private var downID: UUID?, shiftDown = false, optionDown = false, dragging = false
    private var axisX: Bool?
    private var drop: SceneImageDestination?
    private var viewport: SceneViewport {
        SceneViewport(size: state.scene.canvasSize, in: bounds.insetBy(dx: 22, dy: 22))
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(state: SceneEditingState, store: SceneStore) {
        self.state = state; renderer = SceneRenderer(store: store)
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Холст")
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func resetCursorRects() {
        super.resetCursorRects()
        if textTool { addCursorRect(viewport.rect, cursor: .crosshair) }
    }
    func focus() { window?.makeFirstResponder(self) }
    func armText() { finishText(); textTool = true; focus() }
    func createCenteredText() {
        finishText()
        beginNewText(at: state.insertionPoint, width: nil)
    }
    private func scenePoint(_ windowPoint: CGPoint) -> CGPoint { viewport.scenePoint(convert(windowPoint, from: nil)) }
    private var dragRect: CGRect {
        CGRect(x: min(dragStart.x, dragCurrent.x), y: min(dragStart.y, dragCurrent.y),
               width: abs(dragStart.x-dragCurrent.x), height: abs(dragStart.y-dragCurrent.y))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        let v = viewport
        NSColor(srgbRed: 0.12, green: 0.15, blue: 0.19, alpha: 1).setFill(); v.rect.fill()
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: v.rect).addClip()
        if guides { drawGuides(in: v.rect) }
        renderer.draw(state.scene, in: v, excluding: editingID)
        func outline(_ e: SceneElement, color: NSColor) {
            let points = SceneGeometry.corners(e).map(v.viewPoint)
            let path = NSBezierPath(); path.move(to: points[0])
            points.dropFirst().forEach { path.line(to: $0) }
            path.close(); color.setStroke(); path.lineWidth = 1.5; path.stroke()
        }
        for e in state.selected { outline(e, color: .controlAccentColor) }
        if state.selected.count > 1, let box = SceneGeometry.bounds(state.selected) {
            NSColor.controlAccentColor.setStroke(); NSBezierPath(rect: v.viewRect(box)).stroke()
        }
        if original != nil && downID == nil && dragging {
            let box = v.viewRect(dragRect)
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); box.fill()
            NSColor.controlAccentColor.setStroke(); NSBezierPath(rect: box).stroke()
        }
        if let drop = drop {
            let label: String
            switch drop {
            case .add: label = "Добавить фото"
            case .replace(let id):
                label = "Заменить фото"
                if let e = state.scene.elements.first(where: { $0.id == id }) { outline(e, color: .systemOrange) }
            }
            badge(label, at: CGPoint(x: v.rect.minX+12, y: v.rect.minY+12))
        } else if textTool { badge("Щёлкните или протяните рамку для текста", at: CGPoint(x: v.rect.minX+12, y: v.rect.minY+12)) }
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
    override func mouseDown(with event: NSEvent) {
        finishText(); focus()
        let point = scenePoint(event.locationInWindow)
        guard viewport.rect.contains(convert(event.locationInWindow, from: nil)) else { state.select([]); return }
        let hit = textTool ? nil : state.hit(point)
        if event.clickCount == 2, let e = hit {
            state.select([e.id])
            if e.kind == .text { beginEditing(e, initial: state.value, isNew: false, click: event.locationInWindow) }
            else { onPickReplacement?(e.id) }
            return
        }
        dragStart = point; dragCurrent = point; original = state.value; moveBase = nil
        dragging = false; axisX = nil; downID = hit?.id
        shiftDown = event.modifierFlags.contains(.shift); optionDown = event.modifierFlags.contains(.option)
        if let id = downID {
            if shiftDown { state.select(state.selection.symmetricDifference([id])) }
            else if !state.selection.contains(id) { state.select([id]) }
        } else if !shiftDown && !textTool { state.select([]) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let original = original else { return }
        dragCurrent = scenePoint(event.locationInWindow)
        var dx = dragCurrent.x - dragStart.x, dy = dragCurrent.y - dragStart.y
        guard dragging || hypot(dx,dy)*viewport.scale >= 3 else { return }
        dragging = true
        if textTool { needsDisplay = true; return }
        if let downID = downID {
            guard state.selection.contains(downID) || moveBase != nil else { return }
            if moveBase == nil {
                moveBase = optionDown ? SceneEditingState.inserting(state.selected, into: state.value, offset: 0) : state.value
            }
            if axisX == nil { axisX = abs(dx) >= abs(dy) }
            if event.modifierFlags.contains(.shift) { if axisX == true { dy = 0 } else { dx = 0 } }
            if let base = moveBase { state.preview(SceneEditingState.moved(base, dx: dx, dy: dy)) }
        } else {
            let ids = state.marquee(dragRect)
            state.select(shiftDown ? original.selection.union(ids) : ids)
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let original = original else { return }
        dragCurrent = scenePoint(event.locationInWindow)
        let rect = dragRect, dragged = dragging
        defer { clearGesture() }
        if textTool {
            beginNewText(at: dragged ? rect.origin : dragStart, width: dragged ? max(12, rect.width) : nil)
        } else if moveBase != nil { state.finish(from: original) }
        else if !dragged && !shiftDown, let id = downID { state.select([id]) }
    }
    private func clearGesture() {
        original = nil
        moveBase = nil
        downID = nil
        axisX = nil
        shiftDown = false
        optionDown = false
        dragging = false
        dragStart = .zero
        dragCurrent = .zero
        needsDisplay = true
    }
    private func beginNewText(at p: CGPoint, width: CGFloat?) {
        textTool = false
        let initial = state.value
        var e = SceneElement(kind: .text, frame: CGRect(x: p.x, y: p.y, width: width ?? 48, height: 40), text: "")
        e.autoTextWidth = width == nil
        SceneTextLayout.fit(&e)
        var v = initial; v.scene.elements.append(e); v.selection = [e.id]
        state.preview(v); beginEditing(e, initial: initial, isNew: true)
    }
    private func beginEditing(_ e: SceneElement, initial: SceneSnapshot, isNew: Bool, click: CGPoint? = nil) {
        initialText = initial; editingID = e.id; newText = isNew; typed = false; minimumHeight = isNew ? 1 : e.frame.height
        let field = SceneInputView(frame: .zero)
        field.isRichText = false; field.importsGraphics = false; field.allowsUndo = true
        field.isAutomaticQuoteSubstitutionEnabled = false; field.drawsBackground = false
        field.textContainerInset = .zero; field.textContainer?.lineFragmentPadding = 0
        field.isHorizontallyResizable = false; field.isVerticallyResizable = false
        field.textContainer?.widthTracksTextView = true; field.textContainer?.heightTracksTextView = false
        field.textContainer?.containerSize.height = CGFloat.greatestFiniteMagnitude
        field.string = e.text; field.delegate = self
        let attrs = SceneTextLayout.attributes(e.style, scale: viewport.scale)
        field.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: (e.text as NSString).length))
        field.typingAttributes = attrs; field.insertionPointColor = e.style.color.nsColor
        inputScale = viewport.scale; input = field; addSubview(field); positionInput(); window?.makeFirstResponder(field)
        let end = (e.text as NSString).length
        let cursor = click.map { field.characterIndexForInsertion(at: field.convert($0, from: nil)) } ?? end
        field.setSelectedRange(NSRange(location: min(cursor,end), length: 0)); needsDisplay = true
    }
    private func positionInput() {
        guard let input = input, let e = state.scene.elements.first(where: { $0.id == editingID }) else { return }
        let v = viewport, y = SceneTextLayout.yOffset(e)*v.scale
        let frame = v.viewRect(e.frame)
        if abs(v.scale-inputScale) > 0.0001 && !input.hasMarkedText() {
            let attrs = SceneTextLayout.attributes(e.style, scale: v.scale)
            input.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: (input.string as NSString).length))
            input.typingAttributes = attrs; inputScale = v.scale
        }
        input.frameCenterRotation = 0; input.frame = frame
        input.textContainerInset = CGSize(width: 0, height: y)
        input.frameCenterRotation = -e.rotation
        input.alphaValue = max(0.2, e.opacity)
    }
    override func layout() { super.layout(); positionInput() }
    func textDidChange(_ notification: Notification) {
        guard let field = input, let i = state.scene.elements.firstIndex(where: { $0.id == editingID }) else { return }
        var v = state.value
        v.scene.elements[i].text = field.string
        SceneTextLayout.fit(&v.scene.elements[i], minimumHeight: minimumHeight)
        typed = true; state.preview(v, typing: true); positionInput()
    }
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(cancelOperation(_:)) { finishText(); focus(); return true }
        return false
    }
    func textDidEndEditing(_ notification: Notification) { finishText() }
    func finishText() {
        guard let field = input, let initial = initialText, let id = editingID else { return }
        let restore = typed
        // Clear delegates first to avoid reentrant ending notifications during focus changes.
        field.delegate = nil; input = nil; initialText = nil; editingID = nil
        if newText && field.string.isEmpty {
            var v = state.value; v.scene.elements.removeAll { $0.id == id }; v.selection = initial.selection
            state.preview(v)
        }
        field.removeFromSuperview(); state.finish(from: initial)
        if restore && initial.scene == state.scene { onRestoreTypedScene?() }
        needsDisplay = true
    }
    func editSelection() {
        guard state.selected.count == 1, let e = state.selected.first else { return }
        if e.kind == .text { beginEditing(e, initial: state.value, isNew: false) }
        else { onPickReplacement?(e.id) }
    }
    override func keyDown(with event: NSEvent) {
        guard input == nil else { super.keyDown(with: event); return }
        if event.keyCode == 53, original != nil {
            cancelOperation(nil) // Option may still be held from the start of a copy drag.
            return
        }
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            let d: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 17: armText(); return // physical T / Е
            case 36, 76: editSelection(); return
            case 51, 117: deleteBackward(nil); return
            case 53: cancelOperation(nil); return
            case 123: state.move(dx: -d, dy: 0); return
            case 124: state.move(dx: d, dy: 0); return
            case 125: state.move(dx: 0, dy: d); return
            case 126: state.move(dx: 0, dy: -d); return
            default: break
            }
        }
        super.keyDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        if let beforeMouseDown = original {
            clearGesture()
            textTool = false
            state.preview(beforeMouseDown)
        } else if textTool {
            textTool = false
        } else {
            state.select([])
        }
    }
    override func deleteBackward(_ sender: Any?) { state.deleteSelection(); focus() }
    override func selectAll(_ sender: Any?) { state.select(Set(state.scene.elements.map(\.id))) }
    @objc func copy(_ sender: Any?) { _ = writeSelection() }
    private func writeSelection() -> Bool {
        do { return try SceneTransfer.write(state.selected, to: .general) }
        catch { onError?("Не удалось скопировать выделение."); return false }
    }
    @objc func cut(_ sender: Any?) { if writeSelection() { deleteBackward(nil) } }
    @objc func paste(_ sender: Any?) { _ = onPaste?(.general, nil) }
    @objc func duplicate(_ sender: Any?) { if input == nil { state.insertCopies(state.selected) } }
    @objc func undo(_ sender: Any?) { state.undo() }
    @objc func redo(_ sender: Any?) { state.redo() }
    @objc func bringForward(_ sender: Any?) { if input == nil { state.reorder(.forward) } }
    @objc func sendBackward(_ sender: Any?) { if input == nil { state.reorder(.backward) } }
    @objc func bringToFront(_ sender: Any?) { if input == nil { state.reorder(.front) } }
    @objc func sendToBack(_ sender: Any?) { if input == nil { state.reorder(.back) } }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard viewport.rect.contains(convert(sender.draggingLocation, from: nil)) else { drop = nil; needsDisplay = true; return [] }
        drop = state.dropDestination(at: scenePoint(sender.draggingLocation)); needsDisplay = true; return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { drop = nil; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let target = state.dropDestination(at: scenePoint(sender.draggingLocation))
        drop = nil; needsDisplay = true; finishText(); focus()
        return onPaste?(sender.draggingPasteboard, target) ?? false
    }
}
