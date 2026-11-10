import AppKit

@main struct SceneEditingTests {
    static func check(_ ok: Bool, _ message: String) { precondition(ok, message) }
    static let size = CGSize(width: 800,height: 500)
    static func item(_ x: CGFloat) -> SceneElement {
        SceneElement(kind: .text, frame: CGRect(x: x,y: 100,width: 100,height: 20))
    }
    static func geometryAndHistory() {
        var a = item(100); a.rotation = 45
        let b = item(300), c = item(500), d = item(650)
        let model = SceneEditingState(EditorScene(canvasSize: size,elements: [a,b,c,d]))
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
        let duplicated = SceneEditingState.inserting(model.selected, into: before, offset: 0)
        model.preview(SceneEditingState.moved(duplicated, dx: 5, dy: -10))
        model.preview(SceneEditingState.moved(duplicated, dx: 20, dy: -30)); model.finish(from: before)
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
    static func cancelCanvasDrag(_ store: SceneStore, duplicate: Bool) {
        _ = NSApplication.shared
        let first = item(50), second = item(300)
        let model = SceneEditingState(EditorScene(canvasSize: size, elements: [first, second]))
        model.select(duplicate ? [first.id, second.id] : [first.id])
        let beforeLastEdit = model.value
        model.editSelected { $0.name = "Сохранённый слой" }
        let beforeMouseDown = model.value
        var commits = 0
        model.onUpdate = { if case .committed = $0 { commits += 1 } }

        let canvas = SceneCanvasView(state: model, store: store)
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
        let model = SceneEditingState(EditorScene(canvasSize: size, elements: [first, second]))
        let canvas = SceneCanvasView(state: model, store: store)
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
            check(model.value == SceneEditingState.moved(original, dx: 24, dy: 0),
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
        let model = SceneEditingState(EditorScene(canvasSize: size))
        let empty = model.value
        let good = SceneImageInput(data: complete), bad = SceneImageInput(data: truncated)
        try model.importImages([good], at: .add(model.insertionPoint), store: store)
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
                try model.importImages(inputs, at: target, store: store)
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
            try model.importImages([good, bad], at: .add(.zero), store: store)
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
        let model = SceneEditingState(EditorScene(canvasSize: size))
        try model.importImages(fileInputs, at: .add(CGPoint(x: 200,y: 200)), store: store)
        var original = model.selected[0]
        model.editSelected { $0.rotation = 28; $0.cornerRadius = 5; $0.opacity = 0.4 }
        original = model.selected[0]
        let captured = model.pasteImageDestination
        check(captured == .replace(original.id), "Clipboard captures selected image")
        try FileManager.default.removeItem(at: file)
        board.clearContents(); check(board.setData(png, forType: .png), "Private board accepts PNG")
        try model.importImages(try images(), at: .add(CGPoint(x: 550,y: 400)), store: store)
        let second = model.selected[0]
        check(model.scene.elements.count == 2 && second.id != original.id, "Explicit add ignores selected photo")
        check(model.dropDestination(at: CGPoint(x: 200,y: 200)) == .replace(original.id), "Drop targets hit image independently of selection")
        let free = CGPoint(x: 10,y: 20)
        check(model.dropDestination(at: free) == .add(free), "Drop on empty canvas adds")
        board.clearContents(); check(board.setData(tiff, forType: .tiff), "Private board accepts TIFF")
        let tiffInputs = try images()
        try model.importImages(tiffInputs, at: captured, store: store)
        let replaced = model.scene.elements[0]
        var expected = original; expected.assetID = replaced.assetID; expected.imageRect = replaced.imageRect
        check(replaced == expected && replaced.assetID != original.assetID && model.scene.elements[1] == second,
              "Replace only captured source and placement")
        check(replaced.imageRect == CGRect(x: 0,y: -120,width: 64,height: 256), "Center-fill with original aspect ratio")
        model.undo()
        check(model.scene.elements == [original,second] && store.image(for: original.assetID!) != nil, "Old imported source survives replacement Undo")
        let before = model.value
        do { try model.importImages([fileInputs[0],SceneImageInput(data: Data([1,2]))], at: .add(free), store: store)
            fatalError("Broken batch accepted") } catch {}
        check(model.value == before, "Broken batch leaves scene and selection unchanged")
        try model.importImages([fileInputs[0],tiffInputs[0]], at: .add(free), store: store)
        check(model.selected.count == 2, "Batch selects new images")
        check(model.pasteImageDestination == .add(model.insertionPoint), "Multiple selection pastes as new layers")
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
        try store.save(EditorScene(canvasSize: size, elements: [e]))
        check(try store.load()?.elements.first?.autoTextWidth == true, "Automatic mode survives restart")
        e.autoTextWidth = nil; e.frame.size.width = 60; SceneTextLayout.fit(&e)
        check(e.frame.width == 60 && e.frame.height > e.style.fontSize, "Fixed-width text wraps without growing sideways")
        let bytes = try JSONEncoder().encode(e)
        check(!String(decoding: bytes,as: UTF8.self).contains("autoTextWidth"), "Older payload has no width mode")
        check(try JSONDecoder().decode(SceneElement.self, from: bytes).autoTextWidth == nil, "Older payload decodes as fixed")
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        geometryAndHistory()
        cancelCanvasDrag(store, duplicate: false)
        cancelCanvasDrag(store, duplicate: true)
        shiftGestures(store)
        try truncatedImports(directory, store)
        try imports(directory,store); try widths(store)
        print("SceneEditingTests passed: rotated selection, history, layer order, group movement, Shift-click and Shift-held drag, Escape during move/copy, image routing, private pasteboard and text widths")
    }
}
