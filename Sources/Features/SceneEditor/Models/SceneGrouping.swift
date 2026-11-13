import Foundation

enum SceneAlignment: Int, CaseIterable {
    case left, horizontalCenter, right, top, verticalCenter, bottom
}

extension SceneEditingStateModel {
    func expandedSelection(_ ids: Set<UUID>) -> Set<UUID> {
        let roots = Set(scene.elements.filter { ids.contains($0.id) }.compactMap { $0.groups?.first?.id })
        return ids.union(scene.elements.filter { $0.groups?.first.map { roots.contains($0.id) } ?? false }.map(\.id))
    }

    /// Highest fully selected group is one unit; partial selections remain independent.
    func selectionUnits() -> [[SceneElementModel]] {
        var used = Set<UUID>(), units: [[SceneElementModel]] = []
        for item in selected where !used.contains(item.id) {
            let complete = (item.groups ?? []).first { group in
                scene.elements.filter { $0.groups?.contains(where: { $0.id == group.id }) == true }.allSatisfy { selection.contains($0.id) }
            }
            let members = complete.map { group in
                selected.filter { $0.groups?.contains(where: { $0.id == group.id }) == true }
            } ?? [item]
            units.append(members); used.formUnion(members.map(\.id))
        }
        return units
    }

    func groupSelection() {
        guard selectionUnits().count > 1 else { return }
        var prefix = selected[0].groups ?? []
        for item in selected.dropFirst() {
            let path = item.groups ?? []
            prefix = Array(zip(prefix, path).prefix { $0.0.id == $0.1.id }.map { $0.0 })
        }
        let depth = prefix.count
        let branches = Set(selected.compactMap { item -> UUID? in
            let path = item.groups ?? []
            return path.count > depth ? path[depth].id : nil
        })
        // Include whole branches when grouping leaves from different parent groups.
        let ids = selection.union(scene.elements.filter { item in
            let path = item.groups ?? []
            return path.count > depth && branches.contains(path[depth].id)
        }.map(\.id))
        let chosen = scene.elements.filter { ids.contains($0.id) }
        let units = Set(chosen.map { item in
            let path = item.groups ?? []
            return path.count > depth ? path[depth].id : item.id
        })
        guard units.count > 1, chosen.allSatisfy({ ($0.groups?.count ?? 0) < 32 }) else { return }
        let group = SceneGroupMembership(id: UUID())
        change { value in
            for i in value.scene.elements.indices where ids.contains(value.scene.elements[i].id) {
                var path = value.scene.elements[i].groups ?? []
                path.insert(group, at: depth)
                value.scene.elements[i].groups = path
            }
            value.selection = ids
        }
    }

    func ungroupSelection() {
        let groups = Set(selectionUnits().compactMap { members in
            members.first?.groups?.first { group in
                scene.elements.filter { $0.groups?.contains(where: { $0.id == group.id }) == true }.allSatisfy { selection.contains($0.id) }
            }?.id
        })
        guard !groups.isEmpty else { return }
        change { value in
            for i in value.scene.elements.indices {
                let path = value.scene.elements[i].groups?.filter { !groups.contains($0.id) }
                value.scene.elements[i].groups = path?.isEmpty == false ? path : nil
            }
        }
    }

    func align(_ alignment: SceneAlignment) {
        let units = selectionUnits()
        guard units.count > 1, let bounds = SceneGeometry.bounds(selected) else { return }
        var offsets: [UUID: CGPoint] = [:]
        for unit in units {
            guard let box = SceneGeometry.bounds(unit) else { continue }
            let delta: CGPoint
            switch alignment {
            case .left: delta = CGPoint(x: bounds.minX-box.minX, y: 0)
            case .horizontalCenter: delta = CGPoint(x: bounds.midX-box.midX, y: 0)
            case .right: delta = CGPoint(x: bounds.maxX-box.maxX, y: 0)
            case .top: delta = CGPoint(x: 0, y: bounds.minY-box.minY)
            case .verticalCenter: delta = CGPoint(x: 0, y: bounds.midY-box.midY)
            case .bottom: delta = CGPoint(x: 0, y: bounds.maxY-box.maxY)
            }
            for item in unit { offsets[item.id] = delta }
        }
        change { value in
            for i in value.scene.elements.indices {
                guard let delta = offsets[value.scene.elements[i].id] else { continue }
                value.scene.elements[i].frame.origin.x += delta.x
                value.scene.elements[i].frame.origin.y += delta.y
            }
        }
    }
}
