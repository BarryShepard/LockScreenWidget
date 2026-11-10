import AppKit

/// Loading never repairs a damaged document implicitly. The temporary store is only
/// a dependency for an in-memory editor when the real directory cannot be opened.
struct SceneStartup {
    let scene: EditorSceneModel
    let store: SceneStore
    let hasSavedScene: Bool
    let persistenceError: String?
    let temporaryDirectory: URL?

    static func directoryArgument(in arguments: [String]) throws -> URL? {
        let positions = arguments.indices.filter { arguments[$0] == "--scene-directory" }
        guard !positions.isEmpty else { return nil }
        guard positions.count == 1, let index = positions.first, index + 1 < arguments.count,
              arguments[index + 1].hasPrefix("/") else {
            throw SceneError.invalid("--scene-directory требует один абсолютный путь к отдельной папке документа.")
        }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func load(canvasSize: CGSize, directory: () throws -> URL) throws -> SceneStartup {
        let store: SceneStore
        do { store = try SceneStore(directory: directory()) }
        catch {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("TEotW-in-memory-\(UUID().uuidString)", isDirectory: true)
            return SceneStartup(scene: EditorSceneModel(canvasSize: canvasSize), store: try SceneStore(directory: temporary),
                                hasSavedScene: false, persistenceError: error.localizedDescription,
                                temporaryDirectory: temporary)
        }
        do {
            let saved = try store.load()
            return SceneStartup(scene: saved ?? EditorSceneModel(canvasSize: canvasSize), store: store,
                                hasSavedScene: saved != nil, persistenceError: nil, temporaryDirectory: nil)
        } catch {
            return SceneStartup(scene: EditorSceneModel(canvasSize: canvasSize), store: store,
                                hasSavedScene: false, persistenceError: error.localizedDescription, temporaryDirectory: nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: ApplicationModel?
    private var editorController: EditorWindowController?
    private var sceneEditorController: SceneEditorWindowController?
    private var sceneStore: SceneStore?
    private var temporarySceneDirectory: URL?
    private var scenePanelRestoration = PanelTestWindowRestoration()
    private var lockScreenController: LockScreenController?
    private var countdownController: CountdownController?
    private var statusItem: NSStatusItem?
    private var enabledMenu: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logDiagnostic("launch")
        do {
            // Capture before revealing either editor: NSApplication's main screen can
            // change with focus, and screen array ordering can change on hot plug.
            let targetScreen = NSScreen.main
            let targetID = targetScreen.flatMap(SceneScreenIdentity.identifier)
            let overrideDirectory = try SceneStartup.directoryArgument(in: CommandLine.arguments)
            let startup = try SceneStartup.load(canvasSize: targetScreen?.frame.size ?? CGSize(width: 1512, height: 982)) {
                try overrideDirectory ?? SceneStore.defaultDirectory()
            }
            sceneStore = startup.store
            temporarySceneDirectory = startup.temporaryDirectory
            guard let url = Bundle.main.url(forResource: "events", withExtension: "json") else {
                throw NSError(domain: "TEotW", code: 1, userInfo: [NSLocalizedDescriptionKey: "Файл событий не найден."])
            }
            let model = ApplicationModel(catalog: try loadEventCatalog(url), settings: loadEditorSettings())
            self.model = model
            let editor = EditorWindowController(model: model)
            let sceneEditor = SceneEditorWindowController(scene: startup.scene, hasSavedScene: startup.hasSavedScene, store: startup.store)
            if let error = startup.persistenceError {
                sceneEditor.setPersistenceBlocked("\(error) Изменения доступны только в памяти. Исходный документ не будет перезаписан.")
            }
            let lock = LockScreenController(model: model, targetScreenID: targetID)
            if startup.hasSavedScene { lock.sceneDidChange(startup.scene, store: startup.store) }
            editorController = editor
            sceneEditorController = sceneEditor
            lockScreenController = lock
            sceneEditor.onSceneChange = { [weak lock, weak store = startup.store] scene in
                guard let store else { return }
                lock?.sceneDidChange(scene, store: store)
            }
            sceneEditor.onRevealLegacy = { [weak editor] in editor?.showPreview() }
            editor.onSettingsChange = { [weak lock] in lock?.settingsDidChange() }
            editor.onToggleEnabled = { [weak lock] in lock?.toggleEnabled() }
            editor.onTestPanel = { [weak lock] in lock?.testPanel() }
            lock.onEnabledChange = { [weak self, weak editor] in
                editor?.refreshEnabledState()
                self?.enabledMenu?.state = self?.model?.isEnabled == true ? .on : .off
            }
            lock.onTestWillBegin = { [weak self, weak editor, weak sceneEditor] in
                sceneEditor?.flush()
                self?.scenePanelRestoration.hide(sceneEditor?.window)
                editor?.hideForPanelTest()
            }
            lock.onTestDidEnd = { [weak self, weak editor, weak sceneEditor] completion in
                self?.scenePanelRestoration.finish(completion, window: sceneEditor?.window)
                editor?.finishPanelTest(completion)
            }
            countdownController = CountdownController { [weak editor, weak lock] now in
                editor?.refresh(at: now)
                lock?.refresh(at: now)
            }
            makeMenu(editor: editor, lock: lock)
            lock.start()
            sceneEditor.showEditor()
            countdownController?.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось открыть приложение"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sceneEditorController?.flush()
        countdownController?.stop()
        lockScreenController?.stop()
        if let directory = temporarySceneDirectory { try? FileManager.default.removeItem(at: directory) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc private func showSceneEditor() { sceneEditorController?.showEditor() }

    /// Nil targets deliberately preserve the native text responder chain.
    static func makeEditMenu() -> NSMenu {
        let edit = NSMenu(title: "Правка")
        func item(_ title: String, _ action: String, _ key: String, shift: Bool = false) {
            let menuItem = edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
            menuItem.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            menuItem.target = nil
        }
        item("Отменить", "undo:", "z")
        item("Повторить", "redo:", "z", shift: true)
        edit.addItem(.separator())
        item("Вырезать", "cut:", "x")
        item("Копировать", "copy:", "c")
        item("Вставить", "paste:", "v")
        item("Выделить всё", "selectAll:", "a")
        item("Дублировать", "duplicate:", "d")
        edit.addItem(.separator())
        item("На слой вперёд", "bringForward:", "]")
        item("На слой назад", "sendBackward:", "[")
        item("На передний план", "bringToFront:", "]", shift: true)
        item("На задний план", "sendToBack:", "[", shift: true)
        return edit
    }

    private func makeMenu(editor: EditorWindowController, lock: LockScreenController) {
        let main = NSMenu()
        let app = NSMenuItem()
        main.addItem(app)
        app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        let edit = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        edit.submenu = Self.makeEditMenu()
        main.addItem(edit)
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = StatusIcon.skull()
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.toolTip = "Редактор экрана блокировки"
        let menu = NSMenu()
        menu.addItem(withTitle: "Открыть редактор экрана", action: #selector(showSceneEditor), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Редактор отсчёта…", action: #selector(EditorWindowController.showPreview), keyEquivalent: "").target = editor
        menu.addItem(.separator())
        enabledMenu = menu.addItem(withTitle: "Показывать при блокировке", action: #selector(LockScreenController.toggleEnabled), keyEquivalent: "")
        enabledMenu?.target = lock
        enabledMenu?.state = model?.isEnabled == true ? .on : .off
        menu.addItem(withTitle: "Проверить прозрачную панель (8 секунд)", action: #selector(LockScreenController.testPanel), keyEquivalent: "").target = lock
        menu.addItem(.separator())
        menu.addItem(withTitle: "Открыть источник отсчёта", action: #selector(EditorWindowController.openSource), keyEquivalent: "").target = editor
        menu.addItem(withTitle: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        statusItem?.menu = menu
    }
}
