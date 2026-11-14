import AppKit

final class SceneCanvasContextMenuController {
    private let state: SceneEditingStateModel
    init(state: SceneEditingStateModel) { self.state = state }

    func items(at point: CGPoint, board: NSPasteboard) -> [SceneCanvasMenuItem] {
        // A locked object can offer Unlock only if it was already chosen in layers.
        let hit = state.scene.elements.last {
            (!$0.isLocked || state.selection.contains($0.id)) &&
                SceneGeometry.intersects($0, CGRect(origin: point, size: .zero))
        }
        if let hit {
            if !state.selection.contains(hit.id) { state.selectFromCanvas([hit.id]) }
        } else { state.select([]) }
        let add = SceneCanvasMenuItem(title: "Добавить", children: SceneCanvasTool.allCases.map {
            .init(title: $0.title, action: .place($0, point))
        })
        let paste = SceneCanvasMenuItem(title: "Вставить сюда", action: .pasteHere(point), enabled: SceneTransfer.canRead(board))
        guard hit != nil else { return [add, paste] }
        let selected = state.selected
        let image = selected.count == 1 && selected[0].kind == .image ? selected[0].id : nil
        let canUngroup = state.selectionUnits().contains { members in
            members.first?.groups?.contains { group in
                state.scene.elements.filter { $0.groups?.contains(where: { $0.id == group.id }) == true }
                    .allSatisfy { state.selection.contains($0.id) }
            } == true
        }
        return [
            .init(title: "Копировать", action: .copy), paste,
            .init(title: "Вставить с заменой", action: image.map { .pasteReplacing($0) },
                  enabled: image != nil && SceneTransfer.canRead(board, imagesOnly: true)),
            .init(title: ""),
            .init(title: "На передний план", action: .front),
            .init(title: "На задний план", action: .back),
            .init(title: ""),
            .init(title: "Сгруппировать выделенное", action: .group, enabled: state.selectionUnits().count > 1),
            .init(title: "Разгруппировать", action: .ungroup, enabled: canUngroup),
            .init(title: selected.allSatisfy(\.isLocked) ? "Разблокировать" : "Заблокировать", action: .toggleLock),
            .init(title: ""), add
        ]
    }
}
