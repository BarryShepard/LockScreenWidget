import AppKit

@main struct SceneEditingTests {
    static func check(_ ok: Bool, _ message: String) { precondition(ok, message) }
    static let size = CGSize(width: 800,height: 500)
    static func item(_ x: CGFloat) -> SceneElementModel {
        SceneElementModel(kind: .text, frame: CGRect(x: x,y: 100,width: 100,height: 20))
    }
    static func geometryAndHistory() {
        var a = item(100); a.rotation = 45
        let b = item(300), c = item(500), d = item(650)
        let model = SceneEditingStateModel(EditorSceneModel(canvasSize: size,elements: [a,b,c,d]))
        check(model.marquee(CGRect(x: 110,y: 70,width: 10,height: 10)) == [a.id], "Partially intersect rotated edge")
        check(model.marquee(CGRect(x: 109,y: 140,width: 4,height: 4)).isEmpty, "Rotated bounding box has empty corners")
        check(model.marquee(CGRect(x: 398,y: 117,width: 15,height: 8)) == [b.id], "Partial unrotated marquee")
        model.select([a.id,c.id]); let original = model.value
        model.reorder(.forward)
        check(model.scene.elements.map(\.id) == [b.id,a.id,d.id,c.id], "Separate selections each advance one")
        model.undo(); check(model.value == original, "Undo restores IDs and selection")
        model.redo(); model.reorder(.front)
        check(model.scene.elements.map(\.id) == [b.id,d.id,a.id,c.id], "Stable front order")
        model.reorder(.back); check(model.scene.elements.map(\.id) == [a.id,c.id,b.id,d.id], "Stable back order")
        let before = model.value
        let duplicated = SceneEditingStateModel.inserting(model.selected, into: before, offset: 0)
        model.preview(SceneEditingStateModel.moved(duplicated, dx: 5, dy: -10))
        model.preview(SceneEditingStateModel.moved(duplicated, dx: 20, dy: -30)); model.finish(from: before)
        check(Array(model.scene.elements.prefix(4)) == before.scene.elements && model.selected.count == 2, "Option drag keeps originals")
        check(model.selection.isDisjoint(with: before.selection) && model.selected[0].frame == a.frame.offsetBy(dx: 20,dy: -30), "Only copies move")
        model.undo(); check(model.value == before, "One undo for entire duplicate drag")
        model.redo()
        let owners = model.selected, oldDiff = owners[1].frame.minX-owners[0].frame.minX
        model.center(horizontal: true)
        check(abs(SceneGeometry.bounds(model.selected)!.midX - size.width/2) < 0.0001 &&
              abs(model.selected[1].frame.minX-model.selected[0].frame.minX-oldDiff) < 0.0001, "Center group without changing spacing")
        model.deleteSelection(); check(model.selection.isEmpty && model.scene.elements.count == 4, "Delete clears selection")
        model.undo(); check(model.selection.count == 2, "Undo deletion restores selected group")
    }
    static func transforms() {
        var photo = SceneElementModel(kind: .image, frame: CGRect(x: 100, y: 100, width: 120, height: 80), rotation: 37,
                                      assetID: "original.png", imageRect: CGRect(x: -30, y: -20, width: 180, height: 120))
        let state = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [photo]))
        state.select([photo.id]); let original = state.value
        let targets = SceneTransformController.targets([photo], scale: 1)
        let corner = targets.first { !$0.rotation && $0.handle.x == 1 && $0.handle.y == 1 }!
        let grab = CGPoint(x: corner.point.x+3, y: corner.point.y-2)
        check(SceneTransformController.applying(original, target: corner, from: grab, to: grab, stretch: false, crop: false) == original, "Off-center grab does not jump")
        let delta = SceneTransformController.rotate(CGPoint(x: 30, y: 10), 37 * .pi/180)
        let moved = CGPoint(x: grab.x+delta.x, y: grab.y+delta.y)
        let resized = SceneTransformController.applying(original, target: corner, from: grab, to: moved, stretch: false, crop: false)
        let before = SceneGeometry.corners(photo)[0], after = SceneGeometry.corners(resized.scene.elements[0])[0]
        check(hypot(before.x-after.x, before.y-after.y) < 0.0001, "Opposite rotated corner remains anchored")
        check(abs(resized.scene.elements[0].frame.width / photo.frame.width - resized.scene.elements[0].frame.height / photo.frame.height) < 0.0001, "Corner resize is proportional")
        let stretched = SceneTransformController.applying(original, target: corner, from: grab, to: moved, stretch: true, crop: false)
        check(abs(stretched.scene.elements[0].frame.width / photo.frame.width - 1.25) < 0.0001 && abs(stretched.scene.elements[0].frame.height / photo.frame.height - 1.125) < 0.0001, "Shift stretches axes independently")
        state.preview(resized); state.finish(from: original); state.undo(); check(state.value == original && !state.canUndo, "One gesture is one undo")
        for h in SceneTransformController.handles {
            let target = targets.first { !$0.rotation && $0.handle == h }!
            let d = SceneTransformController.rotate(CGPoint(x: CGFloat(h.x)*(-10), y: CGFloat(h.y)*(-8)), 37 * .pi/180)
            let cropped = SceneTransformController.applying(original, target: target, from: target.point, to: CGPoint(x: target.point.x+d.x, y: target.point.y+d.y), stretch: false, crop: true).scene.elements[0]
            func imageOrigin(_ e: SceneElementModel) -> CGPoint {
                let r = e.imageRect!, v = SceneTransformController.rotate(CGPoint(x: r.minX-e.frame.width/2, y: r.minY-e.frame.height/2), e.rotation * .pi/180)
                return CGPoint(x: e.frame.midX+v.x, y: e.frame.midY+v.y)
            }
            let p = imageOrigin(photo), q = imageOrigin(cropped)
            check(hypot(p.x-q.x, p.y-q.y) < 0.0001 && cropped.assetID == photo.assetID, "Rotated crop preserves source position and asset")
        }
        let other = SceneElementModel(kind: .image, frame: CGRect(x: 350, y: 200, width: 70, height: 60), rotation: -20)
        let groupState = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [photo, other])); groupState.select([photo.id, other.id])
        let bounds = SceneGeometry.bounds(groupState.selected)!
        let groupTargets = SceneTransformController.targets(groupState.selected, scale: 1)
        let groupCorner = groupTargets.first { !$0.rotation && $0.handle.x == 1 && $0.handle.y == 1 }!
        let groupResized = SceneTransformController.applying(groupState.value, target: groupCorner, from: groupCorner.point, to: CGPoint(x: groupCorner.point.x+40, y: groupCorner.point.y+40), stretch: false, crop: false)
        check(groupResized.scene.elements[0].rotation == photo.rotation && groupResized.scene.elements[1].rotation == other.rotation, "Group resize preserves rotations")
        let turn = groupTargets.first { $0.rotation && $0.handle.x == 1 && $0.handle.y == 1 }!
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let turnDelta = CGPoint(x: turn.point.x-center.x, y: turn.point.y-center.y)
        let rotated = SceneTransformController.applying(groupState.value, target: turn, from: turn.point, to: CGPoint(x: center.x-turnDelta.y, y: center.y+turnDelta.x), stretch: false, crop: false)
        check(abs(rotated.scene.elements[0].rotation-photo.rotation-90) < 0.0001 && abs(hypot(rotated.scene.elements[0].frame.midX-center.x, rotated.scene.elements[0].frame.midY-center.y)-hypot(photo.frame.midX-center.x, photo.frame.midY-center.y)) < 0.0001, "Group rotation orbits center")
        let edge = targets.first { !$0.rotation && $0.handle.x == 1 && $0.handle.y == 0 }!
        let edgeDelta = SceneTransformController.rotate(CGPoint(x: 30, y: 0), photo.rotation * .pi/180)
        let edgeResized = SceneTransformController.applying(original, target: edge, from: edge.point, to: CGPoint(x: edge.point.x+edgeDelta.x, y: edge.point.y+edgeDelta.y), stretch: false, crop: false).scene.elements[0]
        let oldCorners = SceneGeometry.corners(photo), newCorners = SceneGeometry.corners(edgeResized)
        let oldAnchor = CGPoint(x: (oldCorners[0].x+oldCorners[3].x)/2, y: (oldCorners[0].y+oldCorners[3].y)/2)
        let newAnchor = CGPoint(x: (newCorners[0].x+newCorners[3].x)/2, y: (newCorners[0].y+newCorners[3].y)/2)
        check(hypot(oldAnchor.x-newAnchor.x, oldAnchor.y-newAnchor.y) < 0.0001 && abs(edgeResized.frame.width/photo.frame.width-edgeResized.frame.height/photo.frame.height) < 0.0001, "Proportional edge resize anchors opposite edge center")
        let expanded = SceneTransformController.applying(original, target: edge, from: edge.point, to: CGPoint(x: edge.point.x+edgeDelta.x*100, y: edge.point.y+edgeDelta.y*100), stretch: false, crop: true).scene.elements[0]
        check(abs(expanded.frame.width - 150) < 0.0001 && abs(expanded.imageRect!.maxX-expanded.frame.width) < 0.0001, "Crop expansion clamps at source edge")
        let tiny = SceneTransformController.applying(original, target: corner, from: grab, to: CGPoint(x: grab.x-10000, y: grab.y-10000), stretch: true, crop: false).scene.elements[0]
        check(tiny.frame.width > 0 && tiny.frame.height > 0, "Resize never flips")
        photo.kind = .text; photo.assetID = nil; photo.imageRect = nil
        let textState = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [photo])); textState.select([photo.id])
        let transformed = SceneTransformController.applying(textState.value, target: corner, from: grab, to: moved, stretch: true, crop: false).scene.elements[0]
        check(transformed.style == photo.style && transformed.textScaleX != nil && transformed.textScaleY != nil, "Text scale is separate from style")
        let encoded = try! JSONEncoder().encode(transformed)
        check(try! JSONDecoder().decode(SceneElementModel.self, from: encoded) == transformed, "Text scale round trip")
        var legacy = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "textScaleX"); legacy.removeValue(forKey: "textScaleY")
        let decoded = try! JSONDecoder().decode(SceneElementModel.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(decoded.textScaleX == nil && decoded.textScaleY == nil, "Old text has identity scale")
    }
    static func transformedTextInput(_ store: SceneStore) {
        var e = item(100); e.text = "Пример текста"; e.textScaleX = 1.5; e.textScaleY = 2
        let state = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [e])); state.select([e.id])
        let controller = SceneCanvasController(state: state, store: store)
        let canvas = controller.view
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 844, height: 544), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas; canvas.editSelection()
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
        guard let input = descendants(canvas).compactMap({ $0 as? NSTextView }).first else { fatalError("Missing native text input") }
        let actualOrigin = canvas.convert(CGPoint.zero, from: input)
        let actualEnd = canvas.convert(CGPoint(x: input.bounds.maxX, y: input.bounds.maxY), from: input)
        let expected = canvas.viewport.viewRect(e.frame)
        check(hypot(actualOrigin.x-expected.minX, actualOrigin.y-expected.minY) < 0.01 && hypot(actualEnd.x-expected.maxX, actualEnd.y-expected.maxY) < 0.01, "Native glyph coordinates map to rendered frame")
        input.layoutManager?.ensureLayout(for: input.textContainer!)
        let glyphs = input.layoutManager!.glyphRange(for: input.textContainer!)
        let glyphRect = input.layoutManager!.boundingRect(forGlyphRange: glyphs, in: input.textContainer!)
        let glyphStart = canvas.convert(glyphRect.origin, from: input)
        let glyphEnd = canvas.convert(CGPoint(x: glyphRect.maxX, y: glyphRect.maxY), from: input)
        let measured = SceneTextLayout.measure(e, width: e.frame.width / e.textScaleX!)
        check(abs(glyphStart.x-expected.minX) < 1 && abs((glyphEnd.x-glyphStart.x)-measured.width*e.textScaleX!) < 4, "Native glyph layout aligns with rendered text and scale")
        check(input.string == e.text && input.selectedRange().location == (e.text as NSString).length, "Scaled input keeps text and insertion point")
        input.setMarkedText("ж", selectedRange: NSRange(location: 1, length: 0), replacementRange: input.selectedRange())
        check(input.hasMarkedText() && state.scene.elements[0].text == e.text, "Scaled input preserves marked text until committed")
        input.unmarkText(); canvas.finishText()
        state.editSelected { $0.rotation = 37 }
        for _ in 0..<2 {
            canvas.editSelection()
            guard let rotatedInput = descendants(canvas).compactMap({ $0 as? NSTextView }).first else { fatalError("Missing rotated input") }
            for _ in 0..<3 {
                canvas.layout()
                let start = canvas.convert(CGPoint.zero, from: rotatedInput)
                let right = canvas.convert(CGPoint(x: rotatedInput.bounds.maxX, y: 0), from: rotatedInput)
                let end = canvas.convert(CGPoint(x: rotatedInput.bounds.maxX, y: rotatedInput.bounds.maxY), from: rotatedInput)
                let corners = SceneGeometry.corners(state.scene.elements[0]).map { canvas.viewport.viewPoint($0) }
                check(hypot(start.x-corners[0].x, start.y-corners[0].y) < 0.01 && hypot(right.x-corners[1].x, right.y-corners[1].y) < 0.01 && hypot(end.x-corners[2].x, end.y-corners[2].y) < 0.01, "Rotated native text stays aligned across refresh and re-entry")
            }
            canvas.finishText()
        }
        withExtendedLifetime(controller) {}
    }
    static func savedTextWrapping(_ store: SceneStore) {
        var e = SceneElementModel(kind: .text, frame: CGRect(x: 756, y: 491, width: 391.07016300621444, height: 70.42969760301493), text: " Transform test")
        e.textScaleX = 1.8534130948161822; e.textScaleY = 1.8534130948161822; e.autoTextWidth = true
        let state = SceneEditingStateModel(EditorSceneModel(canvasSize: CGSize(width: 1512, height: 982), elements: [e])); state.select([e.id])
        let controller = SceneCanvasController(state: state, store: store); let canvas = controller.view
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 844, height: 544), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas; canvas.editSelection()
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
        guard let input = descendants(canvas).compactMap({ $0 as? NSTextView }).first, let layout = input.layoutManager, let container = input.textContainer else { fatalError("Missing input") }
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(for: container)
        var lines = 0
        layout.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in lines += 1 }
        check(lines == 1 && glyphs.length == (e.text as NSString).length, "Saved auto-width text lays out all glyphs on one line")
        let insertion = input.firstRect(forCharacterRange: NSRange(location: (e.text as NSString).length, length: 0), actualRange: nil)
        let localInsertion = input.convert(window.convertFromScreen(insertion), from: nil)
        check(localInsertion.minX >= input.bounds.minX-0.01 && localInsertion.maxX <= input.bounds.maxX+0.01 &&
              localInsertion.minY >= input.bounds.minY-0.01 && localInsertion.maxY <= input.bounds.maxY+0.01, "End caret remains inside input frame")
        window.setContentSize(CGSize(width: 1100, height: 700)); canvas.layout()
        layout.ensureLayout(for: container)
        var resizedLines = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, _, _ in resizedLines += 1 }
        check(resizedLines == 1, "Viewport resize does not change text wrapping")
        canvas.finishText(); withExtendedLifetime(controller) {}
    }
    static func nativeTransformGestures(_ store: SceneStore) {
        var e = item(100); e.text = "Transform test"; e.frame.size.height = 38
        let state = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [e])); state.select([e.id])
        let controller = SceneCanvasController(state: state, store: store), canvas = controller.view
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 844, height: 544), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
        func mouse(_ type: NSEvent.EventType, point: CGPoint, count: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 1)!
        }
        let handle = canvas.viewport.viewPoint(CGPoint(x: e.frame.maxX, y: e.frame.maxY))
        canvas.mouseDown(with: mouse(.leftMouseDown, point: handle)); canvas.mouseUp(with: mouse(.leftMouseUp, point: handle))
        check(state.scene.elements[0] == e && !state.canUndo, "No-motion transform has no history")
        canvas.mouseDown(with: mouse(.leftMouseDown, point: handle))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, point: CGPoint(x: handle.x+30, y: handle.y+20)))
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        canvas.keyDown(with: escape); canvas.mouseUp(with: mouse(.leftMouseUp, point: handle))
        check(state.scene.elements[0] == e && !state.canUndo, "Escape restores a canvas transform without history")
        let edge = canvas.viewport.viewPoint(CGPoint(x: e.frame.minX+1, y: e.frame.midY))
        canvas.mouseDown(with: mouse(.leftMouseDown, point: edge, count: 2))
        guard let input = descendants(canvas).compactMap({ $0 as? NSTextView }).first else { fatalError("Double-click edge must edit text") }
        let right = canvas.convert(CGPoint(x: input.bounds.maxX-1, y: input.bounds.midY), from: input)
        let dragged = CGPoint(x: right.x+30, y: right.y)
        input.mouseDown(with: mouse(.leftMouseDown, point: right)); input.mouseDragged(with: mouse(.leftMouseDragged, point: dragged))
        check(state.scene.elements[0].frame.width > e.frame.width, "Text width gesture previews")
        _ = canvas.textView(input, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        input.mouseUp(with: mouse(.leftMouseUp, point: dragged))
        check(state.scene.elements[0] == e && !state.canUndo, "Escape cancels native width gesture without history")
        input.mouseDown(with: mouse(.leftMouseDown, point: right)); input.mouseDragged(with: mouse(.leftMouseDragged, point: dragged)); input.mouseUp(with: mouse(.leftMouseUp, point: dragged))
        check(state.canUndo && state.scene.elements[0].frame.width > e.frame.width, "Width drag commits")
        state.undo(); check(state.scene.elements[0] == e && !state.canUndo, "Width drag commits one Undo")
        canvas.finishText()
        var image = SceneElementModel(kind: .image, frame: CGRect(x: 300, y: 100, width: 100, height: 100))
        image.assetID = nil
        let imageState = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [image])); imageState.select([image.id])
        let imageController = SceneCanvasController(state: imageState, store: store), imageCanvas = imageController.view
        window.contentView = imageCanvas
        var replaced = false; imageController.onPickReplacement = { _ in replaced = true }
        let p = imageCanvas.viewport.viewPoint(CGPoint(x: image.frame.minX+1, y: image.frame.midY))
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: imageCanvas.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
        imageCanvas.mouseDown(with: click)
        check(replaced, "Double-click image edge requests replacement")
        withExtendedLifetime((controller, imageController)) {}
    }
    static func nativeWidthUndoOrdering(_ store: SceneStore) {
        var e = item(100); e.text = "base"; e.frame.size.height = 38
        let state = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [e])); state.select([e.id])
        let controller = SceneCanvasController(state: state, store: store), canvas = controller.view
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 844, height: 544), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas; canvas.editSelection()
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
        guard let input = descendants(canvas).compactMap({ $0 as? NSTextView }).first else { fatalError("Missing input") }
        func flush() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
        func type(_ s: String) { input.insertText(s, replacementRange: input.selectedRange()); flush(); input.breakUndoCoalescing() }
        func drag(_ amount: CGFloat) {
            let point = canvas.convert(CGPoint(x: input.bounds.maxX-1, y: input.bounds.midY), from: input)
            func event(_ t: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: t, location: canvas.convert(CGPoint(x: point.x+x, y: point.y), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            input.mouseDown(with: event(.leftMouseDown, 0)); input.mouseDragged(with: event(.leftMouseDragged, amount)); input.mouseUp(with: event(.leftMouseUp, amount)); flush()
        }
        func command(_ name: String) { _ = input.perform(NSSelectorFromString(name), with: nil); flush() }
        type("A"); check(state.scene.elements[0].text == "baseA", "Typed before resize")
        drag(30); let width1 = state.scene.elements[0].frame.width
        drag(20); let width2 = state.scene.elements[0].frame.width
        type("B"); check(state.scene.elements[0].text == "baseAB", "Typed after resize")
        command("undo:"); check(state.scene.elements[0].text == "baseA" && state.scene.elements[0].frame.width == width2, "Native undo removes later typing first")
        command("undo:"); check(state.scene.elements[0].frame.width == width1 && state.scene.elements[0].text == "baseA", "Native undo reverts second width")
        command("undo:"); check(state.scene.elements[0].frame.width == e.frame.width && state.scene.elements[0].text == "baseA", "Native undo reverts first width")
        command("undo:"); check(state.scene.elements[0].text == "base", "Native undo reverts earlier typing")
        command("redo:"); command("redo:"); command("redo:"); command("redo:")
        check(state.scene.elements[0].frame.width == width2 && state.scene.elements[0].text == "baseAB", "Native redo restores chronological sequence")
        canvas.finishText(); state.undo()
        check(state.scene.elements[0].frame.width == width2 && state.scene.elements[0].text == "baseA", "Scene undo after finish reverts last typing once")
        state.undo(); check(state.scene.elements[0].frame.width == width1, "Scene undo after finish reverts second width once")
        state.undo(); check(state.scene.elements[0].frame.width == e.frame.width, "Scene undo after finish reverts first width once")
        state.undo(); check(state.scene.elements[0].text == "base" && !state.canUndo, "Scene undo after finish reverts earlier typing once")
        canvas.editSelection()
        guard let secondInput = descendants(canvas).compactMap({ $0 as? NSTextView }).first else { fatalError("Missing reentered input") }
        let point = canvas.convert(CGPoint(x: secondInput.bounds.maxX-1, y: secondInput.bounds.midY), from: secondInput)
        func secondEvent(_ t: NSEvent.EventType, _ dx: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: canvas.convert(CGPoint(x: point.x+dx, y: point.y), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        secondInput.mouseDown(with: secondEvent(.leftMouseDown, 0)); secondInput.mouseDragged(with: secondEvent(.leftMouseDragged, 30)); secondInput.mouseUp(with: secondEvent(.leftMouseUp, 30)); flush()
        _ = secondInput.perform(NSSelectorFromString("undo:"), with: nil); flush()
        check(state.scene.elements[0].frame.width == e.frame.width && !state.canUndo, "Native width undo restores scene checkpoint")
        canvas.finishText()
        check(state.scene.elements[0] == e && !state.canUndo, "Finishing after native width undo creates no extra scene history")
        withExtendedLifetime(controller) {}
    }
    static func cancelCanvasDrag(_ store: SceneStore, duplicate: Bool) {
        _ = NSApplication.shared
        let first = item(50), second = item(300)
        let model = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [first, second]))
        model.select(duplicate ? [first.id, second.id] : [first.id])
        let beforeLastEdit = model.value
        model.editSelected { $0.name = "Сохранённый слой" }
        let beforeMouseDown = model.value
        var commits = 0
        model.onUpdate = { if case .committed = $0 { commits += 1 } }

        let canvasController = SceneCanvasController(state: model, store: store)
        defer { withExtendedLifetime(canvasController) {} }
        let canvas = canvasController.view
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: CGSize(width: 844, height: 544)),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        let flags: NSEvent.ModifierFlags = duplicate ? [.option] : []
        func mouse(_ type: NSEvent.EventType, dx: CGFloat) -> NSEvent {
            // Canvas has a 22 pt inset on each side, leaving the scene at 1:1.
            let point = CGPoint(x: second.frame.midX + 22 + dx, y: second.frame.midY + 22)
            return NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: flags,
                                      timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                      eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, dx: 0))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, dx: 28))
        if duplicate {
            check(model.scene.elements.count == 4 && model.selection.isDisjoint(with: beforeMouseDown.selection),
                  "Option-drag previews copies of the selected group")
        } else {
            check(model.selected.first?.id == second.id && model.selected.first?.frame.minX == second.frame.minX + 28,
                  "Move previews a different selection and frame")
        }
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        canvas.keyDown(with: escape)
        check(model.value == beforeMouseDown, "Escape restores all original elements, IDs, frames and selection")
        canvas.mouseDragged(with: mouse(.leftMouseDragged, dx: 40))
        canvas.mouseUp(with: mouse(.leftMouseUp, dx: 40))
        check(model.value == beforeMouseDown && commits == 0, "Events after cancellation cannot commit or trigger a save")
        model.undo()
        check(model.value == beforeLastEdit && !model.canUndo, "Undo still reaches the previous completed edit in one step")
    }

    static func shiftGestures(_ store: SceneStore) {
        let first = item(50), second = item(300)
        let model = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [first, second]))
        let canvasController = SceneCanvasController(state: model, store: store)
        defer { withExtendedLifetime(canvasController) {} }
        let canvas = canvasController.view
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 844, height: 544),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        func mouse(_ type: NSEvent.EventType, dx: CGFloat = 0, dy: CGFloat = 0) -> NSEvent {
            let point = CGPoint(x: second.frame.midX + 22 + dx, y: second.frame.midY + 22 + dy)
            return NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [.shift],
                                      timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                      eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        for ids: Set<UUID> in [[second.id], [first.id, second.id]] {
            model.select(ids)
            let original = model.value
            canvas.mouseDown(with: mouse(.leftMouseDown))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, dx: 12, dy: 7))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, dx: 24, dy: 40))
            canvas.mouseUp(with: mouse(.leftMouseUp, dx: 24, dy: 40))
            check(model.value == SceneEditingStateModel.moved(original, dx: 24, dy: 0),
                  "Shift held before dragging moves the whole selection on its initial axis")
            model.undo()
            check(model.value == original && !model.canUndo, "One Undo for a Shift-constrained drag")
        }
        canvas.mouseDown(with: mouse(.leftMouseDown))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, dx: 1))
        canvas.mouseUp(with: mouse(.leftMouseUp, dx: 1))
        check(model.selection == [first.id], "Shift-click removes a selected layer below drag threshold")
        canvas.mouseDown(with: mouse(.leftMouseDown))
        canvas.mouseUp(with: mouse(.leftMouseUp))
        check(model.selection == [first.id, second.id] && !model.canUndo, "Shift-click adds a layer without history")
    }

    static func markedTextFinishing(_ store: SceneStore) {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for ending in ["finish", "escape", "focus", "mouseDown"] {
            for accepted in ["", "Текст"] {
                let empty = EditorSceneModel(canvasSize: size)
                let model = SceneEditingStateModel(empty)
                var commits = 0
                model.onUpdate = { if case .committed = $0 { commits += 1 } }
                let canvasController = SceneCanvasController(state: model, store: store)
                defer { withExtendedLifetime(canvasController) {} }
                let canvas = canvasController.view
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: CGSize(width: 844, height: 544)),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = canvas
                canvas.createCenteredText()
                let field = descendants(canvas).compactMap { $0 as? NSTextView }.first!
                let selection = NSRange(location: NSNotFound, length: 0)
                if !accepted.isEmpty { field.insertText(accepted, replacementRange: selection) }
                field.setMarkedText("ка", selectedRange: NSRange(location: 2, length: 0), replacementRange: selection)
                check(field.hasMarkedText() && field.string == accepted + "ка" && model.scene.elements[0].text == accepted,
                      "Native composition stays separate from accepted model text")
                switch ending {
                case "finish": canvas.finishText()
                case "escape": field.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
                case "focus": check(window.makeFirstResponder(canvas), "Native focus transfer succeeds")
                default:
                    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 5, y: 5), modifierFlags: [],
                                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                  eventNumber: 1, clickCount: 1, pressure: 1)!
                    canvas.mouseDown(with: event)
                }
                check(descendants(canvas).allSatisfy { !($0 is NSTextView) }, "\(ending) finishes native text editing")
                if accepted.isEmpty {
                    check(model.scene == empty && commits == 0 && !model.canUndo,
                          "\(ending) discards marked-only insertion without committing a blank layer")
                } else {
                    check(model.scene.elements.count == 1 && model.scene.elements[0].text == accepted && commits == 1,
                          "\(ending) preserves accepted prefix without finalizing the marked suffix")
                    model.undo()
                    check(model.scene == empty && !model.canUndo, "\(ending) creates just one typing Undo")
                    model.redo()
                    check(model.scene.elements[0].text == accepted, "Redo retains accepted text only")
                }
            }
        }
        var saved = item(50); saved.text = "Сохранено"
        let existing = EditorSceneModel(canvasSize: size, elements: [saved])
        let model = SceneEditingStateModel(existing)
        model.select([saved.id])
        let canvasController = SceneCanvasController(state: model, store: store)
        defer { withExtendedLifetime(canvasController) {} }
        let canvas = canvasController.view
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: CGSize(width: 844, height: 544)),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas; canvas.editSelection()
        let field = descendants(canvas).compactMap { $0 as? NSTextView }.first!
        field.setMarkedText("ка", selectedRange: NSRange(location: 2, length: 0),
                            replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.finishText()
        check(model.scene == existing && !model.canUndo, "Finishing composition preserves existing accepted text without another Undo")
        print("Marked text finishing checks passed: direct finish, Escape, focus loss and mouse-down; marked-only discard and accepted prefix with one Undo.")
    }

    static func truncatedImports(_ directory: URL, _ store: SceneStore) throws {
        let width = 128, height = 64
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var seed: UInt32 = 10
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bitmap.bytesPerRow + x * 4
                for channel in 0..<3 {
                    seed = 1664525 &* seed &+ 1013904223
                    bitmap.bitmapData![offset + channel] = UInt8(seed >> 24)
                }
                bitmap.bitmapData![offset + 3] = 255
            }
        }
        let complete = bitmap.representation(using: .png, properties: [:])!
        let truncated = complete.prefix(256)
        check(complete.count > 256 && NSImage(data: truncated)?.size == CGSize(width: width, height: height),
              "Recognizable PNG prefix retains the original dimensions")
        let model = SceneEditingStateModel(EditorSceneModel(canvasSize: size))
        let imageController = SceneImageController(state: model, store: store)
        let empty = model.value
        let good = SceneImageInput(data: complete), bad = SceneImageInput(data: truncated)
        try imageController.importImages([good], at: .add(imageController.insertionPoint))
        let before = model.value, layer = model.selected[0]
        let url = store.imageURL(for: layer.assetID!)!
        let assets = directory.appendingPathComponent("Assets")
        let names = try FileManager.default.contentsOfDirectory(atPath: assets.path).sorted()
        let incompleteFile = directory.appendingPathComponent("incomplete.png")
        try truncated.write(to: incompleteFile)
        for importSource in [{ try store.importImage(data: truncated) }, { try store.importImage(at: incompleteFile) }] {
            do { _ = try importSource(); fatalError("Shared store boundary accepted a truncated PNG") }
            catch is SceneError { }
        }
        for (inputs, target) in [([bad], SceneImageDestination.replace(layer.id)), ([good, bad], .add(.zero))] {
            do {
                try imageController.importImages(inputs, at: target)
                fatalError("Truncated PNG accepted")
            } catch is SceneError { }
            check(model.value == before && !model.canRedo, "Failed imports keep the scene, selection and redo history")
            check(try FileManager.default.contentsOfDirectory(atPath: assets.path).sorted() == names,
                  "A mixed batch creates no partial assets")
            check(try Data(contentsOf: url) == complete, "Replacement preserves every byte of the source pixels")
            model.undo()
            check(model.value == empty && !model.canUndo, "Previous add remains the only Undo step")
            model.redo()
            check(model.value == before, "Redo still restores the original image and identity")
        }
        model.undo()
        do {
            try imageController.importImages([good, bad], at: .add(.zero))
            fatalError("Truncated PNG accepted with pending Redo")
        } catch is SceneError { }
        check(model.value == empty && model.canRedo && !model.canUndo, "A failed batch preserves pending Redo")
        model.redo()
        check(model.value == before, "Pending Redo still restores the original scene after failure")
        print("PNG integrity checks passed: opaque 128×64 PNG (\(complete.count) bytes), 256-byte prefix rejected for replacement and batch.")
    }

    static func imageBytes(_ type: NSBitmapImageRep.FileType, _ w: Int, _ h: Int) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: w,pixelsHigh: h,bitsPerSample: 8,samplesPerPixel: 4,
                                      hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        bitmap.bitmapData!.initialize(repeating: 255, count: bitmap.bytesPerRow*h)
        return bitmap.representation(using: type, properties: [:])!
    }
    static func imports(_ directory: URL, _ store: SceneStore) throws {
        let png = imageBytes(.png, 64, 16), tiff = imageBytes(.tiff, 10, 40)
        let file = directory.appendingPathComponent("пример.png")
        try png.write(to: file)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        func images() throws -> [SceneImageInput] {
            guard case .images(let inputs) = try SceneTransfer.read(board) else { fatalError("Missing private board image") }
            return inputs
        }
        board.clearContents(); check(board.writeObjects([file as NSURL]), "Private board accepts URL")
        let fileInputs = try images()
        check(fileInputs.count == 1 && fileInputs[0].data == png, "Original local file URL copied")
        let model = SceneEditingStateModel(EditorSceneModel(canvasSize: size))
        let imageController = SceneImageController(state: model, store: store)
        try imageController.importImages(fileInputs, at: .add(CGPoint(x: 200,y: 200)))
        var original = model.selected[0]
        model.editSelected { $0.rotation = 28; $0.cornerRadius = 5; $0.opacity = 0.4 }
        original = model.selected[0]
        let captured = imageController.pasteImageDestination
        check(captured == .replace(original.id), "Clipboard captures selected image")
        try FileManager.default.removeItem(at: file)
        board.clearContents(); check(board.setData(png, forType: .png), "Private board accepts PNG")
        try imageController.importImages(try images(), at: .add(CGPoint(x: 550,y: 400)))
        let second = model.selected[0]
        check(model.scene.elements.count == 2 && second.id != original.id, "Explicit add ignores selected photo")
        check(imageController.dropDestination(at: CGPoint(x: 200,y: 200)) == .replace(original.id), "Drop targets hit image independently of selection")
        let free = CGPoint(x: 10,y: 20)
        check(imageController.dropDestination(at: free) == .add(free), "Drop on empty canvas adds")
        board.clearContents(); check(board.setData(tiff, forType: .tiff), "Private board accepts TIFF")
        let tiffInputs = try images()
        try imageController.importImages(tiffInputs, at: captured)
        let replaced = model.scene.elements[0]
        var expected = original; expected.assetID = replaced.assetID; expected.imageRect = replaced.imageRect
        check(replaced == expected && replaced.assetID != original.assetID && model.scene.elements[1] == second,
              "Replace only captured source and placement")
        check(replaced.imageRect == CGRect(x: 0,y: -120,width: 64,height: 256), "Center-fill with original aspect ratio")
        model.undo()
        check(model.scene.elements == [original,second] && store.image(for: original.assetID!) != nil, "Old imported source survives replacement Undo")
        let before = model.value
        do { try imageController.importImages([fileInputs[0],SceneImageInput(data: Data([1,2]))], at: .add(free))
            fatalError("Broken batch accepted") } catch {}
        check(model.value == before, "Broken batch leaves scene and selection unchanged")
        try imageController.importImages([fileInputs[0],tiffInputs[0]], at: .add(free))
        check(model.selected.count == 2, "Batch selects new images")
        check(imageController.pasteImageDestination == .add(imageController.insertionPoint), "Multiple selection pastes as new layers")
        model.undo(); check(model.value == before, "One Undo for whole batch")
        check(try SceneTransfer.write([original,second], to: board), "Internal private-board layer copy")
        guard case .layers(let layers) = try SceneTransfer.read(board) else { fatalError("Missing internal copy") }
        check(layers == [original,second], "All copied properties survive native pasteboard")
        board.clearContents(); board.setString("Привет\nМир", forType: .string)
        guard case .text(let text) = try SceneTransfer.read(board) else { fatalError("Text mistaken for an image") }
        check(text == "Привет\nМир", "Plain external text")
    }
    static func widths(_ store: SceneStore) throws {
        var e = item(20); e.text = "Надпись"; e.autoTextWidth = true
        SceneTextLayout.fit(&e); let initialWidth = e.frame.width
        e.text += " на экране"; SceneTextLayout.fit(&e); check(e.frame.width > initialWidth, "Automatic width follows typing")
        try store.save(EditorSceneModel(canvasSize: size, elements: [e]))
        check(try store.load()?.elements.first?.autoTextWidth == true, "Automatic mode survives restart")
        e.autoTextWidth = nil; e.frame.size.width = 60; SceneTextLayout.fit(&e)
        check(e.frame.width == 60 && e.frame.height > e.style.fontSize, "Fixed-width text wraps without growing sideways")
        let bytes = try JSONEncoder().encode(e)
        check(!String(decoding: bytes,as: UTF8.self).contains("autoTextWidth"), "Older payload has no width mode")
        check(try JSONDecoder().decode(SceneElementModel.self, from: bytes).autoTextWidth == nil, "Older payload decodes as fixed")
    }
    static func inspectorValidation() {
        _ = NSApplication.shared
        var text = item(100); text.style.lineHeight = 48
        let model = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [text]))
        model.select([text.id]); let original = model.value
        model.editSelected { $0.name = "Сохранённое изменение" }
        let saved = model.value
        model.undo()
        let view = SceneInspectorView(frame: .zero)
        let controller = SceneInspectorController(state: model, view: view)
        var errors = [String](), updates = 0
        controller.onError = { errors.append($0) }
        model.onUpdate = { _ in updates += 1 }
        let invalid = [("w", "0"), ("h", "-1"), ("size", "nan"), ("opacity", "101"),
                       ("line", "-1"), ("x", "inf"), ("color", "#XYZXYZ")]
        for (key, raw) in invalid {
            controller.applyField(key: key, raw: raw, label: "Проверяемое поле")
            check(model.value == original && !model.canUndo && model.canRedo,
                  "Invalid \(key) leaves the scene, selection and pending Redo unchanged")
        }
        controller.applyField(key: "w", raw: " \n ", label: "Ширина")
        controller.applyMenu(key: "weight", index: 9)
        check(errors.count == invalid.count && errors.allSatisfy { $0.contains("Проверяемое поле") } && updates == 0,
              "Invalid fields report their label; empty fields and invalid menu indices do not edit or emit updates")
        model.redo()
        check(model.value == saved, "Validation preserves the full pending Redo snapshot")
        model.undo()
        controller.applyField(key: "x", raw: " 12,5 ", label: "X")
        check(model.selected[0].frame.minX == 12.5 && !model.canRedo,
              "Decimal-comma input is trimmed and replaces pending Redo with the new edit")
        model.undo()
        check(model.value == original && !model.canUndo, "A numeric inspector edit adds exactly one Undo step")
        model.redo()
        let beforeAuto = model.value
        controller.applyField(key: "line", raw: " аВтО ", label: "Строка")
        check(model.selected[0].style.lineHeight == 0 && controller.makePresentation().fields["line"]?.text == "Авто",
              "Case-insensitive Авто selects natural line height and is presented consistently")
        check(model.selected[0].frame.height >= beforeAuto.scene.elements[0].frame.height,
              "Changing line height preserves the minimum text frame height")
        model.undo()
        check(model.value == beforeAuto, "Automatic line-height fitting is undone together with the style edit")
        let beforeColor = model.selected[0].frame
        controller.applyField(key: "color", raw: "#123456", label: "Цвет")
        check(model.selected[0].style.color == SceneColor(red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 1) &&
              model.selected[0].frame == beforeColor && controller.makePresentation().fields["color"]?.text == "123456FF",
              "Six-digit HEX uses opaque alpha without resizing the text frame")
    }

    static func inspectorGeometry() {
        var text = item(100); text.rotation = 30; text.autoTextWidth = true
        let image = SceneElementModel(kind: .image, frame: CGRect(x: 300, y: 200, width: 200, height: 80),
                                      imageRect: CGRect(x: -20, y: -10, width: 240, height: 100))
        let other = item(600)
        let model = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [text, image, other]))
        model.select([text.id, image.id]); let original = model.value
        let view = SceneInspectorView(frame: .zero)
        let controller = SceneInspectorController(state: model, view: view)
        let dx = image.frame.minX - text.frame.minX, dy = image.frame.minY - text.frame.minY
        controller.applyField(key: "x", raw: "25,5", label: "X")
        check(abs(SceneGeometry.bounds(model.selected)!.minX - 25.5) < 0.0001 &&
              abs(model.selected[1].frame.minX - model.selected[0].frame.minX - dx) < 0.0001 &&
              model.selected[1].frame.minY - model.selected[0].frame.minY == dy && model.scene.elements[2] == other,
              "Group X moves rotated bounds while preserving spacing and unselected layers")
        model.undo()
        check(model.value == original && !model.canUndo, "Group translation is one Undo step")
        controller.applyField(key: "y", raw: "-30", label: "Y")
        check(abs(SceneGeometry.bounds(model.selected)!.minY + 30) < 0.0001 &&
              abs(model.selected[1].frame.minY - model.selected[0].frame.minY - dy) < 0.0001,
              "Group Y moves rotated bounds without changing vertical spacing")
        model.undo()
        controller.applyField(key: "w", raw: "250", label: "Ширина")
        check(model.selected.allSatisfy { $0.frame.width == 250 } && model.selected[0].autoTextWidth == false &&
              model.selected[0].frame.height == text.frame.height &&
              model.selected[1].imageRect == CGRect(x: -25, y: -10, width: 300, height: 100) && model.scene.elements[2] == other,
              "Batch width sets fixed text width and scales image placement along X only")
        model.undo()
        check(model.value == original && !model.canUndo, "One Undo restores both text width mode and image crop")
        controller.applyField(key: "h", raw: "160", label: "Высота")
        check(model.selected.allSatisfy { $0.frame.height == 160 } && model.selected[0].autoTextWidth == true &&
              model.selected[1].frame.width == image.frame.width &&
              model.selected[1].imageRect == CGRect(x: -20, y: -20, width: 240, height: 200),
              "Batch height scales image placement along Y without disabling automatic text width")
        model.undo()
        check(model.value == original, "Batch height changes undo atomically")
    }

    static func inspectorSelection() {
        var first = item(50), middle = item(250), last = item(450)
        first.name = "Одинаковое имя"; middle.name = "Средний"; last.name = first.name
        let model = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [first, middle, last]))
        model.select([first.id])
        let view = SceneInspectorView(frame: .zero)
        let controller = SceneInspectorController(state: model, view: view)
        var focus = 0
        controller.onFocus = { focus += 1 }
        let initial = controller.makePresentation()
        check(initial.layers == [last.name, middle.name, first.name] && initial.selectedRows == IndexSet(integer: 2),
              "Inspector lists layers from front to back and presents selection in reversed row order")
        view.onSelectionChange?(IndexSet([0, 1, 99]))
        check(model.selection == [last.id, middle.id] && !model.canUndo && focus == 1,
              "Row events map to distinct IDs, ignore stale out-of-range rows and return canvas focus")
        model.reorder(.back); controller.refresh()
        check(controller.makePresentation().selectedRows == IndexSet([1, 2]), "Layer reordering updates presented selection rows")
        view.onSelectionChange?(IndexSet(integer: 0))
        check(model.selection == [first.id] && focus == 2,
              "Refreshed row mapping selects the new top layer even when names are duplicated")
        view.onFocus?()
        check(focus == 3, "Clicking an already-selected layer can still return canvas focus")
        view.onMenuChange?("align", 2)
        check(model.selected[0].style.horizontalAlignment == 2 && focus == 4,
              "A menu event applies the zero-based value and returns canvas focus")
        view.onCenter?(true)
        check(abs(SceneGeometry.bounds(model.selected)!.midX - size.width / 2) < 0.0001 && focus == 5,
              "A center event changes geometry and returns canvas focus")
    }

    static func inspectorNativeEditing() {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        var first = item(50), second = item(250)
        first.opacity = 0.25; second.opacity = 0.75
        let model = SceneEditingStateModel(EditorSceneModel(canvasSize: size, elements: [first, second]))
        model.select([first.id, second.id]); let original = model.value
        let view = SceneInspectorView(frame: .zero)
        let controller = SceneInspectorController(state: model, view: view)
        let presentation = controller.makePresentation()
        check(presentation.fields["opacity"]?.text == "" && presentation.fields["opacity"]?.placeholder == "Разные" &&
              presentation.fields["w"]?.text == "100" && presentation.fields["w"]?.placeholder == nil,
              "Mixed and uniform selection values have distinct presentation states")
        let field = descendants(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "opacity" }!
        var focus = 0
        controller.onFocus = { focus += 1 }
        view.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field,
            userInfo: ["NSTextMovement": NSNumber(value: NSTextMovement.return.rawValue)]))
        check(model.value == original && !model.canUndo && focus == 1,
              "Return in an untouched mixed field requests focus without broadcasting an empty value")
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        check(window.makeFirstResponder(field), "Inspector field accepts native editing focus")
        guard let editor = field.currentEditor() as? NSTextView else { fatalError("Missing native inspector field editor") }
        editor.string = "63,5"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        controller.refresh()
        check(editor.string == "63,5" && model.value == original,
              "A refresh preserves uncommitted text in the active native field editor")
        check(window.makeFirstResponder(nil), "Native inspector editing can finish")
        check(model.selected.allSatisfy { $0.opacity == 0.635 } && model.canUndo,
              "Finishing an edited mixed field applies its value to the whole selection")
        model.undo()
        check(model.value == original && !model.canUndo, "The edited mixed field creates one batch Undo step")
        withExtendedLifetime(controller) {}
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        geometryAndHistory()
        transforms()
        transformedTextInput(store)
        savedTextWrapping(store)
        nativeTransformGestures(store)
        nativeWidthUndoOrdering(store)
        cancelCanvasDrag(store, duplicate: false)
        cancelCanvasDrag(store, duplicate: true)
        shiftGestures(store)
        markedTextFinishing(store)
        try truncatedImports(directory, store)
        try imports(directory,store); try widths(store)
        inspectorValidation()
        inspectorGeometry()
        inspectorSelection()
        inspectorNativeEditing()
        print("SceneEditingTests passed: rotated selection, history, layer order, group movement, Shift-click and Shift-held drag, Escape during move/copy, image routing, private pasteboard, text widths and inspector input")
    }
}
