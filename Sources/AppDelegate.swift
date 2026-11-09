import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: ApplicationModel?
    private var editorController: EditorWindowController?
    private var lockScreenController: LockScreenController?
    private var countdownController: CountdownController?
    private var statusItem: NSStatusItem?
    private var enabledMenu: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logDiagnostic("launch")
        do {
            guard let url = Bundle.main.url(forResource: "events", withExtension: "json") else {
                throw NSError(domain: "TEotW", code: 1, userInfo: [NSLocalizedDescriptionKey: "Файл событий не найден."])
            }
            let model = ApplicationModel(catalog: try loadEventCatalog(url), settings: loadEditorSettings())
            self.model = model
            let editor = EditorWindowController(model: model)
            let lock = LockScreenController(model: model)
            editorController = editor
            lockScreenController = lock
            editor.onSettingsChange = { [weak lock] in lock?.settingsDidChange() }
            editor.onToggleEnabled = { [weak lock] in lock?.toggleEnabled() }
            editor.onTestPanel = { [weak lock] in lock?.testPanel() }
            lock.onEnabledChange = { [weak self, weak editor] in
                editor?.refreshEnabledState()
                self?.enabledMenu?.state = self?.model?.isEnabled == true ? .on : .off
            }
            lock.onTestWillBegin = { [weak editor] in editor?.hideForPanelTest() }
            lock.onTestDidEnd = { [weak editor] completion in editor?.finishPanelTest(completion) }
            countdownController = CountdownController { [weak editor, weak lock] now in
                editor?.refresh(at: now)
                lock?.refresh(at: now)
            }
            makeMenu(editor: editor, lock: lock)
            lock.start()
            editor.showPreview()
            countdownController?.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось открыть каталог"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        countdownController?.stop()
        lockScreenController?.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func makeMenu(editor: EditorWindowController, lock: LockScreenController) {
        let main = NSMenu()
        let app = NSMenuItem()
        main.addItem(app)
        app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = StatusIcon.skull()
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.toolTip = "Следующий конец света"
        let menu = NSMenu()
        enabledMenu = menu.addItem(withTitle: "Показывать при блокировке", action: #selector(LockScreenController.toggleEnabled), keyEquivalent: "")
        enabledMenu?.target = lock
        enabledMenu?.state = model?.isEnabled == true ? .on : .off
        menu.addItem(withTitle: "Открыть предпросмотр", action: #selector(EditorWindowController.showPreview), keyEquivalent: "").target = editor
        menu.addItem(withTitle: "Проверить прозрачную панель (8 секунд)", action: #selector(LockScreenController.testPanel), keyEquivalent: "").target = lock
        menu.addItem(.separator())
        menu.addItem(withTitle: "Открыть источник", action: #selector(EditorWindowController.openSource), keyEquivalent: "").target = editor
        menu.addItem(withTitle: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        statusItem?.menu = menu
    }
}
