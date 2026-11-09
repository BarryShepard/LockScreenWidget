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
        geometryAndHistory(); try imports(directory,store); try widths(store)
        print("SceneEditingTests passed: rotated selection, history, layer order, group movement, image routing, private pasteboard and text widths")
    }
}
