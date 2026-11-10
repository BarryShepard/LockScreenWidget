import AppKit

final class TypographyInspectorView: NSView {
    let block = NSPopUpButton()
    let family = NSPopUpButton()
    let weight = NSPopUpButton()
    let size = NSTextField()
    let lineHeight = NSTextField()
    let spacing = NSTextField()
    let horizontal = NSSegmentedControl(labels: ["Слева", "Центр", "Справа"], trackingMode: .selectOne, target: nil, action: nil)
    let vertical = NSSegmentedControl(labels: ["Сверху", "Центр", "Снизу"], trackingMode: .selectOne, target: nil, action: nil)
    let information = NSButton(checkboxWithTitle: "Дополнительная информация", target: nil, action: nil)
    let selectionLabel = NSTextField(wrappingLabelWithString: "Выберите блок на холсте")
    private(set) var centerButtons: [NSButton] = []

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1).cgColor
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
        ])
        let heading = NSTextField(labelWithString: "Типографика")
        heading.font = .systemFont(ofSize: 19, weight: .semibold)
        content.addArrangedSubview(heading)
        selectionLabel.font = .systemFont(ofSize: 11)
        selectionLabel.textColor = .secondaryLabelColor
        content.addArrangedSubview(selectionLabel)
        block.addItems(withTitles: ["Причина", "Таймер", "Доп. информация"])
        add(block, to: content)
        label("Шрифт", in: content)
        family.addItem(withTitle: "Системный San Francisco")
        family.lastItem?.representedObject = "System"
        for name in NSFontManager.shared.availableFontFamilies.sorted() {
            family.addItem(withTitle: name)
            family.lastItem?.representedObject = name
        }
        family.tag = 0
        add(family, to: content)
        label("Начертание и кегль (pt)", in: content)
        weight.addItems(withTitles: ["Ultra Light", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"])
        weight.tag = 1
        configure(size, tag: 2, placeholder: "26")
        let fontRow = NSStackView(views: [weight, size])
        fontRow.spacing = 8
        weight.widthAnchor.constraint(equalToConstant: 165).isActive = true
        add(fontRow, to: content)
        label("Высота строки (pt) / Интервал (%)", in: content)
        configure(lineHeight, tag: 3, placeholder: "Авто")
        configure(spacing, tag: 4, placeholder: "0")
        let spacingRow = NSStackView(views: [lineHeight, spacing])
        spacingRow.distribution = .fillEqually
        spacingRow.spacing = 8
        add(spacingRow, to: content)
        label("Выравнивание текста", in: content)
        horizontal.tag = 5
        horizontal.segmentDistribution = .fillEqually
        add(horizontal, to: content)
        vertical.tag = 6
        vertical.segmentDistribution = .fillEqually
        add(vertical, to: content)
        let divider = NSBox()
        divider.boxType = .separator
        add(divider, to: content)
        label("Расположение на холсте", in: content)
        for (index, title) in ["По горизонтальному центру", "По вертикальному центру"].enumerated() {
            let button = NSButton(title: title, target: nil, action: nil)
            button.tag = index
            centerButtons.append(button)
            add(button, to: content)
        }
        add(information, to: content)
        let hint = NSTextField(wrappingLabelWithString: "Стрелки — сдвиг на 1 pt, Shift + стрелки — на 10 pt. Рамка выделяет группу; Shift при перетаскивании фиксирует ось.\n\nИзменения сохраняются автоматически.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        add(hint, to: content)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, in stack: NSStackView) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
    }
    private func add(_ view: NSView, to stack: NSStackView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func configure(_ field: NSTextField, tag: Int, placeholder: String) {
        field.tag = tag
        field.placeholderString = placeholder
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    }

    func render(settings: EditorSettingsModel, selectedIndices indices: Set<Int>) {
        let index = indices.min() ?? block.indexOfSelectedItem
        if visibleBlockIndices(in: settings).contains(index) { block.selectItem(at: index) }
        else { block.selectItem(at: 0) }
        block.item(at: 2)?.isEnabled = settings.showInformation
        information.state = settings.showInformation ? .on : .off
        selectionLabel.stringValue = indices.isEmpty ? "Выберите блок на холсте" :
            (indices.count == 1 ? "Настройки выбранного блока" : "Выбрано блоков: \(indices.count). Меняется только выбранное свойство.")
        let style = settings.typography[block.indexOfSelectedItem]
        let familyIndex = family.itemArray.firstIndex { ($0.representedObject as? String) == style.family } ?? 0
        family.selectItem(at: familyIndex)
        weight.selectItem(at: style.weight)
        size.stringValue = number(style.size)
        lineHeight.stringValue = style.lineHeight == 0 ? "" : number(style.lineHeight)
        spacing.stringValue = number(style.spacing)
        horizontal.selectedSegment = style.alignment
        vertical.selectedSegment = style.verticalAlignment
        for control: NSControl in [family, weight, size, lineHeight, spacing, horizontal, vertical] { control.isEnabled = !indices.isEmpty }
        centerButtons.forEach { $0.isEnabled = !indices.isEmpty }
    }

    private func number(_ value: Double) -> String { String(format: "%g", value) }
}
