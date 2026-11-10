import AppKit

enum SceneImageDestination: Equatable { case add(CGPoint), replace(UUID) }
struct SceneImageInput {
    var data: Data
    var name: String

    init(data: Data, name: String = "Изображение") { self.data = data; self.name = name }
    init(file: URL) throws {
        guard file.isFileURL else { throw SceneError.invalid("Выберите локальный файл изображения.") }
        do { data = try Data(contentsOf: file) } catch {
            throw SceneError.storage("Не удалось прочитать файл «\(file.lastPathComponent)».", error)
        }
        name = file.deletingPathExtension().lastPathComponent
    }
}

enum SceneTransfer {
    static let layerType = NSPasteboard.PasteboardType("local.lockscreenwidget.scene-elements.v1")
    enum Content { case layers([SceneElementModel]), images([SceneImageInput]), text(String) }

    static func write(_ elements: [SceneElementModel], to board: NSPasteboard) throws -> Bool {
        guard !elements.isEmpty else { return false }
        let data = try JSONEncoder().encode(elements)
        board.clearContents()
        return board.setData(data, forType: layerType)
    }

    static func read(_ board: NSPasteboard, allowLayers: Bool = true) throws -> Content? {
        if allowLayers, let data = board.data(forType: layerType) {
            let elements = try JSONDecoder().decode([SceneElementModel].self, from: data)
            _ = try EditorSceneModel(canvasSize: CGSize(width: 1, height: 1), elements: elements).validated()
            return .layers(elements)
        }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty { return .images(try urls.map(SceneImageInput.init(file:))) }
        let items = board.pasteboardItems ?? []
        var images = [SceneImageInput]()
        for item in items {
            if let type = item.availableType(from: [.png, .tiff]), let bytes = item.data(forType: type) {
                images.append(SceneImageInput(data: bytes))
            }
        }
        if !images.isEmpty { return .images(images) }
        if let string = board.string(forType: .string), !string.isEmpty { return .text(string) }
        return nil
    }
}

extension SceneEditingStateModel {
    var insertionPoint: CGPoint { CGPoint(x: scene.canvasSize.width/2, y: scene.canvasSize.height/2) }
    var pasteImageDestination: SceneImageDestination {
        if selected.count == 1, let image = selected.first, image.kind == .image { return .replace(image.id) }
        return .add(insertionPoint)
    }
    func dropDestination(at point: CGPoint) -> SceneImageDestination {
        if let e = hit(point), e.kind == .image { return .replace(e.id) }
        return .add(point)
    }
    func importImages(_ inputs: [SceneImageInput], at destination: SceneImageDestination, store: SceneStore) throws {
        if case .replace(let id) = destination {
            guard inputs.count == 1 else { throw SceneError.invalid("Для замены выберите одно изображение.") }
            guard scene.elements.contains(where: { $0.id == id && $0.kind == .image }) else {
                throw SceneError.invalid("Слой для замены больше не существует.")
            }
        }
        guard !inputs.isEmpty else { return }
        let assets = try store.importImages(data: inputs.map(\.data))
        change { v in
            switch destination {
            case .replace(let target):
                guard let i = v.scene.elements.firstIndex(where: { $0.id == target }) else { return }
                let frame = v.scene.elements[i].frame, size = assets[0].size
                let scale = max(frame.width/size.width, frame.height/size.height)
                let w = size.width*scale, h = size.height*scale
                v.scene.elements[i].assetID = assets[0].assetID
                v.scene.elements[i].imageRect = CGRect(x: (frame.width-w)/2, y: (frame.height-h)/2, width: w, height: h)
                v.selection = [target]
            case .add(let point):
                v.selection = []
                for i in assets.indices {
                    let size = assets[i].size, canvas = v.scene.canvasSize
                    let scale = min(1, canvas.width*0.65/size.width, canvas.height*0.65/size.height)
                    let w = size.width*scale, h = size.height*scale, offset = CGFloat(i)*16
                    let frame = CGRect(x: point.x-w/2+offset, y: point.y-h/2+offset, width: w, height: h)
                    let e = SceneElementModel(kind: .image, frame: frame, name: inputs[i].name, assetID: assets[i].assetID,
                                         imageRect: CGRect(origin: .zero, size: frame.size))
                    v.scene.elements.append(e); v.selection.insert(e.id)
                }
            }
        }
    }
}
