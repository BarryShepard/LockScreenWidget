import AppKit

enum SceneCornerChecks {
    private static func check(_ value: Bool, _ message: String) { precondition(value, message) }
    private static func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a-b) < 0.0001 }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("corners-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        paths()
        try inspector(store)
        limits()
        gestures(store)
        nativeInspector(store)
        nativeWidth(store)
        nativeMask(store)
        print("Continuous corner checks passed: native path, all-kind inspector, limits, rotated marker, gesture history and input mask.")
    }

    private static func paths() {
        let rect = CGRect(x: 0, y: 0, width: 160, height: 100)
        let square = SceneCornerPath.path(in: rect, radius: 0)
        let rounded = SceneCornerPath.path(in: rect, radius: 30)
        check(square.contains(CGPoint(x: 0.1,y: 0.1)), "Zero radius has square corners")
        check(!rounded.contains(CGPoint(x: 0.1,y: 0.1)) && rounded.contains(CGPoint(x: 80,y: 50)), "Continuous shape clips corners, preserves interior")
        check(rounded.boundingBoxOfPath == rect, "Continuous shape preserves frame bounds")
        check(SceneCornerPath.path(in: rect, radius: 1_000) == SceneCornerPath.path(in: rect, radius: 50), "Path clamps at half smaller side")
        for y in stride(from: CGFloat(1), to: 100, by: 7) {
            for x in stride(from: CGFloat(1), to: 160, by: 7) {
                let inside = rounded.contains(CGPoint(x:x,y:y))
                check(inside == rounded.contains(CGPoint(x:160-x,y:y)) && inside == rounded.contains(CGPoint(x:x,y:100-y)), "Continuous shape is symmetric")
            }
        }
        func rendered(_ radius: Double) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 100, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current!.cgContext.clear(rect)
            let element = SceneRenderElement(id: UUID(), frame: rect, rotation: 0, cornerRadius: radius, opacity: 1,
                drawing: .note(NSAttributedString(string: ""), frame: rect, background: .white))
            SceneRenderer().draw(.init(canvasSize: rect.size, elements: [element]), in: SceneViewport(size: rect.size, in: rect))
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        let roundedPixels = rendered(30), squarePixels = rendered(0)
        check(roundedPixels.colorAt(x:0,y:0)!.alphaComponent < 0.05 && roundedPixels.colorAt(x:80,y:50)!.alphaComponent > 0.95, "Actual renderer clips note background")
        check(squarePixels.colorAt(x:0,y:0)!.alphaComponent > 0.95, "Actual renderer restores square corners")
    }

    private static func inspector(_ store: SceneStore) throws {
        let elements = [SceneElementKind.text,.image,.note,.countdown,.clock].enumerated().map { index, kind in
            SceneElementModel(kind: kind, frame: CGRect(x: index*150,y: 100,width: 120,height: 60+index*10), cornerRadius: Double(index*4))
        }
        let original = EditorSceneModel(canvasSize: CGSize(width: 900,height: 500), elements: elements)
        let state = SceneEditingStateModel(original)
        let view = SceneInspectorView(frame: .zero), controller = SceneInspectorController(state: state, view: view)
        state.select(Set(elements.map(\.id)))
        check(controller.makePresentation().fields["radius"]?.placeholder == "Разные", "Mixed all-kind radii have a placeholder")
        controller.applyField(key: "radius", raw: "1000", label: "Радиус")
        check(state.selected.allSatisfy { $0.cornerRadius == $0.maximumCornerRadius }, "Common field clamps each kind independently")
        let changed = state.scene
        state.undo(); check(state.scene == original && !state.canUndo, "One common radius change is one Undo")
        state.redo(); check(state.scene == changed, "Radius redo")
        for raw in ["-1","nan","inf","bad"] {
            controller.applyField(key: "radius", raw: raw, label: "Радиус")
            check(state.scene == changed, "Invalid radius leaves scene unchanged")
        }
        controller.applyField(key: "radius", raw: "0", label: "Радиус")
        check(state.selected.allSatisfy { $0.cornerRadius == 0 }, "Square corners for every kind")
        try store.save(changed)
        check(try store.load() == changed, "All radii survive persistence")
        var old = elements[0]; old.cornerRadius = 1_000
        let legacy = EditorSceneModel(canvasSize: original.canvasSize,elements: [old])
        check(try legacy.validated().elements[0].cornerRadius == 1_000 && old.effectiveCornerRadius == 30, "Old oversized stored radius is read without rewriting")
    }

    private static func limits() {
        let note = SceneElementModel(kind: .note, frame: CGRect(x:100,y:100,width:200,height:100),cornerRadius:40)
        let bottom = SceneTransformController.Target(handle: .init(x:0,y:1),point:CGPoint(x:200,y:200),rotation:false)
        let state = SceneSnapshot(scene: .init(canvasSize:CGSize(width:800,height:500),elements:[note]),selection:[note.id])
        let reduced = SceneTransformController.applying(state,target:bottom,from:.zero,to:CGPoint(x:0,y:-80),stretch:true,crop:false)
        check(reduced.scene.elements[0].cornerRadius == 10 && reduced.scene.elements[0].style == note.style, "Note area resize clamps radius and retains typography")
        var image = note; image.kind = .image; image.imageRect = CGRect(origin:.zero,size:image.frame.size)
        let photoState = SceneSnapshot(scene:.init(canvasSize:state.scene.canvasSize,elements:[image]),selection:[image.id])
        let cropped = SceneTransformController.applying(photoState,target:bottom,from:.zero,to:CGPoint(x:0,y:-80),stretch:false,crop:true)
        check(cropped.scene.elements[0].cornerRadius == 10 && cropped.scene.elements[0].imageRect == image.imageRect, "Crop clamps radius without changing original placement")
        let unchanged = SceneTransformController.applying(photoState,target:bottom,from:.zero,to:.zero,stretch:false,crop:false)
        check(unchanged == photoState, "No-motion transform stays unchanged")
    }

    private static func gestures(_ store: SceneStore) {
        let element = SceneElementModel(kind:.note,frame:CGRect(x:200,y:150,width:240,height:140),rotation:31,cornerRadius:10,text:"Corners")
        let state = SceneEditingStateModel(.init(canvasSize:CGSize(width:800,height:500),elements:[element]))
        state.select([element.id])
        let controller = SceneCanvasController(state:state,store:store), canvas = controller.view
        let window = NSWindow(contentRect:CGRect(x:0,y:0,width:844,height:544),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        var commits = 0
        state.onUpdate = { if case .committed = $0 { commits += 1 }; controller.refresh() }
        controller.refresh()
        let original = state.value
        let target = SceneCornerController.target(state.selected,scale:canvas.viewport.scale)!
        check(SceneCornerController.hit(target.point,elements:state.selected,scale:canvas.viewport.scale) != nil, "Rotated radius marker is hittable")
        check(SceneTransformController.hit(target.point,elements:state.selected,scale:canvas.viewport.scale) == nil, "Marker has no resize or rotation overlap")
        var tiny = element; tiny.frame.size = CGSize(width:30,height:30)
        check(SceneCornerController.target([tiny],scale:1) == nil, "Small frames avoid conflicting marker")
        let amount = (40-target.initialRadius)/target.radiusPerPoint
        let delta = SceneTransformController.rotate(CGPoint(x:amount,y:amount),element.rotation * .pi/180)
        let end = CGPoint(x:target.point.x+delta.x,y:target.point.y+delta.y)
        func mouse(_ type:NSEvent.EventType,_ point:CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:canvas.convert(canvas.viewport.viewPoint(point),to:nil),modifierFlags:[],timestamp:0,
                windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        }
        canvas.mouseDown(with:mouse(.leftMouseDown,target.point)); canvas.mouseUp(with:mouse(.leftMouseUp,target.point))
        check(state.value == original && !state.canUndo, "Click without drag has no radius history")
        canvas.mouseDown(with:mouse(.leftMouseDown,target.point)); canvas.mouseDragged(with:mouse(.leftMouseDragged,end))
        check(close(state.selected[0].cornerRadius,40) && !state.canUndo && commits == 0, "Drag preview changes radius without commit")
        let escape = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,
            context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        canvas.keyDown(with:escape); canvas.mouseUp(with:mouse(.leftMouseUp,end))
        check(state.value == original && !state.canUndo, "Escape restores radius gesture")
        canvas.mouseDown(with:mouse(.leftMouseDown,target.point)); canvas.mouseDragged(with:mouse(.leftMouseDragged,end)); canvas.mouseUp(with:mouse(.leftMouseUp,end))
        let resized = state.value
        check(close(state.selected[0].cornerRadius,40) && state.selected[0].frame == element.frame && commits == 1, "Gesture commits one radius change without moving element")
        state.undo(); check(state.value == original && !state.canUndo,"One radius Undo")
        state.redo(); check(state.value == resized,"Radius Redo")
        var small = element; small.id = UUID(); small.frame = CGRect(x:50,y:50,width:100,height:40)
        let mixed = SceneSnapshot(scene:.init(canvasSize:state.scene.canvasSize,elements:[small,element]),selection:[small.id,element.id])
        let mixedTarget = SceneCornerController.target(mixed.scene.elements,scale:1)!
        let mixedResult = SceneCornerController.applying(mixed,target:mixedTarget,from:target.point,to:end)
        check(close(mixedResult.scene.elements[0].cornerRadius,20) && close(mixedResult.scene.elements[1].cornerRadius,40), "Shared radius gesture clamps smaller selected leaves")
        withExtendedLifetime(controller) {}
    }

    private static func nativeInspector(_ store: SceneStore) {
        let element = SceneElementModel(kind:.image,frame:CGRect(x:0,y:0,width:320,height:240),cornerRadius:60)
        let state = SceneEditingStateModel(.init(canvasSize:CGSize(width:800,height:500),elements:[element]))
        state.select([element.id])
        let view = SceneInspectorView(frame:.zero), controller = SceneInspectorController(state:state,view:view)
        state.onUpdate = { _ in controller.refresh() }
        let window = NSWindow(contentRect:CGRect(x:0,y:0,width:260,height:1000),styleMask:.titled,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = view; view.layoutSubtreeIfNeeded()
        func descendants(_ view:NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let field = descendants(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "radius" }!
        check(window.makeFirstResponder(field), "Native radius field accepts focus")
        let editor = field.currentEditor() as! NSTextView
        editor.insertText("500",replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
        window.makeFirstResponder(nil)
        RunLoop.current.run(until:Date(timeIntervalSinceNow:0.02))
        check(state.selected[0].cornerRadius == 120 && field.stringValue == "120", "Native radius field shows the clamped value after commit")
        state.undo(); check(state.selected[0].cornerRadius == 60 && field.stringValue == "60", "Undo updates normalized native field")
        withExtendedLifetime(controller) {}
    }

    private static func nativeWidth(_ store: SceneStore) {
        for kind in [SceneElementKind.text,.note] {
            let element = SceneElementModel(kind:kind,frame:CGRect(x:100,y:100,width:240,height:140),cornerRadius:40,text:"A\nA\nA")
            let state = SceneEditingStateModel(.init(canvasSize:CGSize(width:800,height:500),elements:[element]))
            state.select([element.id]); let original = state.value
            let controller = SceneCanvasController(state:state,store:store), canvas = controller.view
            let window = NSWindow(contentRect:CGRect(x:0,y:0,width:844,height:544),styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false; window.contentView = canvas; canvas.editSelection()
            func descendants(_ view:NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let input = descendants(canvas).compactMap { $0 as? NSTextView }.first!
            func resize(_ delta:CGFloat) {
                let right = canvas.convert(CGPoint(x:input.bounds.maxX-1,y:input.bounds.midY),from:input)
                func event(_ type:NSEvent.EventType,_ dx:CGFloat) -> NSEvent {
                    NSEvent.mouseEvent(with:type,location:canvas.convert(CGPoint(x:right.x+dx*canvas.viewport.scale,y:right.y),to:nil),
                        modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
                }
                input.mouseDown(with:event(.leftMouseDown,0)); input.mouseDragged(with:event(.leftMouseDragged,delta)); input.mouseUp(with:event(.leftMouseUp,delta))
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
            resize(-200)
            let narrow = state.value
            check(close(state.selected[0].frame.width,40) && close(state.selected[0].cornerRadius,20), "Native width shrink persists radius clamp")
            resize(200)
            check(close(state.selected[0].frame.width,240) && close(state.selected[0].cornerRadius,20), "Widening retains clamped radius")
            _ = input.perform(NSSelectorFromString("undo:"),with:nil)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            check(state.value == narrow, "Native Undo restores narrow radius checkpoint")
            _ = input.perform(NSSelectorFromString("undo:"),with:nil)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            check(state.value == original && !state.canUndo, "Native Undo restores original radius and geometry")
            canvas.finishText(); check(state.value == original && !state.canUndo, "Finish after width Undo adds no duplicate entry")
            withExtendedLifetime(controller) {}
        }
    }

    private static func nativeMask(_ store: SceneStore) {
        for kind in [SceneElementKind.text,.note] {
            var element = SceneElementModel(kind:kind,frame:CGRect(x:100,y:100,width:240,height:140),rotation:27,cornerRadius:60,text:"Native clipping")
            if kind == .text { element.textScaleX = 2; element.textScaleY = 1.5 }
            let state = SceneEditingStateModel(.init(canvasSize:CGSize(width:800,height:500),elements:[element]))
            state.select([element.id])
            let controller = SceneCanvasController(state:state,store:store), canvas = controller.view
            let window = NSWindow(contentRect:CGRect(x:0,y:0,width:844,height:544),styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false; window.contentView = canvas; canvas.editSelection()
            func descendants(_ view:NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let input = descendants(canvas).compactMap { $0 as? NSTextView }.first!
            let mask = input.superview!.layer!.mask as! CAShapeLayer
            let path = mask.path!
            check(close(path.boundingBoxOfPath.width,input.bounds.width) && close(path.boundingBoxOfPath.height,input.bounds.height), "Native mask is in inverse-scaled input coordinates")
            check(!path.contains(CGPoint(x:0.1,y:0.1)) && path.contains(CGPoint(x:input.bounds.midX,y:input.bounds.midY)), "Native mask clips corners for text and note")
            canvas.finishText(); withExtendedLifetime(controller) {}
        }
    }
}
