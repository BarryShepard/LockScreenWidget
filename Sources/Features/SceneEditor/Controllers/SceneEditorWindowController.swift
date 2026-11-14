import AppKit
import UniformTypeIdentifiers

final class SceneEditorWindowController: NSWindowController, NSWindowDelegate {
    private let state: SceneEditingStateModel
    private let store: SceneStore
    private let canvasController: SceneCanvasController
    private let inspectorController: SceneInspectorController
    private let canvas: SceneCanvasView
    private let inspector: SceneInspectorView
    private let status = NSTextField(labelWithString: "Локальная композиция")
    private let guides = NSButton(checkboxWithTitle: "Ориентир входа", target: nil, action: nil)
    private let clock = NSButton(checkboxWithTitle: "Ориентир часов", target: nil, action: nil)
    private let clockHelp = NSButton()
    private(set) var clockPopover = NSPopover()
    private var blocked: String?
    private var pendingSave: DispatchWorkItem?
    // Typing can save a provisional scene before the editing session commits.
    private var hasCommittedDocument: Bool
    private var desiredDocument: EditorSceneModel?
    private var savedDocument: EditorSceneModel?
    var scene: EditorSceneModel { state.scene }
    var canUndo: Bool { state.canUndo }
    var onSceneChange: ((EditorSceneModel?) -> Void)?
    var onOpenSystemSettings: () -> Bool = {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") else { return false }
        return NSWorkspace.shared.open(url)
    }
    var onVisibilityChange: ((Bool) -> Void)?

    init(scene: EditorSceneModel, hasSavedScene: Bool, store: SceneStore, catalog: EventCatalogModel = .init(), now: Date = Date(), pasteboard: NSPasteboard = .general) {
        hasCommittedDocument = hasSavedScene
        savedDocument = hasSavedScene ? scene : nil
        desiredDocument = savedDocument
        self.store = store; state = SceneEditingStateModel(scene)
        canvasController = SceneCanvasController(state: state, store: store, catalog: catalog, now: now)
        canvasController.contextPasteboard = pasteboard
        canvas = canvasController.view
        inspector = SceneInspectorView(frame: .zero)
        inspectorController = SceneInspectorController(state: state, view: inspector, catalog: catalog, now: now)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 710),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Mice — редактор экрана блокировки"; window.minSize = CGSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        buildWindow(window)
        state.onUpdate = { [weak self] in self?.update($0) }
        canvasController.onEditClock = { [weak self] in self?.inspectorController.clock.focus() }
        canvasController.onEditCountdown = { [weak self] in self?.inspectorController.countdown.focus() }
        canvasController.onPickReplacement = { [weak self] id in self?.pick(.replace(id)) }
        canvasController.onPickImage = { [weak self] point in self?.pick(.add(point)) }
        canvasController.onPaste = { [weak self] board, target in self?.paste(board, drop: target) ?? false }
        canvasController.onPasteHere = { [weak self] board, point in self?.paste(board, drop: nil, insertionPoint: point) ?? false }
        canvasController.onRestoreTypedScene = { [weak self] in
            guard let self else { return }
            self.desiredDocument = self.hasCommittedDocument ? self.scene : nil
            self.saveIfNeeded()
        }
        inspectorController.onFocus = { [weak self] in self?.canvas.focus() }
        inspectorController.onBeforeLock = { [weak self] in self?.finishFields() }
        inspectorController.onError = { [weak self] in self?.showError($0) }
        canvasController.onError = inspectorController.onError
        update(.selection)
    }
    required init?(coder: NSCoder) { fatalError() }
    func refresh(at now: Date) { canvasController.refresh(at: now); inspectorController.countdown.refresh(at: now) }
    func showEditor() { onVisibilityChange?(true); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); canvas.focus() }
    func setPersistenceBlocked(_ message: String) {
        blocked = message; pendingSave?.cancel(); pendingSave = nil; showError(message)
    }
    func flush() { // Also useful from applicationWillTerminate, when there is no windowWillClose.
        window?.makeFirstResponder(nil); canvasController.finishText(); saveIfNeeded()
    }
    func windowWillClose(_ notification: Notification) { clockPopover.performClose(nil); flush(); onVisibilityChange?(false) }

    private func buildWindow(_ window: NSWindow) {
        let root = NSView(); window.contentView = root
        let bar = NSStackView(); bar.spacing = 8; bar.translatesAutoresizingMaskIntoConstraints = false
        let add = NSPopUpButton(frame: .zero, pullsDown: true)
        add.addItem(withTitle: "Добавить"); add.addItem(withTitle: "Текст"); add.addItem(withTitle: "Заметка"); add.addItem(withTitle: "Фото с устройства…"); add.addItem(withTitle: "Таймер"); add.addItem(withTitle: "Часы")
        add.target = self; add.action = #selector(addSelected(_:)); add.setAccessibilityLabel("Добавить")
        guides.toolTip = "Приблизительная область имени пользователя и пароля macOS"
        guides.target = self; guides.action = #selector(toggleGuides); guides.state = .on
        guides.identifier = .init("login-guide")
        clock.toolTip = "Приблизительная область системных часов macOS"
        clock.target = self; clock.action = #selector(toggleClock); clock.state = .on
        clock.identifier = .init("clock-guide")
        clockHelp.bezelStyle = .helpButton; clockHelp.title = ""
        clockHelp.target = self; clockHelp.action = #selector(toggleClockHelp)
        clockHelp.identifier = .init("clock-guide-help")
        clockHelp.setAccessibilityLabel("О системных часах")
        clockHelp.toolTip = "Как скрыть системные часы macOS"
        [add,guides,clock,clockHelp].forEach { bar.addArrangedSubview($0) }
        let noticeText = NSTextField(wrappingLabelWithString: "Переключатель скрывает только ориентир в редакторе. Системные часы отключаются в настройках macOS: «Показывать большие часы» → «Никогда».")
        noticeText.font = .systemFont(ofSize: 12); noticeText.textColor = .secondaryLabelColor
        noticeText.preferredMaxLayoutWidth = 328
        let settings = NSButton(title: "Настройки экрана блокировки…", target: self, action: #selector(openSystemSettings))
        settings.identifier = .init("clock-guide-settings"); settings.controlSize = .small
        let dismiss = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Закрыть уведомление")!, target: self, action: #selector(dismissClockNotice))
        dismiss.identifier = .init("clock-guide-dismiss"); dismiss.bezelStyle = .inline
        let title = NSTextField(labelWithString: "Системные часы macOS"); title.font = .boldSystemFont(ofSize: 13)
        let heading = NSStackView(views: [title, dismiss]); heading.distribution = .fill; heading.spacing = 8
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let content = NSView()
        let stack = NSStackView(views: [heading, noticeText, settings])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalToConstant: 328),
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            noticeText.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        let helpController = NSViewController(); helpController.view = content
        clockPopover.contentViewController = helpController
        clockPopover.contentSize = content.fittingSize
        clockPopover.behavior = .transient; clockPopover.animates = false
        let line = NSBox(); line.boxType = .separator
        let sidebarLine = NSBox(); sidebarLine.boxType = .separator
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingTail
        [bar,line,canvas,sidebarLine,inspector,status].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
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
    private func finishFields() { window?.makeFirstResponder(canvas); canvasController.finishText() }
    @objc private func addSelected(_ sender: NSPopUpButton) {
        finishFields()
        guard let tool = SceneCanvasTool(rawValue: sender.indexOfSelectedItem - 1) else { return }
        canvasController.arm(tool)
    }
    @objc private func toggleGuides() {
        canvas.guides = guides.state == .on; canvas.focus()
    }
    @objc private func toggleClock() {
        canvas.clock = clock.state == .on
        canvas.focus()
        if canvas.clock { clockPopover.performClose(nil) }
    }
    private func showClockHelp() {
        guard clockHelp.window?.isVisible == true else { return }
        clockPopover.show(relativeTo: clockHelp.bounds, of: clockHelp, preferredEdge: .maxY)
    }
    @objc private func toggleClockHelp() {
        if clockPopover.isShown { clockPopover.performClose(nil) } else { showClockHelp() }
    }
    @objc private func dismissClockNotice() { clockPopover.performClose(nil) }
    @objc private func openSystemSettings() {
        if !onOpenSystemSettings() { showError("Не удалось открыть настройки экрана блокировки macOS.") }
    }
    private func update(_ kind: SceneUpdate) {
        canvasController.refresh(); inspectorController.refresh()
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
        try canvasController.images.importImages(inputs, at: target)
    }
    private func paste(_ board: NSPasteboard, drop: SceneImageDestination?, insertionPoint: CGPoint? = nil) -> Bool {
        let target = drop ?? insertionPoint.map { .add($0) } ?? canvasController.images.pasteImageDestination
        do {
            switch try SceneTransfer.read(board, allowLayers: drop == nil) {
            case .layers(let copied): state.insertCopies(copied, at: insertionPoint)
            case .images(let images): try importImages(images, into: target)
            case .text(let string) where drop == nil:
                var e = SceneElementModel(kind: .text, frame: CGRect(origin: insertionPoint ?? canvasController.images.insertionPoint,
                                     size: CGSize(width: max(60,scene.canvasSize.width*0.45),height: 1)), text: string)
                SceneTextLayout.fit(&e)
                state.change { $0.scene.elements.append(e); $0.selection = [e.id] }
            default: return false
            }
            canvas.focus(); return true
        } catch { showError(error.localizedDescription); return false }
    }
}
