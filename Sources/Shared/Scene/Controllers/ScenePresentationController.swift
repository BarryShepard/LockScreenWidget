import AppKit

/// Resolves document content into values that the renderer can draw directly.
final class ScenePresentationController {
    private let store: SceneStore
    private let cache = NSCache<NSString, NSImage>()
    private var lastPresentation: (scene: EditorSceneModel, values: [UUID: String], content: SceneRenderContent)?

    init(store: SceneStore) {
        self.store = store
        cache.countLimit = 32
        cache.totalCostLimit = 64*1024*1024
    }

    func content(for scene: EditorSceneModel, catalog: EventCatalogModel = .init(), at now: Date = Date()) -> SceneRenderContent {
        let values = Dictionary(uniqueKeysWithValues: scene.elements.compactMap { element -> (UUID, String)? in
            guard element.kind == .countdown, let timer = element.countdown else { return nil }
            return (element.id, SceneCountdownPresentationController.value(timer, catalog: catalog, at: now))
        })
        if let lastPresentation, lastPresentation.scene == scene, lastPresentation.values == values { return lastPresentation.content }
        let content = SceneRenderContent(canvasSize: scene.canvasSize, elements: scene.elements.map { original in
            var element = original
            if element.kind == .countdown { element.text = values[element.id] ?? "0 дней 00:00:00" }
            let box = CGRect(origin: .zero, size: element.frame.size)
            let drawing: SceneRenderDrawing
            switch element.kind {
            case .text, .note, .countdown:
                let y = SceneTextLayout.yOffset(element)
                let rect = SceneTextLayout.contentRect(element)
                let text = NSAttributedString(string: element.text,
                    attributes: SceneTextLayout.attributes(element.style))
                if element.kind == .note {
                    drawing = .note(text, frame: CGRect(x: rect.minX, y: y, width: rect.width, height: max(0, rect.maxY-y)), background: SceneTextLayout.color(element.resolvedNote.background))
                } else {
                    drawing = .text(text, frame: CGRect(x: 0, y: y, width: box.width / (element.textScaleX ?? 1), height: max(1, box.height / (element.textScaleY ?? 1)-y)), scaleX: element.textScaleX ?? 1, scaleY: element.textScaleY ?? 1)
                }
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
        lastPresentation = (scene, values, content)
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
