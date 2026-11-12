import AppKit

struct SceneInspectorFieldPresentation {
    var text: String
    var placeholder: String?
}

struct SceneInspectorMenuPresentation {
    var items: [String]
    var selectedIndex: Int?
}

struct SceneInspectorPresentation {
    var layers: [String]
    var selectedRows: IndexSet
    var selectionTitle: String
    var emptyMessage: String?
    var showsTextControls: Bool
    var fields: [String: SceneInspectorFieldPresentation]
    var menus: [String: SceneInspectorMenuPresentation]
    var missingFontMessage: String?
    var showsNoteControls: Bool = false
    var overflowMessage: String? = nil
}

private final class SceneStackView: NSView { override var isFlipped: Bool { true } }

private final class SceneLayerTable: NSTableView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onClick?() // Also return focus when the already-selected row was clicked.
    }
}

final class SceneInspectorView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onFocus: (() -> Void)?
    var onSelectionChange: ((IndexSet) -> Void)?
    var onFieldChange: ((String, String, String) -> Void)?
    var onMenuChange: ((String, Int) -> Void)?
    var onCenter: ((Bool) -> Void)?
    private let table = SceneLayerTable(), properties = NSStackView()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "Свойства")
    private var fields = [String: NSTextField](), menus = [String: NSPopUpButton]()
    private var changedField: NSTextField?
    private var rows: [String] = [], syncing = false
    private var textRows = [NSView](), noteRows = [NSView]()
    private let overflow = NSTextField(wrappingLabelWithString: "")
    private let missingFont = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
        addMenu("family", "Шрифт")
        addMenu("weight", "Начертание")
        addField("size", "Кегль, pt", text: true); addField("line", "Строка, pt", text: true)
        addField("spacing", "Трекинг, %", text: true); addField("color", "Цвет, HEX", text: true)
        addMenu("align", "По ширине")
        addMenu("valign", "По высоте")
        addField("background", "Фон, HEX", note: true)
        addField("padding", "Отступ, pt", note: true)
        addField("radius", "Радиус, pt", note: true)
        overflow.textColor = .systemOrange; properties.addArrangedSubview(overflow)
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
            missingFont.widthAnchor.constraint(equalTo: properties.widthAnchor), overflow.widthAnchor.constraint(equalTo: properties.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("layer-name")
        let label = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
        label.identifier = id; label.stringValue = rows[row]; label.lineBreakMode = .byTruncatingTail
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncing else { return }
        onSelectionChange?(table.selectedRowIndexes)
    }
    private func row(_ title: String, _ control: NSControl, text: Bool, note: Bool = false) {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [label,control]); stack.spacing = 5
        properties.addArrangedSubview(stack)
        stack.widthAnchor.constraint(equalTo: properties.widthAnchor).isActive = true
        label.widthAnchor.constraint(equalToConstant: 91).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(title)
        if text { textRows.append(stack) }
        if note { noteRows.append(stack) }
    }
    private func addField(_ key: String, _ title: String, text: Bool = false, note: Bool = false) {
        let f = NSTextField(); f.identifier = NSUserInterfaceItemIdentifier(key); f.delegate = self
        f.usesSingleLineMode = true; f.lineBreakMode = .byTruncatingTail
        fields[key] = f; row(title, f, text: text, note: note)
    }
    private func addMenu(_ key: String, _ title: String) {
        let p = NSPopUpButton(); p.addItem(withTitle: "Разные"); p.lastItem?.isEnabled = false
        p.identifier = NSUserInterfaceItemIdentifier(key)
        p.target = self; p.action = #selector(menuChanged(_:)); menus[key] = p; row(title,p,text: true)
    }
    func render(_ presentation: SceneInspectorPresentation) {
        syncing = true; defer { syncing = false }
        if rows != presentation.layers { rows = presentation.layers; table.reloadData() }
        if table.selectedRowIndexes != presentation.selectedRows {
            table.selectRowIndexes(presentation.selectedRows, byExtendingSelection: false)
        }
        selectionLabel.stringValue = presentation.selectionTitle
        properties.isHidden = presentation.emptyMessage != nil
        empty.isHidden = presentation.emptyMessage == nil
        empty.stringValue = presentation.emptyMessage ?? ""
        textRows.forEach { $0.isHidden = !presentation.showsTextControls }
        noteRows.forEach { $0.isHidden = !presentation.showsNoteControls }
        overflow.isHidden = presentation.overflowMessage == nil
        overflow.stringValue = presentation.overflowMessage ?? ""
        for (key, value) in presentation.fields {
            // A model refresh must not replace text in the active native editor.
            guard let field = fields[key], field.currentEditor() == nil else { continue }
            field.stringValue = value.text
            field.placeholderString = value.placeholder
        }
        for (key, value) in presentation.menus {
            guard let menu = menus[key] else { continue }
            let titles = ["Разные"] + value.items
            if menu.itemTitles != titles {
                menu.removeAllItems(); menu.addItems(withTitles: titles)
                menu.item(at: 0)?.isEnabled = false
            }
            menu.selectItem(at: value.selectedIndex.map { $0 + 1 } ?? 0)
        }
        missingFont.isHidden = presentation.missingFontMessage == nil
        missingFont.stringValue = presentation.missingFontMessage ?? ""
    }
    @objc private func center(_ sender: NSButton) { onCenter?(sender.tag == 0) }
    @objc private func menuChanged(_ menu: NSPopUpButton) {
        let index = menu.indexOfSelectedItem - 1
        guard let key = menu.identifier?.rawValue, index >= 0 else { return }
        onMenuChange?(key, index)
    }
    func controlTextDidChange(_ notification: Notification) { changedField = notification.object as? NSTextField }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard !syncing, let field = notification.object as? NSTextField,
              let key = field.identifier?.rawValue else { return }
        let returnKey = (notification.userInfo?["NSTextMovement"] as? NSNumber)?.intValue == NSTextMovement.return.rawValue
        defer { if returnKey { onFocus?() } }
        // Merely visiting a mixed field must not apply its placeholder to the selection.
        guard changedField === field else { return }
        changedField = nil
        onFieldChange?(key, field.stringValue, field.accessibilityLabel() ?? key)
    }
}
