import AppKit

enum SceneEditorShellChecks {
    private static func check(_ value: Bool, _ message: String) { precondition(value, message) }
    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    private static func button(_ id: String, in root: NSView) -> NSButton {
        descendants(root).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id }!
    }
    private static func click(_ button: NSButton) { button.performClick(nil) }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        var a = SceneElementModel(kind: .text, frame: CGRect(x: 100, y: 100, width: 250, height: 100), text: "Слои и ориентиры")
        a.autoTextWidth = false
        let b = SceneElementModel(kind: .note, frame: CGRect(x: 400, y: 200, width: 200, height: 160), text: "Заметка")
        let state = SceneEditingStateModel(EditorSceneModel(canvasSize: CGSize(width: 800, height: 500), elements: [a,b]))
        state.select([a.id,b.id]); state.groupSelection()
        let inspector = SceneInspectorView(frame: .zero)
        let controller = SceneInspectorController(state: state, view: inspector)
        controller.refresh()
        let table = descendants(inspector).compactMap { $0 as? NSTableView }.first!
        let disclosure = button("layers-disclosure", in: inspector)
        let selected = table.selectedRowIndexes, before = state.value
        var updates = 0; state.onUpdate = { _ in updates += 1 }
        click(disclosure)
        check(!inspector.layersExpanded && table.enclosingScrollView!.isHidden, "Collapsing hides the layer table")
        check(state.value == before && updates == 0, "Disclosure does not change scene, selection or history")
        controller.refresh()
        check(!inspector.layersExpanded && table.selectedRowIndexes == selected, "Refresh preserves collapsed selection")
        state.select([a.id], expandingGroups: false); controller.refresh()
        let childSelection = table.selectedRowIndexes
        click(disclosure)
        check(inspector.layersExpanded && !table.enclosingScrollView!.isHidden, "Disclosure restores the table")
        check(table.selectedRowIndexes == childSelection && state.selection == [a.id], "Reopening preserves child selection")

        let scene = state.scene
        try store.save(scene)
        let sceneURL = directory.appendingPathComponent("scene.json")
        let saved = try Data(contentsOf: sceneURL)
        let editor = SceneEditorWindowController(scene: scene, hasSavedScene: true, store: store)
        defer { editor.close() }
        let window = editor.window!, root = window.contentView!
        window.orderFront(nil)
        window.layoutIfNeeded()
        let canvas = descendants(root).compactMap { $0 as? SceneCanvasView }.first!
        let login = button("login-guide", in: root), clock = button("clock-guide", in: root)
        let notice = editor.clockPopover
        let help = button("clock-guide-help", in: root)
        let popoverContent = notice.contentViewController!.view
        let canvasFrame = canvas.frame, windowFrame = window.frame
        check(!notice.isShown, "Clock popover starts closed")
        var published = 0; editor.onSceneChange = { _ in published += 1 }
        click(login)
        check(!canvas.guides && canvas.clock && clock.isEnabled, "Hiding login keeps clock enabled and visible")
        click(clock)
        check(!canvas.clock && !notice.isShown && !canvas.guides, "Clock switches off independently without opening help")
        click(help)
        check(notice.isShown && !canvas.clock, "Only the help button opens the popover")
        window.layoutIfNeeded()
        check(canvas.frame == canvasFrame && window.frame == windowFrame, "Showing help preserves panel and canvas geometry")
        click(button("clock-guide-dismiss", in: popoverContent))
        check(!notice.isShown && !canvas.clock && clock.state == .off, "Dismissing popover does not restore clock")
        click(help)
        check(notice.isShown && !canvas.clock, "Help button reopens the popover without changing clock")
        click(help)
        check(!notice.isShown, "Help button toggles popover closed")
        click(login)
        check(canvas.guides && !canvas.clock, "Showing login does not restore clock")
        click(clock); click(clock)
        check(!notice.isShown, "Repeated guide toggles do not open help")
        click(help)
        var opened = 0
        editor.onOpenSystemSettings = { opened += 1; return true }
        click(button("clock-guide-settings", in: popoverContent))
        check(opened == 1 && !canvas.clock && notice.isShown, "Settings action does not mutate guide state")
        notice.performClose(nil)
        editor.refresh(at: Date().addingTimeInterval(5))
        editor.flush()
        check(editor.scene == scene && !editor.canUndo && published == 0, "Editor UI changes do not save or create document history")
        check(try Data(contentsOf: sceneURL) == saved, "Disclosure and guides preserve saved bytes")
        let buttons = descendants(root).compactMap { $0 as? NSButton }
        check(!buttons.contains { button in
            [button.title, button.accessibilityLabel() ?? "", button.toolTip ?? ""].contains {
                ["Редактор отсчёта…", "Отменить", "Повторить"].contains($0)
            }
        }, "Obsolete editor and history buttons, including image-only buttons, are absent")

        // Use the real responder chain from the canvas, then the native text view.
        let center = canvas.convert(canvas.viewport.viewPoint(CGPoint(x: a.frame.midX, y: a.frame.midY)), to: nil)
        func mouse(_ type: NSEvent.EventType, clicks: Int) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: center, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, clicks: 1)); canvas.mouseUp(with: mouse(.leftMouseUp, clicks: 1))
        let original = editor.scene
        let arrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
        canvas.keyDown(with: arrow)
        let moved = editor.scene
        check(moved != original && editor.canUndo, "Canvas movement creates document history")
        check(window.firstResponder?.tryToPerform(NSSelectorFromString("undo:"), with: nil) == true && editor.scene == original, "Responder-chain Undo restores scene")
        check(window.firstResponder?.tryToPerform(NSSelectorFromString("redo:"), with: nil) == true && editor.scene == moved, "Responder-chain Redo restores scene")
        canvas.mouseDown(with: mouse(.leftMouseDown, clicks: 2))
        let input = descendants(canvas).compactMap { $0 as? NSTextView }.first!
        check(window.firstResponder === input, "Native text owns keyboard focus")
        input.setSelectedRange(NSRange(location: (input.string as NSString).length, length: 0))
        input.insertText("!", replacementRange: input.selectedRange())
        check(input.string == a.text + "!", "Native text receives insertion")
        check(window.firstResponder?.tryToPerform(NSSelectorFromString("undo:"), with: nil) == true && input.string == a.text, "Undo first uses native text history")
        check(window.firstResponder?.tryToPerform(NSSelectorFromString("redo:"), with: nil) == true && input.string == a.text + "!", "Redo first uses native text history")
        print("Scene editor shell checks passed: disclosure, independent guides, notice, persistence and responder history")
    }
}
