import AppKit
import UniformTypeIdentifiers

final class SceneEditorWindowController: NSWindowController, NSWindowDelegate {
    private let state: SceneEditingState
    private let store: SceneStore
    private let canvas: SceneCanvasView
    private let inspector: SceneInspectorView
    private let status = NSTextField(labelWithString: "Локальная композиция")
    private let undoButton = NSButton(), redoButton = NSButton()
    private let guides = NSButton(checkboxWithTitle: "Ориентиры", target: nil, action: nil)
    private let clock = NSButton(checkboxWithTitle: "Часы", target: nil, action: nil)
    private var blocked: String?
    private var pendingSave: DispatchWorkItem?
    // Typing can save a provisional scene before the editing session commits.
    private var hasCommittedDocument: Bool
    private var desiredDocument: EditorScene?
    private var savedDocument: EditorScene?
    var scene: EditorScene { state.scene }
    var onSceneChange: ((EditorScene?) -> Void)?
    var onRevealLegacy: (() -> Void)?

    init(scene: EditorScene, hasSavedScene: Bool, store: SceneStore) {
        hasCommittedDocument = hasSavedScene
        savedDocument = hasSavedScene ? scene : nil
        desiredDocument = savedDocument
        self.store = store; state = SceneEditingState(scene)
        canvas = SceneCanvasView(state: state, store: store); inspector = SceneInspectorView(state: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 710),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Редактор экрана блокировки"; window.minSize = CGSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        buildWindow(window)
        state.onUpdate = { [weak self] in self?.update($0) }
        canvas.onPickReplacement = { [weak self] id in self?.pick(.replace(id)) }
        canvas.onPaste = { [weak self] board, target in self?.paste(board, drop: target) ?? false }
        canvas.onRestoreTypedScene = { [weak self] in
            guard let self else { return }
            self.desiredDocument = self.hasCommittedDocument ? self.scene : nil
            self.saveIfNeeded()
        }
        inspector.onFocus = { [weak self] in self?.canvas.focus() }
        inspector.onError = { [weak self] in self?.showError($0) }
        canvas.onError = inspector.onError
        update(.selection)
    }
    required init?(coder: NSCoder) { fatalError() }
    func showEditor() { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); canvas.focus() }
    func setPersistenceBlocked(_ message: String) {
        blocked = message; pendingSave?.cancel(); pendingSave = nil; showError(message)
    }
    func flush() { // Also useful from applicationWillTerminate, when there is no windowWillClose.
        window?.makeFirstResponder(nil); canvas.finishText(); saveIfNeeded()
    }
    func windowWillClose(_ notification: Notification) { flush() }

    private func buildWindow(_ window: NSWindow) {
        let root = NSView(); window.contentView = root
        let bar = NSStackView(); bar.spacing = 8; bar.translatesAutoresizingMaskIntoConstraints = false
        let add = NSPopUpButton(frame: .zero, pullsDown: true)
        add.addItem(withTitle: "Добавить"); add.addItem(withTitle: "Текст"); add.addItem(withTitle: "Фото с устройства…")
        add.target = self; add.action = #selector(addSelected(_:)); add.setAccessibilityLabel("Добавить")
        func button(_ b: NSButton, _ symbol: String, _ label: String, _ selector: Selector) {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label); b.bezelStyle = .rounded
            b.toolTip = label; b.setAccessibilityLabel(label); b.target = self; b.action = selector
        }
        button(undoButton,"arrow.uturn.backward","Отменить",#selector(undoClicked))
        button(redoButton,"arrow.uturn.forward","Повторить",#selector(redoClicked))
        guides.target = self; guides.action = #selector(toggleGuides); guides.state = .on
        clock.target = self; clock.action = #selector(toggleGuides); clock.state = .on
        [add,undoButton,redoButton,guides,clock].forEach { bar.addArrangedSubview($0) }
        let legacy = NSButton(title: "Редактор отсчёта…", target: self, action: #selector(revealLegacy)); legacy.bezelStyle = .rounded
        let line = NSBox(); line.boxType = .separator
        let sidebarLine = NSBox(); sidebarLine.boxType = .separator
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingTail
        [bar,legacy,line,canvas,sidebarLine,inspector,status].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            legacy.centerYAnchor.constraint(equalTo: bar.centerYAnchor),legacy.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            line.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10),line.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: root.trailingAnchor),line.heightAnchor.constraint(equalToConstant: 1),
            canvas.topAnchor.constraint(equalTo: line.bottomAnchor),canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: sidebarLine.leadingAnchor),canvas.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
            sidebarLine.topAnchor.constraint(equalTo: line.bottomAnchor),sidebarLine.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarLine.widthAnchor.constraint(equalToConstant: 1),sidebarLine.trailingAnchor.constraint(equalTo: inspector.leadingAnchor),
            inspector.topAnchor.constraint(equalTo: line.bottomAnchor),inspector.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            inspector.trailingAnchor.constraint(equalTo: root.trailingAnchor),inspector.widthAnchor.constraint(equalToConstant: 260),
            status.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 14),status.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -10),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
    }
    private func finishFields() { window?.makeFirstResponder(canvas); canvas.finishText() }
    @objc private func addSelected(_ sender: NSPopUpButton) {
        finishFields()
        if sender.indexOfSelectedItem == 1 { canvas.createCenteredText() }
        if sender.indexOfSelectedItem == 2 { pick(.add(state.insertionPoint)) }
    }
    @objc private func undoClicked() { finishFields(); state.undo() }
    @objc private func redoClicked() { finishFields(); state.redo() }
    @objc private func revealLegacy() { finishFields(); onRevealLegacy?() }
    @objc private func toggleGuides() {
        canvas.guides = guides.state == .on; canvas.clock = clock.state == .on
        clock.isEnabled = canvas.guides; canvas.focus()
    }
    private func update(_ kind: SceneUpdate) {
        canvas.needsDisplay = true; inspector.refresh()
        undoButton.isEnabled = state.canUndo; redoButton.isEnabled = state.canRedo
        switch kind {
        case .selection, .preview: break
        case .typing:
            desiredDocument = scene; pendingSave?.cancel()
            guard blocked == nil else { return }
            let work = DispatchWorkItem { [weak self] in self?.saveIfNeeded() }
            pendingSave = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.45, execute: work)
        case .committed:
            hasCommittedDocument = true
            desiredDocument = scene
            saveIfNeeded()
        }
    }
    private func saveIfNeeded() {
        pendingSave?.cancel(); pendingSave = nil
        guard blocked == nil else {
            // Recovery still supports editing and panel previews in memory.
            onSceneChange?(desiredDocument)
            return
        }
        guard desiredDocument != savedDocument else { return }
        do {
            if let desiredDocument { try store.save(desiredDocument) }
            else if let savedDocument { try store.discardProvisionalDocument(matching: savedDocument) }
            savedDocument = desiredDocument
            onSceneChange?(savedDocument)
            status.stringValue = savedDocument == nil ? "Локальная композиция" : "Сохранено на этом Mac"
            status.textColor = .secondaryLabelColor; status.toolTip = nil
        } catch { showError(error.localizedDescription) }
    }
    private func showError(_ message: String) {
        status.stringValue = blocked ?? message; status.toolTip = status.stringValue; status.textColor = .systemRed
    }
    private func pick(_ destination: SceneImageDestination) {
        guard let window = window else { return }
        if let blocked = blocked { showError(blocked); return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false
        if case .add = destination { panel.allowsMultipleSelection = true }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            defer { self.canvas.focus() }
            guard response == .OK else { return }
            do { try self.importImages(try panel.urls.map(SceneImageInput.init(file:)), into: destination) }
            catch { self.showError(error.localizedDescription) }
        }
    }
    private func importImages(_ inputs: [SceneImageInput], into target: SceneImageDestination) throws {
        if let blocked = blocked { throw SceneError.invalid(blocked) }
        try state.importImages(inputs, at: target, store: store)
    }
    private func paste(_ board: NSPasteboard, drop: SceneImageDestination?) -> Bool {
        let target = drop ?? state.pasteImageDestination
        do {
            switch try SceneTransfer.read(board, allowLayers: drop == nil) {
            case .layers(let copied): state.insertCopies(copied)
            case .images(let images): try importImages(images, into: target)
            case .text(let string) where drop == nil:
                var e = SceneElement(kind: .text, frame: CGRect(origin: state.insertionPoint,
                                     size: CGSize(width: max(60,scene.canvasSize.width*0.45),height: 1)), text: string)
                SceneTextLayout.fit(&e)
                state.change { $0.scene.elements.append(e); $0.selection = [e.id] }
            default: return false
            }
            canvas.focus(); return true
        } catch { showError(error.localizedDescription); return false }
    }
}
