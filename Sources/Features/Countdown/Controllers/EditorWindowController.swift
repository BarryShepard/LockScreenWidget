import AppKit

final class EditorWindowController: NSWindowController, NSTextFieldDelegate {
    let model: ApplicationModel
    let preferences: UserDefaults
    let editorView = EditorView()
    var canvas: CountdownView { editorView.countdownView }
    var onSettingsChange: (() -> Void)?
    var onToggleEnabled: (() -> Void)?
    var onTestPanel: (() -> Void)?
    private(set) var selectedIndices: Set<Int> = [0]
    private var selectedEventIndex = 0
    private var now = Date()
    private var restoreAfterPanelTest = false
    private var dragStart = NSPoint.zero
    private var originalOffsets: [Double] = []
    private var originalFrames: [NSRect] = []
    private var draggingElements = false
    private var marquee: NSRect?
    private var selectionBeforeMarquee: Set<Int> = []
    private enum Axis { case horizontal, vertical }
    private var lockedAxis: Axis?

    init(model: ApplicationModel, preferences: UserDefaults = .standard) {
        self.model = model
        self.preferences = preferences
        super.init(window: nil)
        canvas.previewScreenSize = NSScreen.main?.frame.size ?? NSSize(width: 1512, height: 982)
        editorView.eventPicker.addItem(withTitle: "Ближайшее событие")
        editorView.eventPicker.addItems(withTitles: model.catalog.events.map { "\(displayedEventDate($0)) · \($0.title)" })
        connectActions()
        renderCanvas()
        refreshInspector()
        refreshEnabledState()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func connectActions() {
        editorView.eventPicker.target = self
        editorView.eventPicker.action = #selector(eventSelected)
        editorView.enabledButton.target = self
        editorView.enabledButton.action = #selector(toggleEnabled)
        editorView.testButton.target = self
        editorView.testButton.action = #selector(testPanel)
        editorView.resetButton.target = self
        editorView.resetButton.action = #selector(resetPositions)
        let inspector = editorView.inspector
        inspector.block.target = self
        inspector.block.action = #selector(blockSelected)
        inspector.information.target = self
        inspector.information.action = #selector(toggleInformation)
        for button in inspector.centerButtons {
            button.target = self
            button.action = #selector(center(_:))
        }
        for control: NSControl in [inspector.family, inspector.weight, inspector.size, inspector.lineHeight,
                                   inspector.spacing, inspector.horizontal, inspector.vertical] {
            control.target = self
            control.action = #selector(changeStyle(_:))
            (control as? NSTextField)?.delegate = self
        }
        canvas.onMouseDown = { [weak self] point, extending in
            self?.beginInteraction(at: point, extendingSelection: extending)
            return self?.draggingElements ?? false
        }
        canvas.onMouseDragged = { [weak self] point, constrain in self?.dragInteraction(to: point, constrainAxis: constrain) }
        canvas.onMouseUp = { [weak self] in self?.endInteraction() }
        canvas.onKeyDown = { [weak self] code, shift in self?.handleKey(code, shift: shift) ?? false }
    }

    override func loadWindow() { window = EditorWindow(content: editorView) }

    @objc func showPreview() {
        if window == nil { loadWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        refresh(at: Date())
    }

    func hideForPanelTest() {
        restoreAfterPanelTest = isWindowLoaded && window?.isVisible == true
        if isWindowLoaded { window?.orderOut(nil) }
    }

    func finishPanelTest(_ completion: PanelTestCompletion) {
        switch completion {
        case .restoreEditor:
            if restoreAfterPanelTest { window?.makeKeyAndOrderFront(nil) }
            restoreAfterPanelTest = false
        case .deferEditor:
            break // Keep the original visibility until the user session is unlocked.
        case .discardEditor:
            restoreAfterPanelTest = false
        }
    }

    func refresh(at now: Date) {
        self.now = now
        renderCanvas()
        if let event = previewEvent(at: now) {
            editorView.catalogNote.stringValue = "Срок: \(displayedEventDate(event)). " + (eventHasCountdown(event)
                ? "Отсчёт до 00:00 по Москве. Выбор меняет только предпросмотр."
                : "Точный день не указан. Карточка доступна для просмотра без секундного отсчёта.")
        } else { editorView.catalogNote.stringValue = "" }
        // Do not rewrite the inspector while a user is entering a partial number.
    }

    private func previewEvent(at now: Date) -> ApocalypseEventModel? {
        let events = model.catalog.events
        return selectedEventIndex > 0 && selectedEventIndex <= events.count
            ? events[selectedEventIndex - 1] : selectNextEvent(in: model.catalog, now: now)
    }

    func selectEvent(at index: Int) {
        selectedEventIndex = (0...model.catalog.events.count).contains(index) ? index : 0
        editorView.eventPicker.selectItem(at: selectedEventIndex)
        refresh(at: now)
    }

    @objc private func eventSelected() { selectEvent(at: editorView.eventPicker.indexOfSelectedItem) }
    @objc private func toggleEnabled() { onToggleEnabled?() }
    @objc private func testPanel() { onTestPanel?() }

    func refreshEnabledState() { editorView.enabledButton.state = model.isEnabled ? .on : .off }

    @objc func openSource() {
        let date = Date()
        let event = isWindowLoaded && window?.isVisible == true ? previewEvent(at: date) : selectNextEvent(in: model.catalog, now: date)
        if let event { NSWorkspace.shared.open(event.sourceURL) }
    }

    private var countdownPresentation: CountdownPresentation {
        makeCountdownPresentation(content: makeCountdownDisplay(event: previewEvent(at: now), now: now),
                                  settings: model.settings)
    }

    private func renderCanvas() {
        canvas.render(countdownPresentation, selectedIndices: selectedIndices, marquee: marquee)
    }

    private func refreshInspector() {
        let inspector = editorView.inspector
        inspector.render(makeTypographyInspectorPresentation(settings: model.settings,
            selectedIndices: selectedIndices, fallbackBlockIndex: inspector.block.indexOfSelectedItem))
    }

    private func selectionDidChange() { renderCanvas(); refreshInspector() }

    private func saveSettings(refreshControls: Bool = true) {
        model.settings = validateEditorSettings(model.settings)
        saveEditorSettings(model.settings, to: preferences)
        renderCanvas()
        if refreshControls { refreshInspector() }
        onSettingsChange?()
    }

    @objc func resetPositions() {
        model.settings.offsets = [0, 0, 0, 0, 0, 0]
        saveSettings()
    }

    func selectBlock(_ index: Int) {
        guard visibleBlockIndices(in: model.settings).contains(index) else { return }
        selectedIndices = [index]
        selectionDidChange()
    }

    func setTypography(_ typography: BlockTypographyModel, for indices: Set<Int>) {
        for index in indices where visibleBlockIndices(in: model.settings).contains(index) {
            model.settings.typography[index] = validateBlockTypography(typography)
        }
        saveSettings()
    }

    func editSelectedTypography(refreshControls: Bool = true, _ edit: (inout BlockTypographyModel) -> Void) {
        for index in selectedIndices {
            var style = model.settings.typography[index]
            edit(&style)
            model.settings.typography[index] = validateBlockTypography(style)
        }
        saveSettings(refreshControls: refreshControls)
    }

    func setInformationVisible(_ visible: Bool) {
        model.settings.showInformation = visible
        selectedIndices.formIntersection(visibleBlockIndices(in: model.settings))
        saveSettings()
    }

    @objc private func blockSelected() {
        selectBlock(editorView.inspector.block.indexOfSelectedItem)
        canvas.window?.makeFirstResponder(canvas)
    }
    @objc private func toggleInformation() { setInformationVisible(editorView.inspector.information.state == .on) }
    @objc private func center(_ button: NSButton) {
        centerSelection(horizontal: button.tag == 0)
        canvas.window?.makeFirstResponder(canvas)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        if let field = notification.object as? NSTextField { applyStyle(field, refreshControls: true) }
    }
    func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField { applyStyle(field, refreshControls: false) }
    }
    @objc private func changeStyle(_ control: NSControl) { applyStyle(control, refreshControls: true) }

    private func applyStyle(_ control: NSControl, refreshControls: Bool) {
        let tag = control.tag
        let inspector = editorView.inspector
        let newValue: Double?
        if let field = control as? NSTextField {
            newValue = parseTypographyNumber(field.stringValue, allowsAutomatic: tag == 3)
            guard newValue != nil else {
                if refreshControls { refreshInspector() }
                return
            }
        } else { newValue = nil }
        editSelectedTypography(refreshControls: refreshControls) { style in
            switch tag {
            case 0: style.family = inspector.family.selectedItem?.representedObject as? String ?? "System"
            case 1: style.weight = inspector.weight.indexOfSelectedItem
            case 2: if let newValue { style.size = newValue }
            case 3: if let newValue { style.lineHeight = newValue }
            case 4: if let newValue { style.spacing = newValue }
            case 5: style.alignment = inspector.horizontal.selectedSegment
            case 6: style.verticalAlignment = inspector.vertical.selectedSegment
            default: break
            }
        }
    }

    private var offsets: [Double] {
        get { model.settings.offsets }
        set { model.settings.offsets = newValue }
    }

    func endInteraction() {
        let wasDragging = draggingElements
        draggingElements = false
        marquee = nil
        lockedAxis = nil
        if wasDragging { saveSettings() }
        else { renderCanvas() }
    }

    private func handleKey(_ code: UInt16, shift: Bool) -> Bool {
        switch code {
        case 123: nudgeSelection(x: -1, y: 0, largeStep: shift)
        case 124: nudgeSelection(x: 1, y: 0, largeStep: shift)
        case 125: nudgeSelection(x: 0, y: 1, largeStep: shift)
        case 126: nudgeSelection(x: 0, y: -1, largeStep: shift)
        case 53: selectedIndices = []; selectionDidChange()
        default: return false
        }
        return true
    }

    func beginInteraction(at point: NSPoint, extendingSelection: Bool) {
        canvas.window?.makeFirstResponder(canvas)
        let runs = canvas.layout(in: canvas.bounds, presentation: countdownPresentation)
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
            originalFrames = canvas.layout(in: canvas.bounds, presentation: countdownPresentation).map(\.frame)
            draggingElements = true
        } else {
            draggingElements = false
            selectionBeforeMarquee = extendingSelection ? selectedIndices : []
            selectedIndices = selectionBeforeMarquee
            marquee = NSRect(origin: point, size: .zero)
        }
        renderCanvas()
        refreshInspector()
    }

    func dragInteraction(to point: NSPoint, constrainAxis: Bool) {
        if marquee != nil {
            let rect = NSRect(x: min(point.x, dragStart.x), y: min(point.y, dragStart.y),
                              width: abs(point.x - dragStart.x), height: abs(point.y - dragStart.y))
            marquee = rect
            let runs = canvas.layout(in: canvas.bounds, presentation: countdownPresentation)
            let hits = runs.indices.filter { runs[$0].frame.intersects(rect) }
            selectedIndices = selectionBeforeMarquee.union(hits)
            refreshInspector()
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
            let area = canvas.canvasFrame(in: canvas.bounds)
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
        renderCanvas()
    }

    func moveElement(_ index: Int, to offset: NSPoint) {
        guard visibleBlockIndices(in: model.settings).contains(index), offset.x.isFinite, offset.y.isFinite else { return }
        offsets[index * 2] = 0
        offsets[index * 2 + 1] = 0
        let base = canvas.layout(in: canvas.bounds, presentation: countdownPresentation)[index].frame
        let area = canvas.canvasFrame(in: canvas.bounds)
        guard area.width > 0, area.height > 0 else { return }
        offsets[index * 2] = min(max(offset.x, (area.minX - base.minX) / area.width),
                                (area.maxX - base.maxX) / area.width)
        offsets[index * 2 + 1] = min(max(offset.y, (area.minY - base.minY) / area.height),
                                    (area.maxY - base.maxY) / area.height)
        renderCanvas()
    }

    /// Shared translation in preview points, preserving the group's relative arrangement.
    private func translateSelection(dx: CGFloat, dy: CGFloat) {
        guard !selectedIndices.isEmpty else { return }
        for index in selectedIndices { moveElement(index, to: NSPoint(x: offsets[index * 2], y: offsets[index * 2 + 1])) }
        let area = canvas.canvasFrame(in: canvas.bounds)
        let runs = canvas.layout(in: canvas.bounds, presentation: countdownPresentation)
        let frames = selectedIndices.map { runs[$0].frame }
        let tx = min(max(dx, frames.map { area.minX - $0.minX }.max() ?? 0), frames.map { area.maxX - $0.maxX }.min() ?? 0)
        let ty = min(max(dy, frames.map { area.minY - $0.minY }.max() ?? 0), frames.map { area.maxY - $0.maxY }.min() ?? 0)
        guard area.width > 0, area.height > 0 else { return }
        for index in selectedIndices {
            offsets[index * 2] += tx / area.width
            offsets[index * 2 + 1] += ty / area.height
        }
        saveSettings()
    }

    func nudgeSelection(x: CGFloat, y: CGFloat, largeStep: Bool = false) {
        let area = canvas.canvasFrame(in: canvas.bounds)
        let reference = canvas.previewScreenSize
        let step: CGFloat = largeStep ? 10 : 1
        translateSelection(dx: x * step * area.width / reference.width,
                           dy: y * step * area.height / reference.height)
    }

    func centerSelection(horizontal: Bool) {
        guard !selectedIndices.isEmpty else { return }
        let runs = canvas.layout(in: canvas.bounds, presentation: countdownPresentation)
        let group = selectedIndices.map { runs[$0].frame }.reduce(NSRect.null) { $0.union($1) }
        let area = canvas.canvasFrame(in: canvas.bounds)
        translateSelection(dx: horizontal ? area.midX - group.midX : 0,
                           dy: horizontal ? 0 : area.midY - group.midY)
    }

}
