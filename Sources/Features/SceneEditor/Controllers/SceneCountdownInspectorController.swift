import AppKit

final class SceneCountdownInspectorController {
    private let state: SceneEditingStateModel
    private let view: SceneCountdownInspectorView
    private let catalog: EventCatalogModel
    private var now: Date
    private let zones = Array(Set(TimeZone.knownTimeZoneIdentifiers + [TimeZone.current.identifier, "UTC"])).sorted()
    private var identity: (id: UUID, target: Date, zone: String, source: SceneCountdownSource)?
    private struct WallEditContext {
        let token: UUID
        let id: UUID
        let timer: SceneCountdownModel
    }
    private var activeWallEdit: WallEditContext?
    private var blockedChoice = false
    private var draft: (date: String, time: String, resolution: SceneWallTimeResolution)?

    init(state: SceneEditingStateModel, view: SceneCountdownInspectorView, catalog: EventCatalogModel, now: Date) {
        self.state = state; self.view = view; self.catalog = catalog; self.now = now
        view.onBeginWallEdit = { [weak self] in self?.beginWallEdit() }
        view.onEndWallEdit = { [weak self] token, date, time, changed in
            self?.endWallEdit(token: token, date: date, time: time, changed: changed)
        }
        view.onChoice = { [weak self] id, key, index in
            guard let self else { return }
            guard self.selected?.id == id else { self.refresh(); return }
            self.choose(key: key, index: index)
        }
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
        guard let element = selected, let timer = element.countdown else { identity = nil; draft = nil; blockedChoice = false; return }
        if identity?.id != element.id || identity?.target != timer.targetDate || identity?.zone != timer.timeZoneID || identity?.source != timer.source {
            draft = nil; blockedChoice = false
        }
        identity = (element.id, timer.targetDate, timer.timeZoneID, timer.source)
    }
    func refresh() {
        view.prepare(for: selected?.id)
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
            case .invalid: return (blockedChoice ? "Сначала исправьте дату и время перед сменой источника или пояса.\n" : "") + "Проверьте YYYY-MM-DD (1583–9999) и HH:mm[:ss]. Несуществующее местное время нельзя сохранить."
            case .ambiguous: return (blockedChoice ? "Сначала уточните время перед сменой источника или пояса.\n" : "") + "Это время встречается дважды. Выберите первое или второе вхождение."
            case .unique: break
            }
        }
        if SceneCountdownPresentationController.wallFields(timer.targetDate, zone: timer.timeZoneID) == nil {
            return "Дата вне диапазона редактора (1583–9999). Введите новую дату."
        }
        return "Дата и время в выбранном часовом поясе."
    }
    /// Tick updates only a label, never popups, field editors, selection or history.
    func refresh(at now: Date) {
        self.now = now
        if let timer = selected?.countdown, timer.source == .apocalypse { view.renderMessage(message(timer)) }
    }
    func focus() { view.focusDate(custom: selected?.countdown?.source == .custom) }

    private func beginWallEdit() -> UUID? {
        guard let element = selected, let timer = element.countdown, timer.source == .custom else { return nil }
        let context = WallEditContext(token: UUID(), id: element.id, timer: timer)
        activeWallEdit = context
        return context.token
    }
    private func endWallEdit(token: UUID, date: String, time: String, changed: Bool) {
        guard let context = activeWallEdit, context.token == token else { return }
        activeWallEdit = nil
        guard changed else { return }
        // Selection may already have changed. Never reinterpret text in the new
        // layer/zone, or overwrite a target changed by Undo or another action.
        guard let current = state.scene.elements.first(where: { $0.id == context.id })?.countdown,
              current.source == context.timer.source, current.timeZoneID == context.timer.timeZoneID,
              current.targetDate == context.timer.targetDate else { return }
        applyWall(date: date, time: time, to: context.id, zone: context.timer.timeZoneID)
    }
    func editWall(date: String, time: String) {
        synchronize()
        guard let element = selected, let timer = element.countdown, timer.source == .custom else { return }
        applyWall(date: date, time: time, to: element.id, zone: timer.timeZoneID)
    }
    private func applyWall(date: String, time: String, to id: UUID, zone: String) {
        let result = SceneCountdownPresentationController.resolve(date: date, time: time, zone: zone)
        blockedChoice = false
        if selected?.id == id { draft = (date,time,result) }
        if case let .unique(target) = result { commit(target, to: id) }
        refresh()
    }
    private func commit(_ target: Date, to id: UUID) {
        if selected?.id == id { draft = nil; blockedChoice = false }
        state.change { snapshot in
            guard let index = snapshot.scene.elements.firstIndex(where: { $0.id == id }) else { return }
            snapshot.scene.elements[index].countdown?.targetDate = target
        }
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
        if key == "source" || key == "zone" {
            // Changing interpretation of an unresolved wall time is never implicit.
            if draft != nil {
                blockedChoice = true; refresh(); return
            }
            draft = nil; blockedChoice = false
        }
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
