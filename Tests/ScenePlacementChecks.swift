import AppKit

enum ScenePlacementChecks {
    private static func check(_ value: Bool, _ message: String) { precondition(value, message) }
    private static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    private static func event(_ type: NSEvent.EventType, point: CGPoint, view: SceneCanvasView, clicks: Int = 1) -> NSEvent {
        let location = view.convert(view.viewport.viewPoint(point), to: nil)
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
            windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }
    private static func click(_ point: CGPoint, view: SceneCanvasView) {
        view.mouseDown(with: event(.leftMouseDown, point: point, view: view))
        view.mouseUp(with: event(.leftMouseUp, point: point, view: view))
    }
    private static func escape(_ view: SceneCanvasView) { view.cancelOperation(nil) }
    private static func menu(_ point: CGPoint, view: SceneCanvasView) -> NSMenu {
        view.menu(for: event(.rightMouseDown, point: point, view: view))!
    }
    private static func invoke(_ title: String, in menu: NSMenu) {
        let item = menu.item(withTitle: title)!
        check(item.isEnabled && item.action != nil, "Menu action is available: \(title)")
        check(NSApp.sendAction(item.action!, to: item.target, from: item), "Native menu target/action dispatches: \(title)")
    }
    private static func image(_ color: NSColor) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill(); NSRect(x: 0, y: 0, width: 40, height: 20).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let size = CGSize(width: 800, height: 500), point = CGPoint(x: 400, y: 250)
        for tool in SceneCanvasTool.allCases {
            let state = SceneEditingStateModel(.init(canvasSize: size))
            let controller = SceneCanvasController(state: state, store: store)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = controller.view
            defer { window.close() }
            var picked: CGPoint?
            controller.onPickImage = { picked = $0 }
            controller.arm(tool)
            check(state.scene.elements.isEmpty && !state.canUndo, "Arming a tool does not create or save: \(tool)")
            escape(controller.view); click(point, view: controller.view)
            check(state.scene.elements.isEmpty && picked == nil, "Escape cancels tool: \(tool)")
            controller.arm(tool)
            click(CGPoint(x: -50, y: -50), view: controller.view)
            check(state.scene.elements.isEmpty && picked == nil, "Outside canvas cannot place: \(tool)")
            click(point, view: controller.view)
            if tool == .image {
                check(picked.map { hypot($0.x-point.x, $0.y-point.y) < 0.001 } == true && state.scene.elements.isEmpty, "Photo dialog requested after click, with no provisional layer")
                picked = nil; click(point, view: controller.view)
                check(picked == nil && !state.canUndo, "Cancelled image picker leaves selection mode and no Undo")
                continue
            }
            if tool == .text || tool == .note {
                let input = views(controller.view).compactMap { $0 as? NSTextView }.first!
                input.insertText("Проверка", replacementRange: input.selectedRange()); controller.finishText()
            }
            check(state.scene.elements.count == 1 && state.canUndo, "Placement creates exactly one element: \(tool)")
            let element = state.scene.elements[0]
            let anchor = tool == .text ? element.frame.origin : CGPoint(x: element.frame.midX, y: element.frame.midY)
            check(hypot(anchor.x-point.x, anchor.y-point.y) < 0.001, "Placement anchor follows clicked point: \(tool)")
            let saved = state.scene
            state.undo(); check(state.scene.elements.isEmpty && !state.canUndo, "Placement is one Undo: \(tool)")
            state.redo(); check(state.scene == saved, "Placement supports Redo: \(tool)")
            if tool == .text {
                state.undo(); controller.arm(.text)
                let start = CGPoint(x: 250, y: 160), end = CGPoint(x: 450, y: 220)
                controller.view.mouseDown(with: event(.leftMouseDown, point: start, view: controller.view))
                controller.view.mouseDragged(with: event(.leftMouseDragged, point: end, view: controller.view))
                controller.view.mouseUp(with: event(.leftMouseUp, point: end, view: controller.view))
                let input = views(controller.view).compactMap { $0 as? NSTextView }.first!
                input.insertText("Рамка", replacementRange: input.selectedRange()); controller.finishText()
                let framed = state.scene.elements[0]
                check(abs(framed.frame.minX-start.x) < 0.001 && abs(framed.frame.width-200) < 0.001 && framed.autoTextWidth == false, "Text drag places a fixed-width frame")
                state.undo(); controller.arm(.text)
                controller.view.mouseDown(with: event(.leftMouseDown, point: start, view: controller.view))
                controller.view.mouseDragged(with: event(.leftMouseDragged, point: end, view: controller.view))
                escape(controller.view)
                controller.view.mouseUp(with: event(.leftMouseUp, point: end, view: controller.view))
                check(state.scene.elements.isEmpty && !state.canUndo, "Escape during placement drag leaves no provisional text or Undo")
            }
        }

        var a = SceneElementModel(kind: .text, frame: CGRect(x: 50, y: 60, width: 100, height: 60), text: "A")
        let b = SceneElementModel(kind: .text, frame: CGRect(x: 220, y: 60, width: 100, height: 60), text: "B")
        a.rotation = 25
        let state = SceneEditingStateModel(.init(canvasSize: size, elements: [a,b]))
        let canvas = SceneCanvasController(state: state, store: store); canvas.contextPasteboard = board
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas.view
        defer { window.close() }
        let aPoint = CGPoint(x: a.frame.midX, y: a.frame.midY), bPoint = CGPoint(x: b.frame.midX, y: b.frame.midY)
        let blank = CGPoint(x: 700, y: 400)
        board.clearContents()
        let emptyMenu = menu(blank, view: canvas.view)
        check(emptyMenu.items.map(\.title) == ["Добавить", "Вставить сюда"] && !emptyMenu.item(withTitle: "Вставить сюда")!.isEnabled, "Empty canvas menu and unavailable paste")
        let addMenu = emptyMenu.item(withTitle: "Добавить")!.submenu!
        invoke("Часы", in: addMenu)
        check(state.scene.elements.last!.kind == .clock && state.canUndo, "Context creation runs immediately without another click")
        state.undo()
        _ = menu(aPoint, view: canvas.view)
        check(state.selection == [a.id], "Right-click selects unselected element")
        state.select([a.id,b.id]); canvas.refresh()
        let multi = menu(aPoint, view: canvas.view)
        check(state.selection == [a.id,b.id], "Right-click inside multiselection preserves the set")
        check(multi.item(withTitle: "Сгруппировать выделенное")!.isEnabled && !multi.item(withTitle: "Разгруппировать")!.isEnabled, "Grouping applicability")
        invoke("Копировать", in: multi)
        check(board.availableType(from: [SceneTransfer.layerType]) != nil, "Context copy uses existing private layer format")
        invoke("Сгруппировать выделенное", in: multi)
        check(menu(aPoint, view: canvas.view).item(withTitle: "Разгруппировать")!.isEnabled, "Group menu offers ungroup")
        let grouped = state.scene
        invoke("Заблокировать", in: menu(aPoint, view: canvas.view))
        check(state.selected.allSatisfy(\.isLocked) && state.hit(aPoint) == nil && state.hit(bPoint) == nil, "Group lock excludes leaves from cursor hit testing")
        check(state.marquee(CGRect(origin: .zero, size: size)).isEmpty, "Marquee excludes locked leaves")
        check(menu(aPoint, view: canvas.view).item(withTitle: "Разблокировать")?.isEnabled == true, "Already-selected locked group offers context Unlock without cursor selection")
        click(aPoint, view: canvas.view)
        check(state.selection.isEmpty, "Clicking locked geometry cannot select it")
        state.select([a.id], expandingGroups: false)
        let inspectorView = SceneInspectorView(frame: .zero)
        let inspector = SceneInspectorController(state: state, view: inspectorView)
        inspector.applyField(key: "x", raw: "80", label: "X")
        check(state.scene.elements[0].frame.minX == 80 && state.scene.elements[0].isLocked, "Layer selection permits inspector changes while locked")
        state.undo(); state.undo()
        check(state.scene == grouped, "Inspector change and lock each have one Undo")
        state.toggleLocked([a.id]); state.selectFromCanvas([b.id])
        check(state.selection == [b.id] && state.marquee(CGRect(origin: .zero, size: size)) == [b.id], "Group expansion never reselects a locked child")
        inspector.refresh()
        check(inspector.makePresentation().layerLocks.contains(2), "Partially locked group has mixed lock presentation")
        let table = views(inspectorView).compactMap { $0 as? NSTableView }.first!
        let row = inspectorView.tableView(table, viewFor: table.tableColumns[0], row: 0)!
        let lockButton = views(row).compactMap { $0 as? NSButton }.first!
        let selection = state.selection
        lockButton.performClick(nil)
        check(state.scene.elements.allSatisfy(\.isLocked) && state.selection == selection, "Group lock button applies to descendants without replacing selection")
        let beforeSave = state.scene
        try store.save(beforeSave)
        check(try store.load() == beforeSave, "Locked flags survive scene persistence")
        let copied = SceneEditingStateModel(.init(canvasSize: size))
        copied.insertCopies(beforeSave.elements, at: point)
        check(copied.scene.elements.allSatisfy(\.isLocked) && Set(copied.scene.elements.map(\.id)).isDisjoint(with: beforeSave.elements.map(\.id)), "Copies preserve locks with independent IDs")
        let copiedBounds = SceneGeometry.bounds(copied.selected)!
        check(hypot(copiedBounds.midX-point.x, copiedBounds.midY-point.y) < 0.001, "Paste-here centers transformed bounds exactly")
        let json = try JSONEncoder().encode(EditorSceneModel(canvasSize: size, elements: [b]))
        check(!String(decoding: json, as: UTF8.self).contains("\"locked\""), "Unlocked legacy-compatible scenes omit optional lock field")

        try windowPaste(store: store, board: board, size: size)
        inspectorDraftContext(store: store, board: board, size: size)
        print("Placement checks passed: tools, Escape, context menus, paste-here/replacement, locks, layers, persistence and Undo")
    }

    private static func inspectorDraftContext(store: SceneStore, board: NSPasteboard, size: CGSize) {
        let a = SceneElementModel(kind: .text, frame: CGRect(x: 80, y: 90, width: 100, height: 60), text: "A")
        let b = SceneElementModel(kind: .text, frame: CGRect(x: 350, y: 90, width: 100, height: 60), text: "B")
        for target in [CGPoint(x: b.frame.midX, y: b.frame.midY), CGPoint(x: 700, y: 400)] {
            let editor = SceneEditorWindowController(scene: .init(canvasSize: size, elements: [a,b]), hasSavedScene: false, store: store, pasteboard: board)
            defer { editor.close() }
            let window = editor.window!, root = window.contentView!
            window.layoutIfNeeded()
            let canvas = views(root).compactMap { $0 as? SceneCanvasView }.first!
            let inspector = views(root).compactMap { $0 as? SceneInspectorView }.first!
            click(CGPoint(x: a.frame.midX, y: a.frame.midY), view: canvas)
            let field = views(inspector).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "x" }!
            check(window.makeFirstResponder(field), "Native inspector field accepts focus")
            let input = field.currentEditor() as! NSTextView
            input.string = "140"
            inspector.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            _ = menu(target, view: canvas)
            check(editor.scene.elements[0].frame.minX == 140 && editor.scene.elements[1] == b, "Context selection commits old inspector draft to A before selecting B or empty canvas")
            canvas.undo(nil)
            check(editor.scene.elements == [a,b] && !editor.canUndo, "Inspector draft remains one Undo before context command")
        }
    }

    private static func windowPaste(store: SceneStore, board: NSPasteboard, size: CGSize) throws {
        let state = SceneEditingStateModel(.init(canvasSize: size))
        let images = SceneImageController(state: state, store: store)
        try images.importImages([.init(data: image(.red))], at: .add(CGPoint(x: 250, y: 180)))
        let original = state.scene.elements[0]
        let editor = SceneEditorWindowController(scene: state.scene, hasSavedScene: false, store: store, pasteboard: board)
        defer { editor.close() }
        editor.window!.layoutIfNeeded()
        let view = views(editor.window!.contentView!).compactMap { $0 as? SceneCanvasView }.first!
        let imagePoint = CGPoint(x: original.frame.midX, y: original.frame.midY)
        board.clearContents(); board.setData(image(.blue), forType: .png)
        let imageMenu = menu(imagePoint, view: view)
        check(imageMenu.item(withTitle: "Вставить с заменой")!.isEnabled, "Image clipboard enables replacement")
        invoke("Вставить сюда", in: imageMenu)
        check(editor.scene.elements.count == 2 && editor.scene.elements[0] == original, "Paste-here over selected image adds instead of replacing")
        let newPhoto = editor.scene.elements[1]
        check(hypot(newPhoto.frame.midX-imagePoint.x, newPhoto.frame.midY-imagePoint.y) < 0.001, "Photo paste follows context point")
        view.undo(nil)
        invoke("Вставить с заменой", in: menu(imagePoint, view: view))
        check(editor.scene.elements.count == 1 && editor.scene.elements[0].id == original.id && editor.scene.elements[0].frame == original.frame && editor.scene.elements[0].assetID != original.assetID, "Replacement retains target identity and geometry via existing importer")
        view.undo(nil); check(editor.scene.elements == [original], "Replacement is one Undo")
        board.clearContents(); board.setString("Текст в точке", forType: .string)
        let point = CGPoint(x: 650, y: 350)
        invoke("Вставить сюда", in: menu(point, view: view))
        let text = editor.scene.elements.last!
        check(text.text == "Текст в точке" && hypot(text.frame.minX-point.x, text.frame.minY-point.y) < 0.001, "Text paste-here uses context anchor")
        view.undo(nil)
        let layer = SceneElementModel(kind: .text, frame: CGRect(x: 20, y: 30, width: 100, height: 60), text: "Копия")
        _ = try SceneTransfer.write([layer], to: board)
        invoke("Вставить сюда", in: menu(point, view: view))
        let added = editor.scene.elements.last!
        check(added.id != layer.id && added.text == layer.text && abs(added.frame.midX-point.x) < 0.001 && abs(added.frame.midY-point.y) < 0.001, "Private layers paste-here remaps IDs and centers bounds")
        view.undo(nil)
        board.clearContents(); board.setData(Data([1,2,3]), forType: .png)
        invoke("Вставить с заменой", in: menu(imagePoint, view: view))
        check(editor.scene.elements == [original], "Rejected image replacement preserves entire scene")
        let add = views(editor.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Добавить" }!
        add.selectItem(at: 4)
        check(add.sendAction(add.action!, to: add.target) && editor.scene.elements == [original], "Toolbar arms countdown without inserting at center")
        let insertion = CGPoint(x: 500, y: 300)
        click(insertion, view: view)
        let timer = editor.scene.elements.last!
        check(timer.kind == .countdown && hypot(timer.frame.midX-insertion.x, timer.frame.midY-insertion.y) < 0.001, "Toolbar countdown waits for chosen canvas point")
        view.undo(nil)
        check(editor.scene.elements == [original], "Toolbar placement is one Undo")
    }
}
