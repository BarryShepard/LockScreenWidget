import AppKit

final class SceneCountdownInspectorController {
    private let state: SceneEditingStateModel
    private let view: SceneCountdownInspectorView
    private let catalog: EventCatalogModel
    private var now: Date
    private let zones = Array(Set(TimeZone.knownTimeZoneIdentifiers + [TimeZone.current.identifier, "UTC"])).sorted()
    private var identity: (id: UUID, target: Date, zone: String, source: SceneCountdownSource)?
    private var draft: (date: String, time: String, resolution: SceneWallTimeResolution)?

    init(state: SceneEditingStateModel, view: SceneCountdownInspectorView, catalog: EventCatalogModel, now: Date) {
        self.state = state; self.view = view; self.catalog = catalog; self.now = now
        view.onWallEdit = { [weak self] date, time in self?.editWall(date: date, time: time) }
        view.onChoice = { [weak self] key, index in self?.choose(key: key, index: index) }
        view.onRadius = { [weak self] value in
            guard let self, let radius = Double(value), radius.isFinite, radius >= 0 else { return }
            self.state.editSelected { if $0.kind == .countdown { $0.cornerRadius = radius } }
        }
    }
    private var selected: SceneElementModel? {
        guard state.selected.count == 1, let element = state.selected.first, element.kind == .countdown else { return nil }
        return element
    }
    private func synchronize() {
        guard let element = selected, let timer = element.countdown else { identity = nil; draft = nil; return }
        if identity?.id != element.id || identity?.target != timer.targetDate || identity?.zone != timer.timeZoneID || identity?.source != timer.source {
            draft = nil
        }
        identity = (element.id, timer.targetDate, timer.timeZoneID, timer.source)
    }
    func refresh() {
        synchronize()
        view.isHidden = selected == nil
        guard let element = selected, let timer = element.countdown else { return }
        let wall = SceneCountdownPresentationController.wallFields(timer.targetDate, zone: timer.timeZoneID)
        let availableZones = zones.contains(timer.timeZoneID) ? zones : (zones + [timer.timeZoneID]).sorted()
        var occurrences: [String] = []
        if case let .ambiguous(first,last)? = draft?.resolution {
            func label(_ value: Date) -> String {
                let offset = TimeZone(identifier: timer.timeZoneID)!.secondsFromGMT(for: value)
                return String(format: "UTC%@%02d:%02d", offset < 0 ? "−" : "+", abs(offset)/3600, abs(offset)%3600/60)
            }
            occurrences = ["Первое (\(label(first)))", "Второе (\(label(last)))"]
        }
        view.render(.init(source: timer.source == .custom ? 0 : 1, date: draft?.date ?? wall?.date ?? "",
            time: draft?.time ?? wall?.time ?? "", zones: availableZones, zone: availableZones.firstIndex(of: timer.timeZoneID)!,
            format: [.daysAndTime, .totalHours, .days].firstIndex(of: timer.format)!, seconds: timer.showsSeconds,
            radius: String(format: "%g", element.cornerRadius), message: message(timer), occurrences: occurrences))
    }
    private func message(_ timer: SceneCountdownModel) -> String {
        if timer.source == .apocalypse {
            guard let event = SceneCountdownPresentationController.nextEvent(in: catalog, at: now) else {
                return "Будущих проверенных событий с точной датой нет. Показан ноль. Даты каталога: полночь, Europe/Moscow."
            }
            return "\(event.title)\n\(event.date) · 00:00 Europe/Moscow\n\(event.source)"
        }
        if let draft {
            switch draft.resolution {
            case .invalid: return "Проверьте YYYY-MM-DD и HH:mm[:ss]. Несуществующее местное время нельзя сохранить."
            case .ambiguous: return "Это время встречается дважды. Выберите первое или второе вхождение."
            case .unique: break
            }
        }
        if SceneCountdownPresentationController.wallFields(timer.targetDate, zone: timer.timeZoneID) == nil {
            return "Дата вне диапазона редактора (0001–9999). Введите новую дату."
        }
        return "Дата и время в выбранном часовом поясе."
    }
    /// Tick updates only a label, never popups, field editors, selection or history.
    func refresh(at now: Date) {
        self.now = now
        if let timer = selected?.countdown, timer.source == .apocalypse { view.renderMessage(message(timer)) }
    }
    func focus() { view.focusDate(custom: selected?.countdown?.source == .custom) }

    func editWall(date: String, time: String) {
        synchronize()
        guard let element = selected, let timer = element.countdown, timer.source == .custom else { return }
        let result = SceneCountdownPresentationController.resolve(date: date, time: time, zone: timer.timeZoneID)
        draft = (date,time,result)
        if case let .unique(target) = result { commit(target, to: element.id) }
        refresh()
    }
    private func commit(_ target: Date, to id: UUID) {
        draft = nil
        state.editSelected { if $0.id == id { $0.countdown?.targetDate = target } }
    }
    func choose(key: String, index: Int) {
        // Invalidate stale ambiguous candidates before interpreting a delayed action.
        synchronize()
        guard let element = selected, let timer = element.countdown else { return }
        if key == "occurrence" {
            guard timer.source == .custom, identity?.id == element.id,
                  case let .ambiguous(first,last)? = draft?.resolution, (0...1).contains(index) else { return }
            commit(index == 0 ? first : last, to: element.id); refresh(); return
        }
        let availableZones = zones.contains(timer.timeZoneID) ? zones : (zones + [timer.timeZoneID]).sorted()
        guard (key == "source" && (0...1).contains(index)) || (key == "zone" && availableZones.indices.contains(index)) ||
                (key == "format" && (0...2).contains(index)) || (key == "seconds" && (0...1).contains(index)) else { return }
        if key == "source" || key == "zone" { draft = nil }
        state.editSelected { e in
            guard e.id == element.id, var value = e.countdown else { return }
            switch key {
            case "source": value.source = index == 0 ? .custom : .apocalypse
            case "zone": value.timeZoneID = availableZones[index] // Preserve the absolute instant.
            case "format": value.format = [.daysAndTime,.totalHours,.days][index]
            case "seconds": value.showsSeconds = index == 1
            default: break
            }
            e.countdown = value
        }
        refresh()
    }
}
