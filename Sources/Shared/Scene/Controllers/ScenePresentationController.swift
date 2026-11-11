import AppKit

/// Resolves document content into values that the renderer can draw directly.
final class ScenePresentationController {
    private let store: SceneStore
    private let cache = NSCache<NSString, NSImage>()
    private var lastPresentation: (scene: EditorSceneModel, content: SceneRenderContent)?

    init(store: SceneStore) {
        self.store = store
        cache.countLimit = 32
        cache.totalCostLimit = 64*1024*1024
    }

    func content(for scene: EditorSceneModel) -> SceneRenderContent {
        if let lastPresentation, lastPresentation.scene == scene { return lastPresentation.content }
        let content = SceneRenderContent(canvasSize: scene.canvasSize, elements: scene.elements.map { element in
            let box = CGRect(origin: .zero, size: element.frame.size)
            let drawing: SceneRenderDrawing
            switch element.kind {
            case .text:
                let y = SceneTextLayout.yOffset(element)
                drawing = .text(NSAttributedString(string: element.text,
                    attributes: SceneTextLayout.attributes(element.style)),
                    frame: CGRect(x: 0, y: y, width: box.width, height: max(1, box.height-y)))
            case .image:
                if let id = element.assetID, let image = image(id) {
                    drawing = .image(image, frame: element.imageRect ?? box)
                } else {
                    drawing = .missingImage(label: NSAttributedString(string: "Нет изображения",
                        attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13)]),
                        frame: box.insetBy(dx: 5, dy: 5), background: NSColor(white: 0.25, alpha: 0.85))
                }
            }
            return SceneRenderElement(id: element.id, frame: element.frame, rotation: element.rotation,
                cornerRadius: element.cornerRadius, opacity: element.opacity, drawing: drawing)
        })
        lastPresentation = (scene, content)
        return content
    }

    private func image(_ id: String) -> NSImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let image = store.image(for: id) else { return nil }
        let size = image.representations.first
        let cost = min(64*1024*1024.0, CGFloat(size?.pixelsWide ?? 1)*CGFloat(size?.pixelsHigh ?? 1)*4)
        cache.setObject(image, forKey: id as NSString, cost: Int(max(1, cost)))
        return image
    }
}
