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
