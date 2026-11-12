import AppKit

/// Observe real AppKit invalidation requests without depending on when the host
/// WindowServer happens to service a visible layer's pending display.
private final class InvalidationObservingSceneView: SceneDisplayView {
    var invalidations = 0
    var clears = 0
    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if newValue { invalidations += 1 } else { clears += 1 }
            super.needsDisplay = newValue
        }
    }
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        invalidations += 1
        super.setNeedsDisplay(invalidRect)
    }
}

private final class FakeSpace: LockScreenSpaceManaging {
    var attachments = 0
    var teardowns = 0
    var succeeds = true
    func attach(_ window: NSWindow) -> Bool { attachments += 1; return succeeds }
    func tearDown() { teardowns += 1 }
}

@main struct LockScreenControllerTests {
    static func main() throws {
        let _ = NSApplication.shared
        checkRecovery()
        let model = ApplicationModel(catalog: EventCatalogModel(), settings: EditorSettingsModel())
        var locked = false
        var delayedActions: [() -> Void] = []
        var began = 0
        var completions: [PanelTestCompletion] = []
        let controller = LockScreenController(model: model, readLockState: { locked ? .locked : .unlocked }, diagnostic: { _ in }, makePanels: { [] },
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
        try checkTextPersistence(model: model)
        try checkMarkedTextPersistence(model: model)
        print("Panel lifecycle checks passed: repeated tests, lock/unlock restoration, disable and shutdown.")
    }

    static func checkRecovery() {
        let console = kCGSessionOnConsoleKey as String
        assert(decodeSessionState(nil) == .unknown)
        assert(decodeSessionState([console: true]) == .activeWithoutLockFlag)
        assert(decodeSessionState([console: true, "CGSSessionScreenIsLocked": "invalid"]) == .unknown)
        assert(decodeSessionState([console: false]) == .inactive)
        assert(decodeSessionState([console: true, "CGSSessionScreenIsLocked": true]) == .locked)
        assert(decodeSessionState([console: true, "CGSSessionScreenIsLocked": false]) == .unlocked)
        let model = ApplicationModel(catalog: EventCatalogModel(), settings: EditorSettingsModel())
        var state: LockSessionState = .unknown
        var created: [OverlayPanel] = []
        var attempts = 0
        let space = FakeSpace()
        var configuration = ["display:100x80"]
        let controller = LockScreenController(model: model, readLockState: { state }, makeSpace: { space }, diagnostic: { _ in }, makePanels: {
            attempts += 1
            if attempts == 1 { return [] }
            let panel = privatePanel(); created.append(panel); return [panel]
        }, screenConfiguration: { configuration }, scheduleAfter: { _, _ in })
        controller.start()
        assert(attempts == 0, "Unknown cold start remains hidden")
        let now = Date()
        state = .locked; controller.refresh(at: now)
        assert(attempts == 1)
        state = .unknown; controller.refresh(at: now.addingTimeInterval(1))
        assert(attempts == 1)
        controller.refresh(at: now.addingTimeInterval(3))
        assert(attempts == 2 && created[0].isVisible && space.attachments == 1)
        for tick in 4...100 { controller.refresh(at: now.addingTimeInterval(Double(tick))) }
        assert(created.count == 1 && space.attachments == 1 && created[0].isVisible)
        for _ in 0..<100 { _ = controller.perform(NSSelectorFromString("screensChanged")) }
        assert(created.count == 1 && space.attachments == 1 && space.teardowns == 0,
               "Unchanged screen notifications must not rebuild panels")
        configuration = ["display:120x80"]
        _ = controller.perform(NSSelectorFromString("screensChanged"))
        assert(created.count == 2 && space.teardowns == 1, "Changed geometry must rebuild")
        state = .locked
        _ = controller.perform(NSSelectorFromString("screenWake"))
        assert(space.attachments == 3, "Wake must reattach existing window")
        _ = controller.perform(NSSelectorFromString("sessionResigned"))
        assert(created[1].isVisible, "Confirmed locked resignation must retain panel")
        state = .unknown
        _ = controller.perform(NSSelectorFromString("sessionResigned"))
        assert(!created[1].isVisible && space.teardowns == 2)
        _ = controller.perform(NSSelectorFromString("screenWake"))
        assert(created.count == 2)
        state = .locked; controller.refresh(at: now.addingTimeInterval(101))
        assert(created.count == 3)
        state = .activeWithoutLockFlag; controller.refresh(at: now.addingTimeInterval(102))
        assert(created[2].isVisible)
        state = .locked; controller.refresh(at: now.addingTimeInterval(103))
        state = .activeWithoutLockFlag; controller.refresh(at: now.addingTimeInterval(104))
        assert(created[2].isVisible)
        controller.refresh(at: now.addingTimeInterval(105))
        assert(!created[2].isVisible)
        state = .inactive; controller.refresh(at: now.addingTimeInterval(106))
        assert(!created[2].isVisible)
        controller.refresh(at: now.addingTimeInterval(110))
        assert(created.count == 3)
        controller.stop()

        var factoryAttempts = 0
        var failures: [FakeSpace] = []
        var retries = 0
        var diagnostics: [String] = []
        let retryController = LockScreenController(model: model, readLockState: { .locked }, makeSpace: {
            factoryAttempts += 1
            if factoryAttempts == 1 { return nil }
            let next = FakeSpace()
            next.succeeds = factoryAttempts > 2
            failures.append(next)
            return next
        }, diagnostic: { diagnostics.append($0) }, makePanels: {
            retries += 1
            return [privatePanel()]
        }, scheduleAfter: { _, _ in })
        retryController.start()
        let retryAt = Date().addingTimeInterval(3)
        retryController.refresh(at: retryAt)
        assert(factoryAttempts == 2 && failures[0].teardowns == 1)
        retryController.refresh(at: retryAt.addingTimeInterval(1))
        assert(factoryAttempts == 2)
        retryController.refresh(at: retryAt.addingTimeInterval(3))
        assert(factoryAttempts == 3 && retries == 3 && failures[1].attachments == 1)
        retryController.stop()
        assert(failures[1].teardowns == 1)
        let diagnosticsAfterStop = diagnostics.count
        retryController.refresh(at: retryAt.addingTimeInterval(30))
        assert(factoryAttempts == 3 && retries == 3 && diagnostics.count == diagnosticsAfterStop, "Stopped controller must not recover panels or emit heartbeat")

        var session: LockSessionState = .unlocked
        var completions: [PanelTestCompletion] = []
        let restoration = LockScreenController(model: model, readLockState: { session }, makeSpace: { assertionFailure("No private space expected"); return nil }, diagnostic: { _ in }, makePanels: { [privatePanel()] }, scheduleAfter: { _, _ in })
        restoration.onTestDidEnd = { completions.append($0) }
        restoration.start()
        restoration.testPanel()
        session = .inactive
        _ = restoration.perform(NSSelectorFromString("sessionResigned"))
        assert(completions == [.deferEditor])
        session = .unknown
        _ = restoration.perform(NSSelectorFromString("screenWake"))
        assert(completions == [.deferEditor], "Unknown wake must not restore")
        session = .unlocked
        _ = restoration.perform(NSSelectorFromString("screenWake"))
        assert(completions == [.deferEditor, .restoreEditor])
        restoration.testPanel()
        session = .inactive
        _ = restoration.perform(NSSelectorFromString("sessionResigned"))
        session = .activeWithoutLockFlag
        restoration.refresh(at: retryAt)
        assert(completions.last == .deferEditor)
        restoration.refresh(at: retryAt.addingTimeInterval(1))
        assert(completions.last == .restoreEditor, "Confirmed missing lock flag restores deferred editor")
        restoration.stop()
    }

    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    static func privatePanel() -> OverlayPanel {
        OverlayPanel(screenFrame: CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    static func checkMarkedTextPersistence(model: ApplicationModel) throws {
        for ending in ["finish", "escape", "focus"] {
            for accepted in ["", "Принято"] {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                let store = try SceneStore(directory: directory)
                let empty = EditorSceneModel(canvasSize: CGSize(width: 800, height: 500))
                var panel: OverlayPanel?
                let routing = LockScreenController(model: model, readLockState: { .unlocked }, diagnostic: { _ in }, makePanels: {
                    let next = privatePanel(); panel = next; return [next]
                }, scheduleAfter: { _, _ in })
                routing.start(); routing.testPanel()
                defer { routing.stop() }
                let editor = SceneEditorWindowController(scene: empty, hasSavedScene: false, store: store)
                editor.onSceneChange = { routing.sceneDidChange($0, store: store) }
                let canvas = descendants(editor.window!.contentView!).compactMap { $0 as? SceneCanvasView }.first!
                canvas.createCenteredText()
                let field = descendants(canvas).compactMap { $0 as? NSTextView }.first!
                let selection = NSRange(location: NSNotFound, length: 0)
                if !accepted.isEmpty { field.insertText(accepted, replacementRange: selection) }
                field.setMarkedText("ка", selectedRange: NSRange(location: 2, length: 0), replacementRange: selection)
                RunLoop.main.run(until: Date().addingTimeInterval(0.65))
                assert(field.hasMarkedText() && editor.scene.elements[0].text == accepted)
                switch ending {
                case "finish": canvas.finishText()
                case "escape": field.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
                default: assert(editor.window!.makeFirstResponder(canvas))
                }
                let saved = try store.load()
                if accepted.isEmpty {
                    assert(editor.scene == empty && saved == nil && !editor.canUndo,
                           "\(ending) must keep a marked-only first edit out of persistence/history")
                    assert(panel?.contentView is CountdownView)
                } else {
                    assert(editor.scene.elements.count == 1 && editor.scene.elements[0].text == accepted)
                    assert(saved == editor.scene && (panel?.contentView as? SceneDisplayView)?.content == ScenePresentationController(store: store).content(for: editor.scene),
                           "\(ending) preserves the accepted prefix in both store and consumer")
                    canvas.undo(nil)
                    assert(editor.scene == empty && !editor.canUndo, "One Undo for accepted typing plus composition")
                }
                editor.close()
            }
        }
        print("Marked text persistence checks passed: finish/Escape/focus discard marked-only first edits, preserve accepted prefixes, fallback and single Undo.")
    }

    static func checkTextPersistence(model: ApplicationModel) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        let empty = EditorSceneModel(canvasSize: CGSize(width: 800, height: 500))
        var panel: OverlayPanel?
        let routing = LockScreenController(model: model, readLockState: { .unlocked }, diagnostic: { _ in }, makePanels: {
            let next = privatePanel()
            panel = next
            return [next]
        }, scheduleAfter: { _, _ in })
        routing.start()
        routing.testPanel()
        defer { routing.stop() }

        func editor(hasSavedScene: Bool) -> (SceneEditorWindowController, SceneCanvasView) {
            let editor = SceneEditorWindowController(scene: empty, hasSavedScene: hasSavedScene, store: store)
            editor.onSceneChange = { routing.sceneDidChange($0, store: store) }
            let canvas = descendants(editor.window!.contentView!).compactMap { $0 as? SceneCanvasView }.first!
            return (editor, canvas)
        }
        func begin(_ canvas: SceneCanvasView) -> NSTextView {
            canvas.createCenteredText()
            return descendants(canvas).compactMap { $0 as? NSTextView }.first!
        }
        func escape(_ field: NSTextView) { field.doCommand(by: #selector(NSResponder.cancelOperation(_:))) }
        func awaitDebounce() { RunLoop.main.run(until: Date().addingTimeInterval(0.65)) }
        func checkConsumer(_ expected: EditorSceneModel?) throws {
            let loaded = try store.load()
            assert(loaded == expected, "Persisted scene must agree with the active editor")
            if let expected {
                assert((panel?.contentView as? SceneDisplayView)?.content == ScenePresentationController(store: store).content(for: expected), "Panel must see the saved scene")
            } else { assert(panel?.contentView is CountdownView, "First-run legacy fallback must be restored") }
        }
        let (firstEditor, canvas) = editor(hasSavedScene: false)
        for waitForSave in [false, true] {
            let field = begin(canvas)
            field.insertText("А", replacementRange: NSRange(location: NSNotFound, length: 0))
            if waitForSave {
                awaitDebounce()
                assert(firstEditor.window?.firstResponder === field && !firstEditor.canUndo)
                assert(firstEditor.scene.elements.first?.text == "А")
                try checkConsumer(firstEditor.scene)
            }
            field.deleteBackward(nil)
            escape(field)
            assert(firstEditor.scene == empty && !firstEditor.canUndo)
            try checkConsumer(nil)
            awaitDebounce()
            try checkConsumer(nil)
        }

        let field = begin(canvas)
        let selection = NSRange(location: NSNotFound, length: 0)
        field.setMarkedText("ка", selectedRange: NSRange(location: 2, length: 0), replacementRange: selection)
        awaitDebounce()
        assert(field.hasMarkedText() && firstEditor.scene.elements.first?.text == "" && !firstEditor.canUndo)
        try checkConsumer(nil)
        field.insertText("Т", replacementRange: selection)
        field.setMarkedText("ка", selectedRange: NSRange(location: 2, length: 0), replacementRange: selection)
        assert(field.hasMarkedText(), "Exercise the native composing state")
        awaitDebounce()
        assert(field.hasMarkedText() && firstEditor.window?.firstResponder === field)
        assert(firstEditor.scene.elements.first?.text == "Т" && !firstEditor.canUndo)
        try checkConsumer(firstEditor.scene)
        field.insertText("екст", replacementRange: selection)
        awaitDebounce()
        assert(!field.hasMarkedText() && firstEditor.window?.firstResponder === field)
        assert(firstEditor.scene.elements.first?.text == "Текст" && !firstEditor.canUndo)
        try checkConsumer(firstEditor.scene)
        escape(field)
        assert(firstEditor.canUndo)
        canvas.editSelection()
        let existing = descendants(canvas).compactMap { $0 as? NSTextView }.first!
        existing.insertText("Новое", replacementRange: NSRange(location: 0, length: (existing.string as NSString).length))
        awaitDebounce()
        assert(firstEditor.window?.firstResponder === existing && firstEditor.scene.elements.first?.text == "Новое")
        try checkConsumer(firstEditor.scene)
        escape(existing)
        let committed = firstEditor.scene
        let discarded = begin(canvas)
        discarded.insertText("Я", replacementRange: selection)
        awaitDebounce()
        try checkConsumer(firstEditor.scene)
        discarded.deleteBackward(nil)
        escape(discarded)
        assert(firstEditor.scene == committed, "Discard preserves the existing nonempty document")
        try checkConsumer(committed)
        canvas.undo(nil)
        assert(firstEditor.scene.elements.first?.text == "Текст")
        canvas.undo(nil)
        assert(!firstEditor.canUndo && firstEditor.scene == empty, "Typing registers exactly one scene Undo on completion")
        canvas.redo(nil)
        canvas.redo(nil)
        canvas.deleteBackward(nil)
        assert(firstEditor.scene == empty)
        try checkConsumer(empty)
        firstEditor.close()

        // Reopen the deliberately empty document and discard another provisional insertion.
        let (reopened, secondCanvas) = editor(hasSavedScene: true)
        let provisional = begin(secondCanvas)
        provisional.insertText("Я", replacementRange: selection)
        awaitDebounce()
        try checkConsumer(reopened.scene)
        provisional.deleteBackward(nil)
        escape(provisional)
        assert(!reopened.canUndo)
        try checkConsumer(empty)
        reopened.close()
        print("Text persistence checks passed: active first typing and marked input, single Undo, immediate/debounced discard, committed empty document and fallback.")
    }

    static func checkSceneIntegration(model: ApplicationModel) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TEotW-integration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let size = CGSize(width: 900, height: 600)
        let startup = try SceneStartup.load(canvasSize: size) { directory }
        assert(!startup.hasSavedScene && startup.scene.elements.isEmpty && startup.scene.canvasSize == size)
        assert(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("scene.json").path),
               "First-run resolution must not save the empty editing scene")
        let sceneEditor = SceneEditorWindowController(scene: startup.scene, hasSavedScene: startup.hasSavedScene, store: startup.store)
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
        let blocked = SceneEditorWindowController(scene: failed.scene, hasSavedScene: failed.hasSavedScene, store: failed.store)
        blocked.setPersistenceBlocked(failed.persistenceError!)
        let canvas = descendants(blocked.window!.contentView!).compactMap { $0 as? SceneCanvasView }.first!
        canvas.createCenteredText()
        let text = descendants(canvas).compactMap { $0 as? NSTextView }.first!
        text.string = "Only in memory"
        text.didChangeText()
        blocked.flush()
        assert(blocked.scene.elements.first?.text == "Only in memory")
        let discarded = { () -> NSTextView in
            canvas.createCenteredText()
            return descendants(canvas).compactMap { $0 as? NSTextView }.first!
        }()
        discarded.insertText("Я", replacementRange: NSRange(location: NSNotFound, length: 0))
        discarded.deleteBackward(nil)
        discarded.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        for accepted in ["", "Принято"] {
            let before = blocked.scene
            canvas.createCenteredText()
            let marked = descendants(canvas).compactMap { $0 as? NSTextView }.first!
            let selection = NSRange(location: NSNotFound, length: 0)
            if !accepted.isEmpty { marked.insertText(accepted, replacementRange: selection) }
            marked.setMarkedText("ка", selectedRange: NSRange(location: 2, length: 0), replacementRange: selection)
            canvas.finishText()
            if accepted.isEmpty { assert(blocked.scene == before) }
            else { assert(blocked.scene.elements.count == before.elements.count + 1 && blocked.scene.elements.last?.text == accepted) }
        }
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

        for frame in [NSRect(x: 1440, y: 0, width: 1280, height: 800),
                      NSRect(x: -1280, y: 900, width: 1280, height: 720),
                      NSRect(x: 160, y: -1080, width: 1920, height: 1080)] {
            let placed = OverlayPanel(screenFrame: frame)
            assert(placed.frame == frame, "The actual panel must occupy its matched global display rectangle")
            placed.close()
        }

        let menu = AppDelegate.makeEditMenu()
        let actions = menu.items.filter { !$0.isSeparatorItem }
        assert(actions.count == 11 && actions.allSatisfy { $0.target == nil })
        assert(actions.map { NSStringFromSelector($0.action!) } == ["undo:", "redo:", "cut:", "copy:", "paste:",
               "selectAll:", "duplicate:", "bringForward:", "sendBackward:", "bringToFront:", "sendToBack:"])
        assert(actions[1].keyEquivalentModifierMask == [.command, .shift])
        assert(actions[9].keyEquivalent == "]" && actions[10].keyEquivalent == "[")

        var created: [OverlayPanel] = []
        let routing = LockScreenController(model: model, readLockState: { .unlocked }, diagnostic: { _ in }, makePanels: {
            let panel = privatePanel()
            created.append(panel)
            return [panel]
        }, scheduleAfter: { _, _ in })
        routing.start()
        routing.testPanel()
        assert(created.count == 1 && created[0].contentView is CountdownView)
        routing.sceneDidChange(startup.scene, store: startup.store)
        assert(created.count == 2 && !created[0].isVisible, "Changing content routes must hide the old panel first")
        assert((created[1].contentView as? SceneDisplayView)?.content == ScenePresentationController(store: startup.store).content(for: startup.scene))
        let display = InvalidationObservingSceneView(content: ScenePresentationController(store: startup.store).content(for: startup.scene))
        created[1].contentView = display
        let clean = display.invalidations
        for tick in 1...3 {
            routing.refresh(at: Date(timeIntervalSince1970: Double(1_800_000_000 + tick)))
            assert(display.invalidations == clean, "Tick dirtied view")
        }
        routing.settingsDidChange()
        assert(display.invalidations == clean, "Countdown ticks and legacy settings must leave a static composition clean")
        routing.sceneDidChange(startup.scene, store: startup.store)
        assert(display.invalidations == clean, "Publishing an unchanged snapshot must leave the view clean")
        display.setFrameSize(CGSize(width: display.frame.width + 10, height: display.frame.height))
        assert(display.invalidations > clean, "Resizing the display view must redraw its viewport")
        let resized = display.invalidations
        display.setNeedsDisplay(display.bounds)
        let clears = display.clears
        routing.refresh(at: Date())
        assert(display.invalidations > resized && display.clears == clears,
               "AppKit display requests must survive countdown refresh")
        let beforeEdit = display.invalidations
        var changed = startup.scene
        changed.elements = [SceneElementModel(kind: .text, frame: CGRect(x: 5, y: 5, width: 90, height: 30), text: "Live scene")]
        routing.sceneDidChange(changed, store: startup.store)
        assert(created.count == 2 && display.content == ScenePresentationController(store: startup.store).content(for: changed) && display.invalidations > beforeEdit)
        // Shared clock exercises real scene panel updates without locking the host.
        let clockNow = Date(timeIntervalSince1970: 1_800_000_000)
        var timer = SceneElementModel(kind: .countdown, frame: CGRect(x: 0,y: 0,width: 320,height: 80))
        timer.countdown = SceneCountdownModel(targetDate: clockNow.addingTimeInterval(125), timeZoneID: "UTC")
        var ticking = EditorSceneModel(canvasSize: size, elements: [timer])
        routing.sceneDidChange(ticking, store: startup.store)
        let timerState = SceneEditingStateModel(ticking)
        let timerCanvas = SceneCanvasController(state: timerState, store: startup.store, catalog: model.catalog, now: clockNow)
        var stateUpdates = 0; timerState.onUpdate = { _ in stateUpdates += 1 }
        let commonClock = CountdownController { instant in
            timerCanvas.refresh(at: instant)
            routing.refresh(at: instant)
        }
        commonClock.refresh(at: clockNow)
        let dynamicClean = display.invalidations
        let canvasBefore = timerCanvas.view.renderedContent
        commonClock.refresh(at: clockNow.addingTimeInterval(1))
        assert(display.invalidations > dynamicClean && timerCanvas.view.renderedContent != canvasBefore, "One shared second refreshes both timer views")
        assert(display.content == ScenePresentationController(store: startup.store).content(for: ticking,catalog: model.catalog,at: clockNow.addingTimeInterval(1)), "Overlay uses the supplied shared instant")
        assert(timerCanvas.view.renderedContent == display.content, "Canvas and actual overlay share identical values")
        ticking.elements[0].countdown?.showsSeconds = false
        routing.sceneDidChange(ticking,store: startup.store)
        routing.refresh(at: clockNow)
        let minuteClean = display.invalidations
        routing.refresh(at: clockNow.addingTimeInterval(1))
        assert(display.invalidations == minuteClean, "Seconds-disabled timer is not dirtied every second")
        routing.refresh(at: clockNow.addingTimeInterval(6))
        assert(display.invalidations > minuteClean, "Minute boundary invalidates once")
        commonClock.refresh(at: clockNow.addingTimeInterval(86400))
        let exhaustedClean = display.invalidations
        routing.refresh(at: clockNow.addingTimeInterval(86401))
        assert(display.invalidations == exhaustedClean && stateUpdates == 0 && !timerState.canUndo, "Wake recomputes expiry; expired ticks add neither invalidation nor scene history")
        assert(created.count == 2, "Dynamic values never recreate panels")
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
