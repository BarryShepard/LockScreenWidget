import AppKit

private final class SceneStackView: NSView { override var isFlipped: Bool { true } }

private final class SceneLayerTable: NSTableView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onClick?() // Also return focus when the already-selected row was clicked.
    }
}

final class SceneInspectorView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let state: SceneEditingState
    var onFocus: (() -> Void)?
    var onError: ((String) -> Void)?
    private let table = SceneLayerTable(), properties = NSStackView()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "Свойства")
    private var fields = [String: NSTextField](), menus = [String: NSPopUpButton]()
    private var changedField: NSTextField?
    private var rows: [(UUID, String)] = [], syncing = false
    private let families = ["System"] + NSFontManager.shared.availableFontFamilies.sorted()
    private var textRows = [NSView]()
    private let missingFont = NSTextField(wrappingLabelWithString: "")

    init(state: SceneEditingState) {
        self.state = state
        super.init(frame: .zero)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        let document = SceneStackView(); scroll.documentView = document; document.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        let layers = NSTextField(labelWithString: "Слои"); layers.font = .boldSystemFont(ofSize: 14)
        stack.addArrangedSubview(layers)
        let layerScroll = NSScrollView(); layerScroll.hasVerticalScroller = true
        layerScroll.borderType = .bezelBorder; layerScroll.documentView = table
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layer")); col.resizingMask = .autoresizingMask
        table.addTableColumn(col); table.headerView = nil; table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true; table.rowHeight = 23
        table.onClick = { [weak self] in self?.onFocus?() }
        table.delegate = self; table.dataSource = self; table.setAccessibilityLabel("Слои")
        stack.addArrangedSubview(layerScroll)
        selectionLabel.font = .boldSystemFont(ofSize: 14); stack.addArrangedSubview(selectionLabel)
        empty.textColor = .secondaryLabelColor; stack.addArrangedSubview(empty)
        properties.orientation = .vertical; properties.alignment = .leading; properties.spacing = 7; stack.addArrangedSubview(properties)
        addField("name", "Название"); addField("x", "X, pt"); addField("y", "Y, pt")
        addField("w", "Ширина, pt"); addField("h", "Высота, pt")
        let h = NSButton(title: "По горизонтали", target: self, action: #selector(center(_:))); h.tag = 0
        let v = NSButton(title: "По вертикали", target: self, action: #selector(center(_:))); v.tag = 1
        let centers = NSStackView(views: [h,v]); centers.spacing = 4
        [h,v].forEach { $0.controlSize = .small }; properties.addArrangedSubview(centers)
        addField("opacity", "Непрозр., %")
        addMenu("family", "Шрифт", families.map { $0 == "System" ? "Системный" : $0 })
        addMenu("weight", "Начертание", ["Сверхтонкое","Тонкое","Лёгкое","Обычное","Среднее","Полужирное","Жирное","Тяжёлое","Чёрное"])
        addField("size", "Кегль, pt", text: true); addField("line", "Интерлиньяж", text: true)
        addField("spacing", "Трекинг, %", text: true); addField("color", "Цвет, HEX", text: true)
        addMenu("align", "По ширине", ["Слева","По центру","Справа"])
        addMenu("valign", "По высоте", ["Сверху","По центру","Снизу"])
        missingFont.textColor = .secondaryLabelColor; properties.addArrangedSubview(missingFont)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            layerScroll.widthAnchor.constraint(equalTo: stack.widthAnchor), layerScroll.heightAnchor.constraint(equalToConstant: 130),
            properties.widthAnchor.constraint(equalTo: stack.widthAnchor), empty.widthAnchor.constraint(equalTo: stack.widthAnchor),
            missingFont.widthAnchor.constraint(equalTo: properties.widthAnchor)
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("layer-name")
        let label = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
        label.identifier = id; label.stringValue = rows[row].1; label.lineBreakMode = .byTruncatingTail
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncing else { return }
        state.select(Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].0 : nil }))
        onFocus?()
    }
    private func row(_ title: String, _ control: NSControl, text: Bool) {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [label,control]); stack.spacing = 5
        properties.addArrangedSubview(stack)
        stack.widthAnchor.constraint(equalTo: properties.widthAnchor).isActive = true
        label.widthAnchor.constraint(equalToConstant: 91).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(title)
        if text { textRows.append(stack) }
    }
    private func addField(_ key: String, _ title: String, text: Bool = false) {
        let f = NSTextField(); f.identifier = NSUserInterfaceItemIdentifier(key); f.delegate = self
        f.usesSingleLineMode = true; f.lineBreakMode = .byTruncatingTail
        fields[key] = f; row(title, f, text: text)
    }
    private func addMenu(_ key: String, _ title: String, _ values: [String]) {
        let p = NSPopUpButton(); p.addItem(withTitle: "Разные"); p.lastItem?.isEnabled = false
        p.addItems(withTitles: values); p.identifier = NSUserInterfaceItemIdentifier(key)
        p.target = self; p.action = #selector(menuChanged(_:)); menus[key] = p; row(title,p,text: true)
    }
    private func uniform<T: Equatable>(_ values: [T]) -> T? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }; return first
    }
    func refresh() {
        syncing = true; defer { syncing = false }
        let next = state.scene.elements.reversed().map { ($0.id, $0.name) }
        if !rows.elementsEqual(next, by: { $0.0 == $1.0 && $0.1 == $1.1 }) { rows = next; table.reloadData() }
        let indices = IndexSet(rows.indices.filter { state.selection.contains(rows[$0].0) })
        if table.selectedRowIndexes != indices { table.selectRowIndexes(indices, byExtendingSelection: false) }
        let sel = state.selected, texts = sel.filter { $0.kind == .text }
        if sel.isEmpty {
            properties.isHidden = true; empty.isHidden = false; selectionLabel.stringValue = "Композиция"
            empty.stringValue = "Основной экран · \(Int(clampingScene: state.scene.canvasSize.width)) × \(Int(clampingScene: state.scene.canvasSize.height)) pt\nВыберите слой на холсте или в списке."
            return
        }
        properties.isHidden = false; empty.isHidden = true
        selectionLabel.stringValue = sel.count == 1 ? "Свойства слоя" : "Выделено: \(sel.count)"
        textRows.forEach { $0.isHidden = texts.isEmpty }
        func number(_ x: CGFloat) -> String { String(format: "%.3f", x).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression) }
        func field(_ key: String, _ value: String?) {
            guard let f = fields[key], f.currentEditor() == nil else { return }
            f.stringValue = value ?? ""; f.placeholderString = value == nil ? "Разные" : nil
        }
        field("name", uniform(sel.map(\.name)))
        let group = sel.count > 1 ? SceneGeometry.bounds(sel) : nil
        field("x", (group?.minX ?? sel.first?.frame.minX).map(number))
        field("y", (group?.minY ?? sel.first?.frame.minY).map(number))
        field("w", uniform(sel.map { $0.frame.width }).map(number)); field("h", uniform(sel.map { $0.frame.height }).map(number))
        field("opacity", uniform(sel.map { $0.opacity*100 }).map(number))
        guard !texts.isEmpty else { missingFont.isHidden = true; return }
        field("size", uniform(texts.map { $0.style.fontSize }).map { number(CGFloat($0)) }); field("spacing", uniform(texts.map { $0.style.letterSpacing }).map { number(CGFloat($0)) })
        field("line", uniform(texts.map { $0.style.lineHeight }).map { $0 == 0 ? "Авто" : number($0) })
        field("color", uniform(texts.map { $0.style.color }).map {
            [$0.red,$0.green,$0.blue,$0.alpha].map { String(format: "%02X", Int(($0*255).rounded())) }.joined()
        })
        for (key, value) in [("family",uniform(texts.map { $0.style.family }).flatMap { families.firstIndex(of: $0) }),
                             ("weight",uniform(texts.map { $0.style.weight })), ("align",uniform(texts.map { $0.style.horizontalAlignment })),
                             ("valign",uniform(texts.map { $0.style.verticalAlignment }))] {
            menus[key]?.selectItem(at: value.map { $0+1 } ?? 0)
        }
        let unavailable = Set(texts.map { $0.style.family }.filter { !families.contains($0) })
        missingFont.isHidden = unavailable.isEmpty
        if !unavailable.isEmpty { missingFont.stringValue = "Нет шрифта \(unavailable.sorted().joined(separator: ", ")). Показан системный." }
    }
    @objc private func center(_ sender: NSButton) { state.center(horizontal: sender.tag == 0); onFocus?() }
    @objc private func menuChanged(_ p: NSPopUpButton) {
        let index = p.indexOfSelectedItem-1
        guard let key = p.identifier?.rawValue, index >= 0 else { return }
        state.editSelected { e in
            guard e.kind == .text else { return }
            switch key {
            case "family": e.style.family = families[index]
            case "weight": e.style.weight = index
            case "align": e.style.horizontalAlignment = index
            case "valign": e.style.verticalAlignment = index
            default: break
            }
            if key == "family" || key == "weight" { SceneTextLayout.fit(&e, minimumHeight: e.frame.height) }
        }
        onFocus?()
    }
    func controlTextDidChange(_ notification: Notification) { changedField = notification.object as? NSTextField }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard !syncing, let f = notification.object as? NSTextField, let key = f.identifier?.rawValue else { return }
        let returnKey = (notification.userInfo?["NSTextMovement"] as? NSNumber)?.intValue == NSTextMovement.return.rawValue
        defer { if returnKey { onFocus?() } }
        guard changedField === f else { return }; changedField = nil
        // An untouched mixed field must never broadcast its placeholder as a value.
        let raw = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { refresh(); return }
        let n = Double(raw.replacingOccurrences(of: ",", with: ".")), color = Self.parseColor(raw)
        let auto = raw.localizedCaseInsensitiveCompare("Авто") == .orderedSame
        let valid: Bool
        switch key {
        case "name": valid = true
        case "color": valid = color != nil
        case "w","h","size": valid = n.map { $0.isFinite && $0 > 0 } == true
        case "opacity": valid = n.map { (0...100).contains($0) } == true
        case "line": valid = auto || n.map { $0.isFinite && $0 >= 0 } == true
        default: valid = n?.isFinite == true
        }
        guard valid else { onError?("Проверьте значение поля «\(f.accessibilityLabel() ?? key)»."); refresh(); return }
        let group = state.selected.count > 1 ? SceneGeometry.bounds(state.selected) : nil
        state.editSelected { e in
            switch key {
            case "name": e.name = raw
            case "x": e.frame.origin.x = group.map { e.frame.origin.x + n! - $0.minX } ?? n!
            case "y": e.frame.origin.y = group.map { e.frame.origin.y + n! - $0.minY } ?? n!
            case "w","h":
                let sx = key == "w" ? n!/e.frame.width : 1, sy = key == "h" ? n!/e.frame.height : 1
                if let r = e.imageRect { e.imageRect = CGRect(x: r.minX*sx,y: r.minY*sy,width: r.width*sx,height: r.height*sy) }
                if key == "w" { e.frame.size.width = n!; if e.kind == .text { e.autoTextWidth = false } }
                else { e.frame.size.height = n! }
            case "opacity": e.opacity = n!/100
            default:
                guard e.kind == .text else { return }
                switch key {
                case "color": e.style.color = color!
                case "size": e.style.fontSize = n!
                case "spacing": e.style.letterSpacing = n!
                case "line": e.style.lineHeight = auto ? 0 : n!
                default: break
                }
                if key != "color" { SceneTextLayout.fit(&e, minimumHeight: e.frame.height) }
            }
        }

    }
    private static func parseColor(_ raw: String) -> SceneColor? {
        var s = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        if s.count == 6 { s += "FF" }
        guard s.count == 8, let value = UInt32(s, radix: 16) else { return nil }
        func channel(_ shift: Int) -> Double { Double((value >> shift) & 255)/255 }
        return SceneColor(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }
}

private extension Int {
    init(clampingScene x: CGFloat) { self = x >= CGFloat(Int.max) ? Int.max : Int(x) }
}
