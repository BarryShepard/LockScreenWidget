import AppKit

struct SceneClockInspectorPresentation {
    var zones: [String]
    var zone: Int
    var seconds: Bool
    var uses24Hour: Bool
}

final class SceneClockInspectorView: NSStackView {
    var onChoice: ((String, Int) -> Void)?
    var onOpenSystemSettings: (() -> Void)?
    private let zone = NSPopUpButton()
    private let seconds = NSButton(checkboxWithTitle: "Показывать секунды", target: nil, action: nil)
    private let hours = NSButton(checkboxWithTitle: "24-часовой формат", target: nil, action: nil)
    private var zoneNames: [String] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .vertical; alignment = .leading; spacing = 7
        let label = NSTextField(labelWithString: "Часовой пояс часов")
        label.font = .systemFont(ofSize: 12)
        zone.setAccessibilityLabel("Часовой пояс часов")
        zone.identifier = .init("clock-zone")
        seconds.identifier = .init("clock-seconds"); hours.identifier = .init("clock-24hour")
        zone.target = self; zone.action = #selector(zoneChanged)
        seconds.target = self; seconds.action = #selector(secondsChanged)
        hours.target = self; hours.action = #selector(hoursChanged)
        let help = NSTextField(wrappingLabelWithString: "Системные часы скрываются в настройках macOS: «Показывать большие часы» → «Никогда».")
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor
        let settings = NSButton(title: "Настройки системных часов…", target: self, action: #selector(openSettings))
        settings.controlSize = .small
        [label, zone, seconds, hours, help, settings].forEach { addArrangedSubview($0) }
        zone.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        help.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func render(_ value: SceneClockInspectorPresentation) {
        if zoneNames != value.zones {
            zoneNames = value.zones; zone.removeAllItems(); zone.addItems(withTitles: zoneNames)
        }
        zone.selectItem(at: value.zone)
        seconds.state = value.seconds ? .on : .off
        hours.state = value.uses24Hour ? .on : .off
    }
    func focus() { window?.makeFirstResponder(zone) }
    @objc private func zoneChanged() { onChoice?("zone", zone.indexOfSelectedItem) }
    @objc private func secondsChanged() { onChoice?("seconds", seconds.state == .on ? 1 : 0) }
    @objc private func hoursChanged() { onChoice?("hours", hours.state == .on ? 1 : 0) }
    @objc private func openSettings() { onOpenSystemSettings?() }
}
