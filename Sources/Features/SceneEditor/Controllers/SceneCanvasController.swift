import AppKit

final class SceneCanvasController {
    let view: SceneCanvasView
    let images: SceneImageController
    private let state: SceneEditingStateModel
    private let presentationController: ScenePresentationController
    var onPickReplacement: ((UUID) -> Void)?
    var onPaste: ((NSPasteboard, SceneImageDestination?) -> Bool)?
    var onError: ((String) -> Void)?
    var onRestoreTypedScene: (() -> Void)?
    private var textTool = false
    private var editingID: UUID?
    private var initialText: SceneSnapshot?
    private var newText = false
    private var typed = false
    private var minimumHeight: CGFloat = 1
    private var dragStart = CGPoint.zero, dragCurrent = CGPoint.zero
    private var original: SceneSnapshot?, moveBase: SceneSnapshot?
    private var downID: UUID?, shiftDown = false, optionDown = false, dragging = false
    private var axisX: Bool?
    private var drop: SceneImageDestination?

    init(state: SceneEditingStateModel, store: SceneStore) {
        self.state = state
        view = SceneCanvasView(frame: .zero)
        images = SceneImageController(state: state, store: store)
        presentationController = ScenePresentationController(store: store)
        view.onAction = { [weak self] action in self?.handle(action); self?.refresh() }
        view.onMouseDown = { [weak self] event in self?.mouseDown(with: event); self?.refresh() }
        view.onMouseDragged = { [weak self] event in self?.mouseDragged(with: event); self?.refresh() }
        view.onMouseUp = { [weak self] event in self?.mouseUp(with: event); self?.refresh() }
        view.onKeyDown = { [weak self] event in
            guard let self else { return false }
            let handled = self.keyDown(event)
            self.refresh()
            return handled
        }
        view.onTextChange = { [weak self] text in self?.textChanged(text) }
        view.onLayout = { [weak self] in self?.refreshText() }
        view.onDragUpdate = { [weak self] point in
            guard let self else { return false }
            self.drop = point.map { self.images.dropDestination(at: $0) }
            self.refresh()
            return point != nil
        }
        view.onDrop = { [weak self] board, point in
            guard let self else { return false }
            let target = self.images.dropDestination(at: point)
            self.drop = nil
            self.finishText()
            self.view.focus()
            let accepted = self.onPaste?(board, target) ?? false
            self.refresh()
            return accepted
        }
        refresh()
    }

    private var dragRect: CGRect {
        CGRect(x: min(dragStart.x, dragCurrent.x), y: min(dragStart.y, dragCurrent.y),
               width: abs(dragStart.x - dragCurrent.x), height: abs(dragStart.y - dragCurrent.y))
    }
    func refresh() {
        let selected = state.selected
        var presentation = SceneCanvasPresentation()
        presentation.content = presentationController.content(for: state.scene)
        presentation.selectionOutlines = selected.map(SceneGeometry.corners)
        presentation.selectionBounds = selected.count > 1 ? SceneGeometry.bounds(selected) : nil
        presentation.marquee = original != nil && downID == nil && dragging ? dragRect : nil
        presentation.textTool = textTool
        presentation.editingID = editingID
        switch drop {
        case .some(.add):
            presentation.badge = "Добавить фото"
        case .some(.replace(let id)):
            presentation.badge = "Заменить фото"
            presentation.dropOutline = state.scene.elements.first { $0.id == id }.map(SceneGeometry.corners)
        case .none:
            presentation.badge = textTool ? "Щёлкните или протяните рамку для текста" : nil
        }
        view.render(presentation)
        refreshText()
    }

    private func mouseDown(with event: NSEvent) {
        finishText(); view.focus()
        let point = view.scenePoint(event.locationInWindow)
        guard view.contains(event.locationInWindow) else { state.select([]); return }
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
            if !state.selection.contains(id) { state.select(shiftDown ? state.selection.union([id]) : [id]) }
        } else if !shiftDown && !textTool { state.select([]) }
    }
    private func mouseDragged(with event: NSEvent) {
        guard let original = original else { return }
        dragCurrent = view.scenePoint(event.locationInWindow)
        var dx = dragCurrent.x - dragStart.x, dy = dragCurrent.y - dragStart.y
        guard dragging || hypot(dx,dy)*view.viewport.scale >= 3 else { return }
        dragging = true
        if textTool { return }
        if let downID = downID {
            guard state.selection.contains(downID) || moveBase != nil else { return }
            if moveBase == nil {
                moveBase = optionDown ? SceneEditingStateModel.inserting(state.selected, into: state.value, offset: 0) : state.value
            }
            if axisX == nil { axisX = abs(dx) >= abs(dy) }
            if event.modifierFlags.contains(.shift) { if axisX == true { dy = 0 } else { dx = 0 } }
            if let base = moveBase { state.preview(SceneEditingStateModel.moved(base, dx: dx, dy: dy)) }
        } else {
            let ids = state.marquee(dragRect)
            state.select(shiftDown ? original.selection.union(ids) : ids)
        }
    }
    private func mouseUp(with event: NSEvent) {
        guard let original = original else { return }
        dragCurrent = view.scenePoint(event.locationInWindow)
        let rect = dragRect, dragged = dragging
        defer { clearGesture() }
        if textTool {
            beginNewText(at: dragged ? rect.origin : dragStart, width: dragged ? max(12, rect.width) : nil)
        } else if moveBase != nil { state.finish(from: original) }
        else if !dragged, let id = downID {
            state.select(shiftDown ? original.selection.symmetricDifference([id]) : [id])
        }
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
    }
    private func beginNewText(at p: CGPoint, width: CGFloat?) {
        textTool = false
        let initial = state.value
        var e = SceneElementModel(kind: .text, frame: CGRect(x: p.x, y: p.y, width: width ?? 48, height: 40), text: "")
        e.autoTextWidth = width == nil
        SceneTextLayout.fit(&e)
        var v = initial; v.scene.elements.append(e); v.selection = [e.id]
        state.preview(v); beginEditing(e, initial: initial, isNew: true)
    }

    private func inputPresentation(_ element: SceneElementModel) -> SceneTextInputPresentation {
        SceneTextInputPresentation(frame: element.frame, rotation: element.rotation, opacity: element.opacity,
                                   yOffset: SceneTextLayout.yOffset(element),
                                   attributes: SceneTextLayout.attributes(element.style, scale: view.viewport.scale),
                                   color: SceneTextLayout.color(element.style.color))
    }
    private func beginEditing(_ element: SceneElementModel, initial: SceneSnapshot, isNew: Bool, click: CGPoint? = nil) {
        initialText = initial
        editingID = element.id
        newText = isNew
        typed = false
        minimumHeight = isNew ? 1 : element.frame.height
        refresh()
        view.beginText(element.text, presentation: inputPresentation(element), click: click)
    }
    private func refreshText() {
        guard let element = state.scene.elements.first(where: { $0.id == editingID }) else { return }
        view.updateText(inputPresentation(element))
    }
    private func textChanged(_ text: String) {
        guard let index = state.scene.elements.firstIndex(where: { $0.id == editingID }) else { return }
        var snapshot = state.value
        snapshot.scene.elements[index].text = text
        SceneTextLayout.fit(&snapshot.scene.elements[index], minimumHeight: minimumHeight)
        typed = true
        state.preview(snapshot, typing: true)
        refresh()
    }
    func finishText() {
        guard let initial = initialText, let id = editingID else { return }
        let restore = typed
        initialText = nil
        editingID = nil
        view.endText()
        // Only text accepted by the input method has reached the model.
        if newText && state.scene.elements.first(where: { $0.id == id })?.text.isEmpty == true {
            var snapshot = state.value
            snapshot.scene.elements.removeAll { $0.id == id }
            snapshot.selection = initial.selection
            state.preview(snapshot)
        }
        state.finish(from: initial)
        if restore && initial.scene == state.scene { onRestoreTypedScene?() }
        refresh()
    }
    func createCenteredText() {
        finishText()
        beginNewText(at: images.insertionPoint, width: nil)
    }
    private func editSelection() {
        guard state.selected.count == 1, let element = state.selected.first else { return }
        if element.kind == .text { beginEditing(element, initial: state.value, isNew: false) }
        else { onPickReplacement?(element.id) }
    }
    private func keyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53, original != nil { cancel(); return true }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let distance: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 17: handle(.armText)
        case 36, 76: editSelection()
        case 51, 117: handle(.delete)
        case 53: cancel()
        case 123: state.move(dx: -distance, dy: 0)
        case 124: state.move(dx: distance, dy: 0)
        case 125: state.move(dx: 0, dy: distance)
        case 126: state.move(dx: 0, dy: -distance)
        default: return false
        }
        return true
    }
    private func cancel() {
        if let snapshot = original {
            clearGesture()
            textTool = false
            state.preview(snapshot)
        } else if textTool {
            textTool = false
        } else {
            state.select([])
        }
    }
    private func writeSelection() -> Bool {
        do { return try SceneTransfer.write(state.selected, to: .general) }
        catch { onError?("Не удалось скопировать выделение."); return false }
    }
    private func handle(_ action: SceneCanvasAction) {
        switch action {
        case .armText:
            finishText()
            textTool = true
            view.focus()
        case .createText: createCenteredText()
        case .editSelection: editSelection()
        case .finishText: finishText()
        case .cancel: cancel()
        case .delete: state.deleteSelection(); view.focus()
        case .selectAll: state.select(Set(state.scene.elements.map(\.id)))
        case .copy: _ = writeSelection()
        case .cut:
            if writeSelection() { state.deleteSelection(); view.focus() }
        case .paste: _ = onPaste?(.general, nil)
        case .duplicate:
            if editingID == nil { state.insertCopies(state.selected) }
        case .undo: state.undo()
        case .redo: state.redo()
        case .forward:
            if editingID == nil { state.reorder(.forward) }
        case .backward:
            if editingID == nil { state.reorder(.backward) }
        case .front:
            if editingID == nil { state.reorder(.front) }
        case .back:
            if editingID == nil { state.reorder(.back) }
        }
    }
}
