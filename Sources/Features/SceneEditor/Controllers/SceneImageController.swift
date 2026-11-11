import AppKit

final class SceneImageController {
    private let state: SceneEditingStateModel
    private let store: SceneStore

    init(state: SceneEditingStateModel, store: SceneStore) {
        self.state = state
        self.store = store
    }
    var insertionPoint: CGPoint { CGPoint(x: state.scene.canvasSize.width/2, y: state.scene.canvasSize.height/2) }
    var pasteImageDestination: SceneImageDestination {
        if state.selected.count == 1, let image = state.selected.first, image.kind == .image { return .replace(image.id) }
        return .add(insertionPoint)
    }
    func dropDestination(at point: CGPoint) -> SceneImageDestination {
        if let e = state.hit(point), e.kind == .image { return .replace(e.id) }
        return .add(point)
    }
    func importImages(_ inputs: [SceneImageInput], at destination: SceneImageDestination) throws {
        if case .replace(let id) = destination {
            guard inputs.count == 1 else { throw SceneError.invalid("Для замены выберите одно изображение.") }
            guard state.scene.elements.contains(where: { $0.id == id && $0.kind == .image }) else {
                throw SceneError.invalid("Слой для замены больше не существует.")
            }
        }
        guard !inputs.isEmpty else { return }
        let assets = try store.importImages(data: inputs.map(\.data))
        state.change { v in
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
