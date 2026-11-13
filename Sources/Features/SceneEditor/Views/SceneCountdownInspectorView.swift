import AppKit

struct SceneCountdownInspectorPresentation {
    var source: Int
    var date: String
    var time: String
    var zones: [String]
    var zone: Int
    var format: Int
    var seconds: Bool
    var radius: String
    var message: String
    var occurrences: [String]
}

/// Controls forward user input; date interpretation belongs to the controller.
final class SceneCountdownInspectorView: NSStackView, NSTextFieldDelegate {
    var onBeginWallEdit: (() -> UUID?)?
    var onEndWallEdit: ((UUID, String, String, Bool) -> Void)?
    var onChoice: ((UUID, String, Int) -> Void)?
    var onRadius: ((String) -> Void)?
    private let source = NSPopUpButton(), zone = NSPopUpButton(), format = NSPopUpButton(), occurrence = NSPopUpButton()
    private let date = NSTextField(), time = NSTextField(), radius = NSTextField()
    private let seconds = NSButton(checkboxWithTitle: "Показывать секунды", target: nil, action: nil)
    private let message = NSTextField(wrappingLabelWithString: "")
    private var representedID: UUID?
    private var radiusChanged = false
    private struct WallEdit {
        let token: UUID
        let field: ObjectIdentifier
        var date: String
        var time: String
        var changed = false
    }
    private var wallEdit: WallEdit?

    init() {
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 7
        func row(_ title: String, _ control: NSControl) {
            let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 12)
            let stack = NSStackView(views: [label,control]); stack.spacing = 5; addArrangedSubview(stack)
            stack.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            label.widthAnchor.constraint(equalToConstant: 91).isActive = true
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            control.setAccessibilityLabel(title)
        }
        for (key, menu, title) in [("source",source,"Источник"),("zone",zone,"Часовой пояс"),("format",format,"Формат"),("occurrence",occurrence,"Повтор часа")] {
            menu.identifier = NSUserInterfaceItemIdentifier(key); menu.target = self; menu.action = #selector(choice(_:))
            if key != "occurrence" { row(title, menu) }
        }
        source.addItems(withTitles: ["Своя дата", "Конец света"])
        format.addItems(withTitles: ["Дни и время", "Суммарные часы", "Только дни"])
        row("Дата", date); date.placeholderString = "YYYY-MM-DD"
        row("Время", time); time.placeholderString = "HH:mm[:ss]"
        for field in [date,time,radius] { field.delegate = self; field.usesSingleLineMode = true }
        seconds.target = self; seconds.action = #selector(toggleSeconds); addArrangedSubview(seconds)
        row("Радиус, pt",radius)
        addArrangedSubview(occurrence); occurrence.setAccessibilityLabel("Повтор часа")
        message.textColor = .secondaryLabelColor; addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    /// A late native end-edit still belongs to the previously displayed layer.
    func prepare(for id: UUID?) {
        guard representedID != id else { return }
        representedID = id
        if wallEdit != nil || date.currentEditor() != nil || time.currentEditor() != nil {
            _ = window?.makeFirstResponder(nil)
        }
    }
    func render(_ p: SceneCountdownInspectorPresentation) {
        source.selectItem(at: p.source); format.selectItem(at: p.format)
        if zone.itemTitles != p.zones { zone.removeAllItems(); zone.addItems(withTitles: p.zones) }
        zone.selectItem(at: p.zone); zone.toolTip = p.zones.indices.contains(p.zone) ? p.zones[p.zone] : nil
        if date.currentEditor() == nil { date.stringValue = p.date }
        if time.currentEditor() == nil { time.stringValue = p.time }
        if radius.currentEditor() == nil { radius.stringValue = p.radius }
        date.isEnabled = p.source == 0; time.isEnabled = p.source == 0; zone.isEnabled = p.source == 0
        seconds.state = p.seconds ? .on : .off; seconds.isEnabled = p.format != 2
        let choices = ["Выберите вхождение…"] + p.occurrences
        if occurrence.itemTitles != choices { occurrence.removeAllItems(); occurrence.addItems(withTitles: choices) }
        occurrence.selectItem(at: 0); occurrence.item(at: 0)?.isEnabled = false
        occurrence.isHidden = p.occurrences.isEmpty
        renderMessage(p.message)
    }
    func renderMessage(_ value: String) { if message.stringValue != value { message.stringValue = value }; message.isHidden = value.isEmpty }
    func focusDate(custom: Bool) {
        let control: NSControl = custom ? date : source
        control.scrollToVisible(control.bounds); window?.makeFirstResponder(control)
    }
    @objc private func choice(_ sender: NSPopUpButton) {
        guard let key = sender.identifier?.rawValue else { return }
        // Ending a field may synchronously render the old selected menu value.
        let index = sender.indexOfSelectedItem - (key == "occurrence" ? 1 : 0)
        performChoice(key, index: index)
    }
    @objc private func toggleSeconds() {
        let index = seconds.state == .on ? 1 : 0
        performChoice("seconds", index: index)
    }
    private func performChoice(_ key: String, index: Int) {
        guard let id = representedID else { return }
        // Complete text in its original editing context before changing its zone.
        guard window?.makeFirstResponder(nil) ?? true else { return }
        onChoice?(id, key, index)
    }
    private func beginWallEdit(_ field: NSTextField) {
        guard field === date || field === time, wallEdit == nil,
              let token = onBeginWallEdit?() else { return }
        wallEdit = WallEdit(token: token, field: ObjectIdentifier(field), date: date.stringValue, time: time.stringValue)
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
        if let field = notification.object as? NSTextField { beginWallEdit(field) }
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === radius { radiusChanged = true; return }
        beginWallEdit(field)
        guard wallEdit?.field == ObjectIdentifier(field) else { return }
        let text = field.currentEditor()?.string ?? field.stringValue
        if field === date { wallEdit?.date = text } else { wallEdit?.time = text }
        wallEdit?.changed = true
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === radius {
            guard radiusChanged else { return }
            radiusChanged = false; onRadius?(field.stringValue); return
        }
        guard var edit = wallEdit, edit.field == ObjectIdentifier(field) else { return }
        // Use the native final value for this field and the original paired field.
        if field === date { edit.date = field.stringValue } else { edit.time = field.stringValue }
        let cancelled = (notification.userInfo?["NSTextMovement"] as? NSNumber)?.intValue == NSTextMovement.cancel.rawValue
        wallEdit = nil // Clear before reentrant state refresh or a duplicate end notification.
        onEndWallEdit?(edit.token, edit.date, edit.time, edit.changed && !cancelled)
    }
}
