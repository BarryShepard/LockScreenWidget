import AppKit

final class SceneInspectorController {
    var onFocus: (() -> Void)?
    var onError: ((String) -> Void)?

    private let state: SceneEditingStateModel
    private let view: SceneInspectorView
    private let families = ["System"] + NSFontManager.shared.availableFontFamilies.sorted()
    private struct LayerRow {
        let title: String
        let ids: Set<UUID>
        let ancestors: [UUID]
        let groupID: UUID?
    }
    private var rowSelections = [Set<UUID>]()
    private func layerRows() -> [LayerRow] {
        let leaves = Array(state.scene.elements.reversed())
        func rows(_ items: [SceneElementModel], depth: Int, ancestors: [UUID]) -> [LayerRow] {
            var result: [LayerRow] = [], seen = Set<UUID>()
            for item in items {
                let path = item.groups ?? []
                let indent = String(repeating: "  ", count: depth)
                if path.count > depth {
                    let group = path[depth]
                    guard seen.insert(group.id).inserted else { continue }
                    let children = items.filter { ($0.groups ?? []).dropFirst(depth).first?.id == group.id }
                    result.append(LayerRow(title: indent + "▾ " + group.name, ids: Set(children.map(\.id)), ancestors: ancestors, groupID: group.id))
                    result += rows(children, depth: depth+1, ancestors: ancestors + [group.id])
                } else {
                    result.append(LayerRow(title: indent + item.name, ids: [item.id], ancestors: ancestors, groupID: nil))
                }
            }
            return result
        }
        return rows(leaves, depth: 0, ancestors: [])
    }
    private var selectedGroup: SceneGroupMembership? {
        guard let first = state.selected.first else { return nil }
        return first.groups?.first { group in
            Set(state.scene.elements.filter { $0.groups?.contains(where: { $0.id == group.id }) == true }.map(\.id)) == state.selection
        }
    }
    let countdown: SceneCountdownInspectorController
    let clock: SceneClockInspectorController

    init(state: SceneEditingStateModel, view: SceneInspectorView, catalog: EventCatalogModel = .init(), now: Date = Date()) {
        countdown = SceneCountdownInspectorController(state: state, view: view.countdown, catalog: catalog, now: now)
        clock = SceneClockInspectorController(state: state, view: view.clock)
        self.state = state
        self.view = view
        view.onFocus = { [weak self] in self?.onFocus?() }
        view.onSelectionChange = { [weak self] indices in
            guard let self else { return }
            self.state.select(Set(indices.filter { self.rowSelections.indices.contains($0) }.flatMap { self.rowSelections[$0] }), expandingGroups: false)
            self.onFocus?()
        }
        view.onFieldChange = { [weak self] key, raw, label in self?.applyField(key: key, raw: raw, label: label) }
        view.onMenuChange = { [weak self] key, index in self?.applyMenu(key: key, index: index) }
        view.onAlign = { [weak self] index in
            guard let alignment = SceneAlignment(rawValue: index) else { return }
            self?.state.align(alignment); self?.onFocus?()
        }
        view.onCenter = { [weak self] horizontal in self?.center(horizontal: horizontal) }
        refresh()
    }

    func refresh() {
        rowSelections = layerRows().map(\.ids)
        view.render(makePresentation())
        countdown.refresh()
        clock.refresh()
    }

    func makePresentation() -> SceneInspectorPresentation {
        let layers = layerRows()
        let selected = state.selected, texts = selected.filter { $0.kind.hasTypography }
        let notes = selected.filter { $0.kind == .note }
        var menus: [String: SceneInspectorMenuPresentation] = [
            "family": .init(items: families.map { $0 == "System" ? "Системный" : $0 }, selectedIndex: nil),
            "weight": .init(items: ["Сверхтонкое", "Тонкое", "Лёгкое", "Обычное", "Среднее", "Полужирное", "Жирное", "Тяжёлое", "Чёрное"], selectedIndex: nil),
            "align": .init(items: ["Слева", "По центру", "Справа"], selectedIndex: nil),
            "valign": .init(items: ["Сверху", "По центру", "Снизу"], selectedIndex: nil)
        ]
        let fullySelectedGroups = Set(layers.filter { $0.groupID != nil && $0.ids.isSubset(of: state.selection) }.compactMap(\.groupID))
        let selectedRows = IndexSet(layers.indices.filter { index in
            let row = layers[index]
            return row.ids.isSubset(of: state.selection) && row.ancestors.allSatisfy { !fullySelectedGroups.contains($0) }
        })
        if selected.isEmpty {
            let width = Int(clampingScene: state.scene.canvasSize.width)
            let height = Int(clampingScene: state.scene.canvasSize.height)
            return SceneInspectorPresentation(layers: layers.map(\.title), selectedRows: selectedRows,
                selectionTitle: "Композиция",
                emptyMessage: "Основной экран · \(width) × \(height) pt\nВыберите слой на холсте или в списке.",
                showsTextControls: false, fields: [:], menus: menus, missingFontMessage: nil)
        }

        func number(_ value: CGFloat) -> String {
            String(format: "%.3f", value).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
        var fields = [String: SceneInspectorFieldPresentation]()
        func field(_ key: String, _ value: String?) {
            fields[key] = .init(text: value ?? "", placeholder: value == nil ? "Разные" : nil)
        }
        field("name", selectedGroup?.name ?? uniform(selected.map(\.name)))
        let group = selected.count > 1 ? SceneGeometry.bounds(selected) : nil
        field("x", (group?.minX ?? selected.first?.frame.minX).map(number))
        field("y", (group?.minY ?? selected.first?.frame.minY).map(number))
        field("w", (selectedGroup != nil ? SceneGeometry.bounds(selected)?.width : uniform(selected.map { $0.frame.width })).map(number))
        field("h", (selectedGroup != nil ? SceneGeometry.bounds(selected)?.height : uniform(selected.map { $0.frame.height })).map(number))
        field("opacity", uniform(selected.map { $0.opacity * 100 }).map(number))

        if !notes.isEmpty {
            field("background", uniform(notes.map { $0.resolvedNote.background }).map {
                [$0.red, $0.green, $0.blue, $0.alpha].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
            })
            field("padding", uniform(notes.map { $0.resolvedNote.padding }).map { number($0) })
            field("radius", uniform(notes.map { $0.cornerRadius }).map { number($0) })
        }
        var missingFontMessage: String?
        if !texts.isEmpty {
            field("size", uniform(texts.map { $0.style.fontSize }).map { number(CGFloat($0)) })
            field("spacing", uniform(texts.map { $0.style.letterSpacing }).map { number(CGFloat($0)) })
            field("line", uniform(texts.map { $0.style.lineHeight }).map { $0 == 0 ? "Авто" : number(CGFloat($0)) })
            field("color", uniform(texts.map { $0.style.color }).map {
                [$0.red, $0.green, $0.blue, $0.alpha].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
            })
            menus["family"]?.selectedIndex = uniform(texts.map { $0.style.family }).flatMap { families.firstIndex(of: $0) }
            menus["weight"]?.selectedIndex = uniform(texts.map { $0.style.weight })
            menus["align"]?.selectedIndex = uniform(texts.map { $0.style.horizontalAlignment })
            menus["valign"]?.selectedIndex = uniform(texts.map { $0.style.verticalAlignment })
            let unavailable = Set(texts.map { $0.style.family }.filter { !families.contains($0) })
            if !unavailable.isEmpty {
                missingFontMessage = "Нет шрифта \(unavailable.sorted().joined(separator: ", ")). Показан системный."
            }
        }
        return SceneInspectorPresentation(layers: layers.map(\.title), selectedRows: selectedRows,
            selectionTitle: selectedGroup != nil ? "Свойства группы" : selected.count == 1 ? "Свойства слоя" : "Выделено: \(selected.count)",
            emptyMessage: nil, showsTextControls: !texts.isEmpty,
            fields: fields, menus: menus, missingFontMessage: missingFontMessage, showsNoteControls: !notes.isEmpty, overflowMessage: notes.contains(where: SceneTextLayout.overflows) ? "Текст не помещается в заметке." : nil, canAlign: state.selectionUnits().count > 1)
    }

    func select(ids: Set<UUID>) {
        state.select(ids)
        onFocus?()
    }

    func center(horizontal: Bool) {
        state.center(horizontal: horizontal)
        onFocus?()
    }

    func applyMenu(key: String, index: Int) {
        switch key {
        case "family": guard families.indices.contains(index) else { return }
        case "weight": guard (0...8).contains(index) else { return }
        case "align", "valign": guard (0...2).contains(index) else { return }
        default: return
        }
        state.editSelected { element in
            guard element.kind.hasTypography else { return }
            switch key {
            case "family": element.style.family = families[index]
            case "weight": element.style.weight = index
            case "align": element.style.horizontalAlignment = index
            case "valign": element.style.verticalAlignment = index
            default: break
            }
            if key == "family" || key == "weight" { SceneTextLayout.fit(&element, minimumHeight: element.frame.height) }
        }
        onFocus?()
    }

    func applyField(key: String, raw: String, label: String) {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { refresh(); return }
        let number = Double(raw.replacingOccurrences(of: ",", with: "."))
        let color = Self.parseColor(raw)
        let auto = raw.localizedCaseInsensitiveCompare("Авто") == .orderedSame
        let valid: Bool
        switch key {
        case "name": valid = true
        case "color", "background": valid = color != nil
        case "w", "h", "size": valid = number.map { $0.isFinite && $0 > 0 } == true
        case "opacity": valid = number.map { (0...100).contains($0) } == true
        case "line": valid = auto || number.map { $0.isFinite && $0 >= 0 } == true
        case "padding", "radius": valid = number.map { $0.isFinite && $0 >= 0 } == true
        case "x", "y", "spacing": valid = number?.isFinite == true
        default: return
        }
        guard valid else {
            onError?("Проверьте значение поля «\(label)».")
            refresh()
            return
        }
        if key == "name", let group = selectedGroup {
            state.change { value in
                for i in value.scene.elements.indices {
                    value.scene.elements[i].groups = value.scene.elements[i].groups?.map { membership in
                        var updated = membership
                        if membership.id == group.id { updated.name = raw }
                        return updated
                    }
                }
            }
            onFocus?()
            return
        }
        if (key == "w" || key == "h"), selectedGroup != nil, let bounds = SceneGeometry.bounds(state.selected) {
            let factor = number! / (key == "w" ? bounds.width : bounds.height)
            guard factor.isFinite, factor > 0 else { refresh(); return }
            state.change { $0 = SceneTransformController.scaling($0, factor: factor, anchor: bounds.origin) }
            return
        }
        let group = state.selected.count > 1 ? SceneGeometry.bounds(state.selected) : nil
        state.editSelected { element in
            switch key {
            case "name": element.name = raw
            case "x": element.frame.origin.x = group.map { element.frame.origin.x + number! - $0.minX } ?? number!
            case "y": element.frame.origin.y = group.map { element.frame.origin.y + number! - $0.minY } ?? number!
            case "w", "h":
                let sx = key == "w" ? number! / element.frame.width : 1
                let sy = key == "h" ? number! / element.frame.height : 1
                if let rect = element.imageRect {
                    element.imageRect = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
                }
                if key == "w" {
                    element.frame.size.width = number!
                    if element.kind == .text { element.autoTextWidth = false }
                } else { element.frame.size.height = number! }
            case "opacity": element.opacity = number! / 100
            case "background", "padding", "radius":
                guard element.kind == .note else { return }
                var note = element.resolvedNote
                if key == "background" { note.background = color! }
                if key == "padding" { note.padding = number! }
                if key == "radius" { element.cornerRadius = number! }
                element.note = note
            default:
                guard element.kind.hasTypography else { return }
                switch key {
                case "color": element.style.color = color!
                case "size": element.style.fontSize = number!
                case "spacing": element.style.letterSpacing = number!
                case "line": element.style.lineHeight = auto ? 0 : number!
                default: break
                }
                if key != "color" { SceneTextLayout.fit(&element, minimumHeight: element.frame.height) }
            }
        }
    }

    private func uniform<T: Equatable>(_ values: [T]) -> T? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private static func parseColor(_ raw: String) -> SceneColor? {
        var value = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        if value.count == 6 { value += "FF" }
        guard value.count == 8, let hex = UInt32(value, radix: 16) else { return nil }
        func channel(_ shift: Int) -> Double { Double((hex >> shift) & 255) / 255 }
        return SceneColor(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }
}

private extension Int {
    init(clampingScene value: CGFloat) { self = value >= CGFloat(Int.max) ? Int.max : Int(value) }
}
