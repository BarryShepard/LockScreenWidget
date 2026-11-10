import AppKit

@main struct LockScreenControllerTests {
    static func main() throws {
        let _ = NSApplication.shared
        let model = ApplicationModel(catalog: EventCatalogModel(), settings: EditorSettingsModel())
        var locked = false
        var delayedActions: [() -> Void] = []
        var began = 0
        var completions: [PanelTestCompletion] = []
        let controller = LockScreenController(model: model, readLockState: { locked }, makePanels: { [] },
            scheduleAfter: { _, action in delayedActions.append(action) })
        controller.onTestWillBegin = { began += 1 }
        controller.onTestDidEnd = { completions.append($0) }
        controller.start()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        controller.testPanel()
        assert(began == 1 && delayedActions.count == 1)
        controller.testPanel()
        assert(began == 1 && delayedActions.count == 2, "A repeated test must preserve the initial editor visibility")
        delayedActions[0]()
        assert(completions.isEmpty, "An older timeout must not finish the newer test")
        delayedActions[1]()
        assert(completions == [.restoreEditor])

        controller.testPanel()
        locked = true
        controller.refresh(at: now)
        assert(completions.last == .deferEditor)
        locked = false
        controller.refresh(at: now)
        assert(completions.last == .restoreEditor, "Unlock must restore the editor after an interrupted test")
        let completionCount = completions.count
        delayedActions[2]()
        assert(completions.count == completionCount, "Interrupted test timeout must be inert")

        controller.testPanel()
        controller.toggleEnabled()
        assert(!model.isEnabled && completions.last == .restoreEditor)
        controller.testPanel()
        controller.stop()
        assert(completions.last == .discardEditor)
        let stoppedCount = completions.count
        delayedActions.last?()
        assert(completions.count == stoppedCount, "Shutdown must invalidate pending callbacks")

        // Test the receiving controller too: deferral must preserve visibility intent.
        let editor = EditorWindowController(model: model, preferences: MemoryPreferences())
        editor.showPreview()
        assert(editor.window?.isVisible == true)
        editor.hideForPanelTest()
        editor.finishPanelTest(.deferEditor)
        assert(editor.window?.isVisible == false)
        editor.finishPanelTest(.restoreEditor)
        assert(editor.window?.isVisible == true)
        editor.hideForPanelTest()
        editor.finishPanelTest(.discardEditor)
        editor.finishPanelTest(.restoreEditor)
        assert(editor.window?.isVisible == false)
        editor.close()
        try checkSceneIntegration(model: model)
        print("Panel lifecycle checks passed: repeated tests, lock/unlock restoration, disable and shutdown.")
    }

    static func checkSceneIntegration(model: ApplicationModel) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TEotW-integration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let size = CGSize(width: 900, height: 600)
        let startup = try SceneStartup.load(canvasSize: size) { directory }
        assert(!startup.hasSavedScene && startup.scene.elements.isEmpty && startup.scene.canvasSize == size)
        assert(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("scene.json").path),
               "First-run resolution must not save the empty editing scene")
        let sceneEditor = SceneEditorWindowController(scene: startup.scene, store: startup.store)
        assert(sceneEditor.window != nil && sceneEditor.window?.contentView != nil,
               "Native primary editor must eagerly construct its first window")
        sceneEditor.flush()
        let untouched = try startup.store.load()
        assert(untouched == nil, "Closing or quitting an untouched editor retains legacy fallback")

        try startup.store.save(startup.scene)
        let savedEmpty = try SceneStartup.load(canvasSize: CGSize(width: 1, height: 1)) { directory }
        assert(savedEmpty.hasSavedScene && savedEmpty.scene == startup.scene,
               "An intentionally saved empty scene must remain distinguishable from first run")

        let document = directory.appendingPathComponent("scene.json")
        let corrupt = Data("corrupt original".utf8)
        try corrupt.write(to: document)
        let failed = try SceneStartup.load(canvasSize: size) { directory }
        assert(!failed.hasSavedScene && failed.persistenceError != nil)
        let blocked = SceneEditorWindowController(scene: failed.scene, store: failed.store)
        blocked.setPersistenceBlocked(failed.persistenceError!)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let canvas = descendants(blocked.window!.contentView!).compactMap { $0 as? SceneCanvasView }.first!
        canvas.createCenteredText()
        let text = descendants(canvas).compactMap { $0 as? NSTextView }.first!
        text.string = "Only in memory"
        text.didChangeText()
        blocked.flush()
        assert(blocked.scene.elements.first?.text == "Only in memory")
        blocked.close()
        let preserved = try Data(contentsOf: document)
        assert(preserved == corrupt,
               "Editing, flush and close after failed loading must never overwrite the damaged file")

        let unavailable = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: unavailable)
        let memoryOnly = try SceneStartup.load(canvasSize: size) { unavailable }
        assert(memoryOnly.persistenceError != nil && memoryOnly.temporaryDirectory != nil)
        if let temporary = memoryOnly.temporaryDirectory { try FileManager.default.removeItem(at: temporary) }

        let defaultDirectory = try SceneStartup.directoryArgument(in: ["app"])
        let overrideDirectory = try SceneStartup.directoryArgument(in: ["app", "--scene-directory", directory.path])
        assert(defaultDirectory == nil && overrideDirectory?.path == directory.path)
        for arguments in [["app", "--scene-directory"], ["app", "--scene-directory", "relative"],
                          ["app", "--scene-directory", "/a", "--scene-directory", "/b"]] {
            do { _ = try SceneStartup.directoryArgument(in: arguments); assertionFailure("Invalid diagnostic path accepted") }
            catch { }
        }
        assert(SceneScreenIdentity.matchingIndex(target: "launch", available: ["other", "launch"]) == 1)
        assert(SceneScreenIdentity.matchingIndex(target: "launch", available: ["other"]) == nil)
        assert(SceneScreenIdentity.matchingIndex(target: nil, available: ["other"]) == nil)
        assert(SceneScreenIdentity.matchingIndex(target: "launch", available: ["launch", "other"]) == 0)

        let menu = AppDelegate.makeEditMenu()
        let actions = menu.items.filter { !$0.isSeparatorItem }
        assert(actions.count == 11 && actions.allSatisfy { $0.target == nil })
        assert(actions.map { NSStringFromSelector($0.action!) } == ["undo:", "redo:", "cut:", "copy:", "paste:",
               "selectAll:", "duplicate:", "bringForward:", "sendBackward:", "bringToFront:", "sendToBack:"])
        assert(actions[1].keyEquivalentModifierMask == [.command, .shift])
        assert(actions[9].keyEquivalent == "]" && actions[10].keyEquivalent == "[")

        var created: [OverlayPanel] = []
        let routing = LockScreenController(model: model, readLockState: { false }, makePanels: {
            let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = true
            panel.contentView = CountdownView(overlay: true)
            created.append(panel)
            return [panel]
        }, scheduleAfter: { _, _ in })
        routing.start()
        routing.testPanel()
        assert(created.count == 1 && created[0].contentView is CountdownView)
        routing.sceneDidChange(startup.scene, store: startup.store)
        assert(created.count == 2 && !created[0].isVisible, "Changing content routes must hide the old panel first")
        assert((created[1].contentView as? SceneDisplayView)?.scene == startup.scene)
        var changed = startup.scene
        changed.elements = [SceneElement(kind: .text, frame: CGRect(x: 5, y: 5, width: 90, height: 30), text: "Live scene")]
        routing.sceneDidChange(changed, store: startup.store)
        assert(created.count == 2 && (created[1].contentView as? SceneDisplayView)?.scene == changed)
        routing.sceneDidChange(startup.scene, store: startup.store)
        assert(created[1].contentView is SceneDisplayView, "Empty committed content cannot restore countdown fallback")
        assert(!created[1].canBecomeKey && !created[1].canBecomeMain && created[1].ignoresMouseEvents)
        routing.stop()
        assert(created.allSatisfy { !$0.isVisible })

        sceneEditor.showEditor()
        var restoration = PanelTestWindowRestoration()
        restoration.hide(sceneEditor.window)
        restoration.finish(.deferEditor, window: sceneEditor.window)
        assert(sceneEditor.window?.isVisible == false)
        restoration.finish(.restoreEditor, window: sceneEditor.window)
        assert(sceneEditor.window?.isVisible == true)
        restoration.hide(sceneEditor.window)
        restoration.finish(.discardEditor, window: sceneEditor.window)
        restoration.finish(.restoreEditor, window: sceneEditor.window)
        assert(sceneEditor.window?.isVisible == false)
        sceneEditor.close()
        print("Scene integration checks passed: startup/error protection, private directory option, menu targets, screen identity, scene routing and editor restoration.")
    }
}
