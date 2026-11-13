import AppKit

final class SceneClockInspectorController {
    private let state: SceneEditingStateModel
    private let view: SceneClockInspectorView
    private let zones = TimeZone.knownTimeZoneIdentifiers.sorted()
    private var displayedZones: [String] = []
    init(state: SceneEditingStateModel, view: SceneClockInspectorView) {
        self.state = state; self.view = view
        view.onChoice = { [weak self] key, index in self?.choose(key, index: index) }
        view.onOpenSystemSettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    private var selected: SceneElementModel? {
        guard state.selected.count == 1, let item = state.selected.first, item.kind == .clock else { return nil }
        return item
    }
    func refresh() {
        view.isHidden = selected == nil
        guard let clock = selected?.clock else { return }
        displayedZones = zones
        if let zone = clock.timeZoneID, !displayedZones.contains(zone) { displayedZones.append(zone); displayedZones.sort() }
        view.render(.init(zones: ["Системный"] + displayedZones,
            zone: clock.timeZoneID.flatMap { displayedZones.firstIndex(of: $0).map { $0+1 } } ?? 0,
            seconds: clock.showsSeconds, uses24Hour: clock.uses24Hour))
    }
    func focus() { view.focus() }
    private func choose(_ key: String, index: Int) {
        guard selected != nil else { return }
        state.editSelected { element in
            guard var clock = element.clock else { return }
            switch key {
            case "zone":
                guard index == 0 || displayedZones.indices.contains(index-1) else { return }
                clock.timeZoneID = index == 0 ? nil : displayedZones[index-1]
            case "seconds": clock.showsSeconds = index == 1
            case "hours": clock.uses24Hour = index == 1
            default: return
            }
            element.clock = clock
        }
    }
}
