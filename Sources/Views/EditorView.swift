import AppKit

final class EditorView: NSView {
    let countdownView = CountdownView(overlay: false)
    let inspector = TypographyInspectorView()
    let eventPicker = NSPopUpButton()
    let enabledButton = NSButton(checkboxWithTitle: "Показывать при блокировке", target: nil, action: nil)
    let testButton = NSButton(title: "Проверить прозрачную панель (8 секунд)", target: nil, action: nil)
    let resetButton = NSButton(title: "Сбросить расположение", target: nil, action: nil)
    let catalogNote = NSTextField(wrappingLabelWithString: "")

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.055, alpha: 1).cgColor
        countdownView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countdownView)
        addSubview(inspector)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        let controls = NSStackView()
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controls)
        let row = NSStackView()
        row.spacing = 16
        eventPicker.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true
        row.addArrangedSubview(eventPicker)
        row.addArrangedSubview(enabledButton)
        controls.addArrangedSubview(row)
        catalogNote.font = .systemFont(ofSize: 11)
        catalogNote.textColor = .secondaryLabelColor
        catalogNote.maximumNumberOfLines = 3
        controls.addArrangedSubview(catalogNote)
        let actions = NSStackView()
        actions.spacing = 16
        actions.addArrangedSubview(testButton)
        actions.addArrangedSubview(resetButton)
        controls.addArrangedSubview(actions)
        let help = NSTextField(wrappingLabelWithString: "Перетаскивайте блоки; Shift — движение по оси. Выделяйте группу рамкой с пустого места или добавляйте блоки с Shift. Положение сохраняется автоматически.")
        help.textColor = NSColor(white: 0.75, alpha: 1)
        help.font = .systemFont(ofSize: 12)
        controls.addArrangedSubview(help)
        let convention = NSTextField(wrappingLabelWithString: "Час в источниках не задан: считаем до 00:00 по Москве. Выбор выше меняет только предпросмотр; при блокировке показывается ближайшее событие.")
        convention.textColor = NSColor(white: 0.55, alpha: 1)
        convention.font = .systemFont(ofSize: 11)
        controls.addArrangedSubview(convention)
        NSLayoutConstraint.activate([
            countdownView.topAnchor.constraint(equalTo: topAnchor),
            countdownView.leadingAnchor.constraint(equalTo: leadingAnchor),
            countdownView.trailingAnchor.constraint(equalTo: separator.leadingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.trailingAnchor.constraint(equalTo: inspector.leadingAnchor),
            inspector.trailingAnchor.constraint(equalTo: trailingAnchor),
            inspector.topAnchor.constraint(equalTo: topAnchor),
            inspector.bottomAnchor.constraint(equalTo: bottomAnchor),
            inspector.widthAnchor.constraint(equalToConstant: 332),
            countdownView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -8),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            controls.trailingAnchor.constraint(equalTo: separator.leadingAnchor, constant: -28),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
