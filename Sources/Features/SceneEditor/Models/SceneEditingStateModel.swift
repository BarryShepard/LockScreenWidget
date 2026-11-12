import Foundation

enum SceneGeometry {
    static func corners(_ e: SceneElementModel) -> [CGPoint] {
        let f = e.frame, a = CGFloat(e.rotation * .pi / 180), c = cos(a), s = sin(a)
        return [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)].map {
            let x = $0.x - f.midX, y = $0.y - f.midY
            return CGPoint(x: f.midX + x*c - y*s, y: f.midY + x*s + y*c)
        }
    }
    static func bounds(_ elements: [SceneElementModel]) -> CGRect? {
        let p = elements.flatMap(corners)
        guard let x = p.map(\.x).min(), let y = p.map(\.y).min() else { return nil }
        return CGRect(x: x, y: y, width: p.map(\.x).max()! - x, height: p.map(\.y).max()! - y)
    }
    /// Separating-axis test; the bounding box alone selects empty rotated corners.
    static func intersects(_ e: SceneElementModel, _ r: CGRect) -> Bool {
        let p = corners(e), a = CGFloat(e.rotation * .pi / 180)
        let q = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                 CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        return [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: cos(a), y: sin(a)),
                CGPoint(x: -sin(a), y: cos(a))].allSatisfy { axis in
            let left = p.map { $0.x * axis.x + $0.y * axis.y }
            let right = q.map { $0.x * axis.x + $0.y * axis.y }
            return left.max()! >= right.min()! && right.max()! >= left.min()!
        }
    }
}

enum SceneLayerOrder { case forward, backward, front, back }
enum SceneUpdate { case selection, preview, typing, committed }
struct SceneSnapshot: Equatable {
    var scene: EditorSceneModel
    var selection: Set<UUID>
}

final class SceneEditingStateModel {
    private(set) var value: SceneSnapshot
    private struct HistoryEntry { let id: UUID; let snapshot: SceneSnapshot }
    private var past = [HistoryEntry](), future = [HistoryEntry]()
    var onUpdate: ((SceneUpdate) -> Void)?
    var scene: EditorSceneModel { value.scene }
    var selection: Set<UUID> { value.selection }
    var selected: [SceneElementModel] { scene.elements.filter { selection.contains($0.id) } }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    init(_ scene: EditorSceneModel) { value = SceneSnapshot(scene: scene, selection: []) }

    func select(_ ids: Set<UUID>) {
        let valid = ids.intersection(scene.elements.map(\.id))
        guard valid != selection else { return }
        value.selection = valid
        onUpdate?(.selection)
    }
    func hit(_ point: CGPoint) -> SceneElementModel? {
        scene.elements.last { SceneGeometry.intersects($0, CGRect(origin: point, size: .zero)) }
    }
    func marquee(_ rect: CGRect) -> Set<UUID> {
        Set(scene.elements.filter { SceneGeometry.intersects($0, rect) }.map(\.id))
    }
    /// Preview from a stable starting snapshot. Repeated mouse/typing events do not add history.
    func preview(_ next: SceneSnapshot, typing: Bool = false) {
        value = next
        onUpdate?(typing ? .typing : .preview)
    }
    @discardableResult
    func finish(from initial: SceneSnapshot) -> UUID? {
        if value.scene != initial.scene {
            let id = UUID()
            past.append(HistoryEntry(id: id, snapshot: initial))
            if past.count > 150 { past.removeFirst() }
            future.removeAll()
            onUpdate?(.committed)
            return id
        }
        onUpdate?(.selection)
        return nil
    }
    func change(_ edit: (inout SceneSnapshot) -> Void) {
        let initial = value
        edit(&value)
        finish(from: initial)
    }
    func undo() { _ = undoEntry(nil) }
    func redo() { _ = redoEntry(nil) }
    @discardableResult
    func undoEntry(_ id: UUID?) -> Bool {
        guard let previous = past.last, id == nil || previous.id == id else { return false }
        past.removeLast()
        future.append(HistoryEntry(id: previous.id, snapshot: value))
        value = previous.snapshot; onUpdate?(.committed)
        return true
    }
    @discardableResult
    func redoEntry(_ id: UUID?) -> Bool {
        guard let next = future.last, id == nil || next.id == id else { return false }
        future.removeLast()
        past.append(HistoryEntry(id: next.id, snapshot: value))
        value = next.snapshot; onUpdate?(.committed)
        return true
    }
    /// Cross an existing typing checkpoint only after its non-derived fields are verified.
    func reconcileTextHistory(from before: SceneSnapshot, undo: Bool,
                              matches: (SceneSnapshot, SceneSnapshot) -> Bool) -> Bool {
        guard before.scene != value.scene else { return false }
        if undo, let previous = past.last, matches(previous.snapshot, value) {
            past.removeLast(); future.append(HistoryEntry(id: previous.id, snapshot: before))
            value = previous.snapshot; onUpdate?(.committed); return true
        }
        if !undo, let next = future.last, matches(next.snapshot, value) {
            future.removeLast(); past.append(HistoryEntry(id: next.id, snapshot: before))
            value = next.snapshot; onUpdate?(.committed); return true
        }
        return false
    }
    func editSelected(_ edit: (inout SceneElementModel) -> Void) {
        change { v in
            for i in v.scene.elements.indices where v.selection.contains(v.scene.elements[i].id) { edit(&v.scene.elements[i]) }
        }
    }
    func deleteSelection() {
        change { v in v.scene.elements.removeAll { v.selection.contains($0.id) }; v.selection = [] }
    }
    static func moved(_ start: SceneSnapshot, dx: CGFloat, dy: CGFloat) -> SceneSnapshot {
        var v = start
        for i in v.scene.elements.indices where v.selection.contains(v.scene.elements[i].id) {
            v.scene.elements[i].frame.origin.x += dx; v.scene.elements[i].frame.origin.y += dy
        }
        return v
    }
    static func inserting(_ items: [SceneElementModel], into start: SceneSnapshot, offset: CGFloat) -> SceneSnapshot {
        var v = start
        let copies = items.map { item -> SceneElementModel in
            var e = item
            e.id = UUID(); e.frame = item.frame.offsetBy(dx: offset, dy: offset)
            return e
        }
        v.scene.elements += copies; v.selection = Set(copies.map(\.id))
        return v
    }
    func move(dx: CGFloat, dy: CGFloat) { change { $0 = Self.moved($0, dx: dx, dy: dy) } }
    func center(horizontal: Bool) {
        guard let box = SceneGeometry.bounds(selected) else { return }
        move(dx: horizontal ? scene.canvasSize.width/2 - box.midX : 0,
             dy: horizontal ? 0 : scene.canvasSize.height/2 - box.midY)
    }
    func insertCopies(_ items: [SceneElementModel]) {
        guard !items.isEmpty else { return }
        change { $0 = Self.inserting(items, into: $0, offset: 12) }
    }
    func reorder(_ order: SceneLayerOrder) {
        change { v in
            var items = v.scene.elements
            let ids = v.selection, chosen = items.filter { ids.contains($0.id) }, others = items.filter { !ids.contains($0.id) }
            switch order {
            case .front: items = others + chosen
            case .back: items = chosen + others
            case .forward:
                for i in items.indices.dropLast().reversed() where ids.contains(items[i].id) && !ids.contains(items[i+1].id) {
                    items.swapAt(i, i+1)
                }
            case .backward:
                for i in items.indices.dropFirst() where ids.contains(items[i].id) && !ids.contains(items[i-1].id) {
                    items.swapAt(i, i-1)
                }
            }
            v.scene.elements = items
        }
    }
}
