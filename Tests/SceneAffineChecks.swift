import AppKit

/// Exact point comparisons catch the rectangle approximation that loses shear.
enum SceneAffineChecks {
    static func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
    static func near(_ a: CGPoint, _ b: CGPoint, _ message: String) {
        check(hypot(a.x-b.x, a.y-b.y) < 1e-7, message)
    }
    static func stretch(_ start: SceneSnapshot, sx: CGFloat, sy: CGFloat, handle: SceneTransformController.Handle = .init(x: 1, y: 1)) -> SceneSnapshot {
        let bounds = SceneGeometry.bounds(start.scene.elements.filter { start.selection.contains($0.id) })!
        let target = SceneTransformController.targets(start.scene.elements.filter { start.selection.contains($0.id) }, scale: 1)
            .first { !$0.rotation && $0.handle == handle }!
        return SceneTransformController.applying(start, target: target, from: target.point,
            to: CGPoint(x: target.point.x+CGFloat(handle.x)*bounds.width*(sx-1),
                        y: target.point.y+CGFloat(handle.y)*bounds.height*(sy-1)), stretch: true, crop: false)
    }
    static func geometry() throws -> EditorSceneModel {
        var leaves = [SceneElementKind.image, .text, .note, .countdown, .clock].enumerated().map { index, kind in
            SceneElementModel(kind: kind, frame: CGRect(x: 130+index*95, y: 140+index*15, width: 80, height: 60),
                              rotation: Double(index*31-43), cornerRadius: 9, text: "Affine")
        }
        leaves[0].imageRect = CGRect(x: -10, y: -20, width: 120, height: 100)
        leaves[1].textScaleX = 1.4; leaves[1].textScaleY = 0.8
        let scene = EditorSceneModel(canvasSize: CGSize(width: 1000, height: 700), elements: leaves)
        let state = SceneEditingStateModel(scene); state.select(Set(leaves.map(\.id)))
        state.groupSelection(); state.select(Set(leaves.prefix(2).map(\.id)), expandingGroups: false); state.groupSelection()
        state.select(Set(leaves.map(\.id)))
        let start = state.value
        for handle in SceneTransformController.handles {
            let sx: CGFloat = handle.x == 0 ? 1 : 1.7, sy: CGFloat = handle.y == 0 ? 1 : 0.6
            let bounds = SceneGeometry.bounds(start.scene.elements)!
            let anchor = CGPoint(x: handle.x == 0 ? bounds.midX : (handle.x > 0 ? bounds.minX : bounds.maxX),
                                 y: handle.y == 0 ? bounds.midY : (handle.y > 0 ? bounds.minY : bounds.maxY))
            let result = stretch(start, sx: sx, sy: sy, handle: handle)
            for (original, changed) in zip(start.scene.elements, result.scene.elements) {
                for (p, q) in zip(SceneGeometry.corners(original), SceneGeometry.corners(changed)) {
                    near(q, CGPoint(x: anchor.x+(p.x-anchor.x)*sx, y: anchor.y+(p.y-anchor.y)*sy), "Every transformed corner follows exact group scale")
                }
                check(original.frame.size == changed.frame.size && original.style == changed.style &&
                      original.imageRect == changed.imageRect && original.groups == changed.groups &&
                      original.cornerRadius == changed.cornerRadius, "Group stretch preserves local content, crop and hierarchy")
            }
            _ = try result.scene.validated()
        }
        let once = stretch(start, sx: 1.7, sy: 0.6)
        let twice = stretch(once, sx: 0.7, sy: 1.8)
        let oldBounds = SceneGeometry.bounds(once.scene.elements)!
        for (original, changed) in zip(once.scene.elements, twice.scene.elements) {
            for (p,q) in zip(SceneGeometry.corners(original), SceneGeometry.corners(changed)) {
                near(q, CGPoint(x: oldBounds.minX+(p.x-oldBounds.minX)*0.7, y: oldBounds.minY+(p.y-oldBounds.minY)*1.8), "Repeated stretch composes residuals")
            }
            let center = changed.localPoint(CGPoint(x: changed.frame.width/2, y: changed.frame.height/2))
            check(SceneGeometry.intersects(changed, CGRect(origin: center, size: .zero)), "Sheared interior is hittable")
            let bounds = SceneGeometry.bounds([changed])!
            let emptyCorner = CGPoint(x: bounds.minX+1e-5, y: bounds.minY+1e-5)
            check(!SceneGeometry.intersects(changed, CGRect(origin: emptyCorner, size: .zero)), "SAT rejects empty bounding-box corner")
        }
        state.preview(once); state.preview(twice); state.finish(from: start)
        state.undo(); check(state.value == start, "Whole stretch gesture is one Undo")
        state.redo(); check(state.value == twice, "Redo restores exact affine map")
        state.preview(once); state.preview(twice); check(state.value == twice, "Cancellation can restore starting snapshot")
        check(stretch(start, sx: 1, sy: 1) == start, "Zero-motion stretch has no history")
        let data = try JSONEncoder().encode(twice.scene)
        check(try JSONDecoder().decode(EditorSceneModel.self, from: data) == twice.scene, "Affine map survives JSON")
        let legacy = try JSONDecoder().decode(EditorSceneModel.self, from: JSONEncoder().encode(scene))
        check(legacy.elements.allSatisfy { $0.linearTransform == nil }, "Legacy scene uses identity")
        for invalid in [SceneLinearTransformModel(a: 0, d: 0), .init(a: -1), .init(a: .infinity)] {
            var bad = scene; bad.elements[0].linearTransform = invalid
            do { _ = try bad.validated(); fatalError("Invalid linear map accepted") } catch is SceneError { }
        }
        // A sheared leaf can still be resized and cropped about its actual opposite corner.
        let leaf = twice.scene.elements[0], single = SceneSnapshot(scene: .init(canvasSize: scene.canvasSize, elements: [leaf]), selection: [leaf.id])
        let target = SceneTransformController.targets([leaf], scale: 1).first { !$0.rotation && $0.handle == .init(x: 1, y: 1) }!
        let motion = leaf.localVector(CGPoint(x: 25, y: 15))
        let resized = SceneTransformController.applying(single, target: target, from: target.point,
            to: CGPoint(x: target.point.x+motion.x, y: target.point.y+motion.y), stretch: true, crop: false).scene.elements[0]
        near(resized.localPoint(.zero), leaf.localPoint(.zero), "Sheared leaf resize retains opposite corner")
        check(abs(resized.frame.width-leaf.frame.width-25) < 1e-7 && abs(resized.frame.height-leaf.frame.height-15) < 1e-7, "Resize inverts residual")
        let cropped = SceneTransformController.applying(single, target: target, from: target.point,
            to: CGPoint(x: target.point.x-motion.x, y: target.point.y-motion.y), stretch: false, crop: true).scene.elements[0]
        near(cropped.localPoint(cropped.imageRect!.origin), leaf.localPoint(leaf.imageRect!.origin), "Affine crop preserves source position")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        check(try SceneTransfer.write(twice.scene.elements, to: board), "Write affine private pasteboard")
        if case let .layers(transfer) = try SceneTransfer.read(board) {
            check(transfer == twice.scene.elements, "Transfer preserves affine fields")
        } else { fatalError("Affine transfer lost layers") }
        return twice.scene
    }
    static func native(_ scene: EditorSceneModel, store: SceneStore) {
        for kind in [SceneElementKind.text, .note] {
            let e = scene.elements.first { $0.kind == kind }!
            let state = SceneEditingStateModel(.init(canvasSize: scene.canvasSize, elements: [e])); state.select([e.id])
            let controller = SceneCanvasController(state: state, store: store), canvas = controller.view
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1044, height: 744), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = canvas
            func descendants(_ v: NSView) -> [NSView] { [v]+v.subviews.flatMap(descendants) }
            canvas.setFrameSize(.zero)
            canvas.editSelection()
            check(descendants(canvas).contains { $0 is NSTextView }, "Hidden zero-size canvas can prepare native affine input")
            canvas.finishText()
            for size in [CGSize(width: 1044, height: 744), CGSize(width: 644, height: 444)] {
                window.setContentSize(size); canvas.setFrameSize(size); canvas.editSelection()
                guard let input = descendants(canvas).compactMap({ $0 as? NSTextView }).first else { fatalError("Missing affine native input") }
                let current = state.scene.elements[0], sx = current.textScaleX ?? 1, sy = current.textScaleY ?? 1
                for p in [CGPoint.zero, CGPoint(x: input.bounds.maxX, y: 0), CGPoint(x: 0, y: input.bounds.maxY), CGPoint(x: input.bounds.maxX, y: input.bounds.maxY)] {
                    let expected = canvas.viewport.viewPoint(current.localPoint(CGPoint(x: p.x*sx, y: p.y*sy)))
                    near(canvas.convert(p, from: input), expected, "Native view corners agree with renderer after shear")
                    near(input.convert(expected, from: canvas), p, "Native mouse coordinates invert affine map")
                }
                for p in [CGPoint(x: 4, y: 4), CGPoint(x: input.bounds.maxX-4, y: input.bounds.maxY-4)] {
                    let pointInParent = canvas.superview!.convert(p, from: input)
                    let hit = canvas.hitTest(pointInParent)
                    check(hit === input, "Actual event routing reaches transformed native input")
                }
                input.insertText("!", replacementRange: input.selectedRange())
                canvas.finishText()
                check(state.scene.elements[0].linearTransform == e.linearTransform, "Native editing preserves group shear")
            }
            withExtendedLifetime(controller) { }
        }
    }
    static func nativeGestures(_ scene: EditorSceneModel, store: SceneStore) {
        let state = SceneEditingStateModel(scene); state.select(Set(scene.elements.map(\.id)))
        let controller = SceneCanvasController(state: state, store: store), canvas = controller.view
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1044, height: 744), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        let start = state.value
        let target = SceneTransformController.targets(state.selected, scale: canvas.viewport.scale).first { !$0.rotation && $0.handle == .init(x:1,y:1) }!
        func event(_ type: NSEvent.EventType, _ point: CGPoint, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.viewport.viewPoint(point), to: nil), modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let end = CGPoint(x: target.point.x+60, y: target.point.y-20)
        canvas.mouseDown(with: event(.leftMouseDown,target.point)); canvas.mouseDragged(with:event(.leftMouseDragged,end))
        check(state.scene != start.scene && !state.canUndo, "Native free group stretch previews without history")
        canvas.cancelOperation(nil); canvas.mouseUp(with:event(.leftMouseUp,end))
        check(state.value == start && !state.canUndo, "Escape restores complete group transform")
        canvas.mouseDown(with:event(.leftMouseDown,target.point)); canvas.mouseDragged(with:event(.leftMouseDragged,end)); canvas.mouseUp(with:event(.leftMouseUp,end))
        let committed = state.value
        check(state.canUndo && committed.scene != start.scene, "Native group stretch commits")
        state.undo(); check(state.value == start && !state.canUndo, "Native group gesture is one Undo")
        state.redo(); check(state.value == committed, "Native group gesture Redo")
        state.undo()
        canvas.mouseDown(with:event(.leftMouseDown,target.point,.shift)); canvas.mouseDragged(with:event(.leftMouseDragged,end,.shift)); canvas.mouseUp(with:event(.leftMouseUp,end,.shift))
        let constrained = SceneGeometry.bounds(state.scene.elements)!, initialBounds = SceneGeometry.bounds(start.scene.elements)!
        check(abs(constrained.width/initialBounds.width-constrained.height/initialBounds.height) < 1e-7, "Shift constrains group proportions")
        state.undo(); check(state.value == start, "Shift group resize is one Undo")
        canvas.mouseDown(with:event(.leftMouseDown,target.point,[.shift,.option])); canvas.mouseDragged(with:event(.leftMouseDragged,end,[.shift,.option])); canvas.mouseUp(with:event(.leftMouseUp,end,[.shift,.option]))
        let before = SceneGeometry.bounds(start.scene.elements)!, after = SceneGeometry.bounds(state.scene.elements)!
        check(abs(after.width/before.width-after.height/before.height) < 1e-7, "Option overrides Shift with uniform group scaling")
        near(CGPoint(x:after.midX,y:after.midY), CGPoint(x:before.midX,y:before.midY), "Option group scaling keeps center")
        withExtendedLifetime(controller) { }
    }
    static func boxResizing(_ store: SceneStore) {
        for kind in [SceneElementKind.text, .note, .countdown, .clock, .image] {
            var e = SceneElementModel(kind:kind, frame:CGRect(x:180,y:160,width:240,height:160), rotation:23,
                cornerRadius:20, text:"A long line of text that must wrap when its box narrows")
            e.style.fontSize = 24
            if kind == .text { e.autoTextWidth = true }
            if kind.hasTypography && kind != .note { e.textScaleX = 1.2; e.textScaleY = 0.9 }
            let state = SceneEditingStateModel(.init(canvasSize:CGSize(width:800,height:600), elements:[e])); state.select([e.id])
            let controller = SceneCanvasController(state:state, store:store), canvas = controller.view
            let window = NSWindow(contentRect:CGRect(x:0,y:0,width:844,height:644),styleMask:.borderless,backing:.buffered,defer:false)
            window.contentView = canvas
            let start = state.value
            for h in SceneTransformController.handles {
                for flags: NSEvent.ModifierFlags in [[], .shift] {
                    let target = SceneTransformController.targets([e],scale:canvas.viewport.scale).first { !$0.rotation && $0.handle == h }!
                    let motion = e.localVector(CGPoint(x:CGFloat(h.x) * -80,y:CGFloat(h.y) * 35))
                    let end = CGPoint(x:target.point.x+motion.x,y:target.point.y+motion.y)
                    func event(_ type:NSEvent.EventType,_ p:CGPoint) -> NSEvent {
                        NSEvent.mouseEvent(with:type,location:canvas.convert(canvas.viewport.viewPoint(p),to:nil),modifierFlags:flags,timestamp:0,
                            windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
                    }
                    canvas.mouseDown(with:event(.leftMouseDown,target.point));canvas.mouseDragged(with:event(.leftMouseDragged,end));canvas.mouseUp(with:event(.leftMouseUp,end))
                    let changed = state.scene.elements[0]
                    check(changed.style == e.style, "Resize preserves original typography style")
                    if flags.contains(.shift) {
                        check(abs(changed.frame.width/e.frame.width-changed.frame.height/e.frame.height) < 1e-7, "Shift preserves every element's box proportions")
                    } else if h.x == 0 {
                        check(abs(changed.frame.width-e.frame.width) < 1e-7 && abs(changed.frame.height-e.frame.height-35) < 1e-7, "Free vertical edge changes only box height")
                    } else if h.y == 0 {
                        check(abs(changed.frame.height-e.frame.height) < 1e-7 && abs(changed.frame.width-e.frame.width+80) < 1e-7, "Free horizontal edge changes only box width")
                    } else {
                        check(abs(changed.frame.width-e.frame.width+80) < 1e-7 && abs(changed.frame.height-e.frame.height-35) < 1e-7, "Free corner changes axes independently")
                    }
                    if kind.hasTypography {
                        check(changed.textScaleX == e.textScaleX && changed.textScaleY == e.textScaleY, "Box resize preserves displayed font scale")
                        check(changed.resolvedNote.padding == e.resolvedNote.padding && changed.cornerRadius == e.cornerRadius, "Box resize preserves padding and radius")
                        if kind == .text && h.x != 0 { check(changed.autoTextWidth == false, "Dragged text width remains fixed after reentering native input") }
                        if kind.hasEditableText && h.x != 0 && flags.isEmpty {
                            check(SceneTextLayout.measure(changed,width:changed.frame.width/(changed.textScaleX ?? 1)).height >
                                  SceneTextLayout.measure(e,width:e.frame.width/(e.textScaleX ?? 1)).height, "Narrower box reflows text into more lines")
                        }
                    }
                    state.undo(); check(state.value == start && !state.canUndo, "Each box or scale gesture has one Undo")
                }
            }
            withExtendedLifetime(controller) { }
        }
    }
    static func raster() {
        var e = SceneElementModel(kind: .note, frame: CGRect(x: 170, y: 150, width: 120, height: 90), rotation: 27, cornerRadius: 14)
        e.linearTransform = .init(a: 1.5, b: 0.2, c: 0.8, d: 0.9)
        let size = CGSize(width: 500, height: 400)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 500, pixelsHigh: 400, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        context.cgContext.translateBy(x: 0, y: size.height); context.cgContext.scaleBy(x: 1, y: -1)
        context.cgContext.clear(CGRect(origin: .zero, size: size))
        let render = SceneRenderElement(id: e.id, frame: e.frame, rotation: e.rotation, cornerRadius: e.cornerRadius, opacity: 1,
            drawing: .note(NSAttributedString(string: ""), frame: .zero, background: .white),
            linearTransform: ScenePresentationController.transform(e))
        SceneRenderer().draw(.init(canvasSize: size, elements: [render]), in: .init(size: size, in: CGRect(origin: .zero, size: size)))
        NSGraphicsContext.restoreGraphicsState()
        let path = SceneCornerPath.path(in: CGRect(origin: .zero, size: e.frame.size), radius: e.cornerRadius)
        var samples = 0
        for y in stride(from: 50, to: 350, by: 7) {
            for x in stride(from: 50, to: 450, by: 7) {
                let local = e.inverseVector(CGPoint(x: CGFloat(x)+0.5-e.frame.midX, y: CGFloat(y)+0.5-e.frame.midY))
                let p = CGPoint(x: local.x+e.frame.width/2, y: local.y+e.frame.height/2)
                // Skip anti-aliased boundaries, retain only stable interior/exterior samples.
                let classifications = [-2.0, 0, 2.0].flatMap { dx in [-2.0, 0, 2.0].map { dy in path.contains(CGPoint(x:p.x+dx,y:p.y+dy)) } }
                guard Set(classifications).count == 1 else { continue }
                let alpha = rep.colorAt(x: x,y: y)!.alphaComponent
                check(classifications[0] ? alpha > 0.95 : alpha < 0.05, "Raster agrees with exact sheared clipping geometry")
                samples += 1
            }
        }
        check(samples > 1000, "Raster checks cover shape and exterior")
    }
    static func run() throws {
        let scene = try geometry()
        raster()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("affine-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        try store.save(scene)
        check(try store.load() == scene, "Storage preserves exact affine scene")
        boxResizing(store)
        native(scene, store: store)
        nativeGestures(scene, store: store)
        print("Affine group checks passed: exact corners, repeated stretch, persistence, clipping, native text/mouse and gesture history.")
    }
}
