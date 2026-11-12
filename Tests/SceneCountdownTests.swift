import AppKit

@main struct SceneCountdownTests {
    static func check(_ value: Bool, _ message: String) { precondition(value, message) }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func main() throws {
        _ = NSApplication.shared
        let now = date("2026-11-12T12:00:00Z")
        var timer = SceneCountdownModel(targetDate: now.addingTimeInterval(1_047_845), timeZoneID: "Europe/Moscow")
        check(SceneCountdownPresentationController.value(timer, catalog: .init(), at: now) == "12 дней 03:04:05", "Days and time")
        timer.format = .totalHours
        check(SceneCountdownPresentationController.value(timer, catalog: .init(), at: now) == "291:04:05", "Total hours do not wrap at 24")
        timer.showsSeconds = false
        check(SceneCountdownPresentationController.value(timer, catalog: .init(), at: now) == "291:04", "Seconds hidden")
        check(SceneCountdownPresentationController.value(timer, catalog: .init(), at: now.addingTimeInterval(1)) == "291:04", "Minute format stable within minute")
        timer.format = .days
        check(SceneCountdownPresentationController.value(timer, catalog: .init(), at: now) == "12 дней", "Full days only")
        for (count, word) in [(0,"дней"),(1,"день"),(2,"дня"),(4,"дня"),(11,"дней"),(21,"день"),(22,"дня"),(111,"дней")] {
            check(SceneCountdownPresentationController.days(count) == "\(count) \(word)", "Russian plural \(count)")
        }
        timer.targetDate = now.addingTimeInterval(-1)
        check(SceneCountdownPresentationController.value(timer, catalog: .init(), at: now) == "0 дней", "Expired stays zero")
        timer.targetDate = Date(timeIntervalSinceReferenceDate: 1e300)
        check(!SceneCountdownPresentationController.value(timer, catalog: .init(), at: now).isEmpty, "Extreme finite date is safe")
        var fractional = SceneCountdownModel(targetDate: now.addingTimeInterval(0.5), timeZoneID: "UTC", format: .totalHours)
        check(SceneCountdownPresentationController.value(fractional, catalog: .init(), at: now) == "00:00:01", "Future subsecond is not expired")
        check(SceneCountdownPresentationController.value(fractional, catalog: .init(), at: now.addingTimeInterval(0.5)) == "00:00:00", "Exact expiry is zero")
        fractional.showsSeconds = false; fractional.targetDate = now.addingTimeInterval(60.5)
        check(SceneCountdownPresentationController.value(fractional, catalog: .init(), at: now) == "00:01", "Hidden seconds floor whole minutes")
        check(SceneCountdownPresentationController.value(fractional, catalog: .init(), at: now.addingTimeInterval(1)) == "00:00", "Hidden minute boundary")
        check(SceneCountdownPresentationController.wallFields(timer.targetDate,zone:"UTC") == nil, "Extreme target never enters Calendar conversion")
        wallTimes()
        try modelAndCatalog(now)
        try integration(now)
        inspector(now)
        print("Scene countdown tests passed")
    }
    static func wallTimes() {
        let helper = SceneCountdownPresentationController.self
        check(helper.resolve(date: "2025-02-29", time: "12:00", zone: "UTC") == .invalid, "Impossible date")
        check(helper.resolve(date: "2024-03-10", time: "02:30", zone: "America/New_York") == .invalid, "Spring DST gap must not normalize")
        check(helper.resolve(date: "2024-11-03", time: "01:30", zone: "America/New_York") == .ambiguous(date("2024-11-03T05:30:00Z"), date("2024-11-03T06:30:00Z")), "Actual Foundation repeated wall time")
        check(helper.resolve(date: "2024-11-03", time: "03:30:45", zone: "America/New_York") == .unique(date("2024-11-03T08:30:45Z")), "Normal wall time")
        for bad in ["2024-1-01", "0000-01-01", "10000-01-01", "2024-02-30"] {
            check(helper.resolve(date: bad, time: "00:00", zone: "UTC") == .invalid, "Strict date \(bad)")
        }
        for bad in ["24:00", "12:60", "12:00:60", "1:00", "12:00 "] {
            check(helper.resolve(date: "2024-01-01", time: bad, zone: "UTC") == .invalid, "Strict time \(bad)")
        }
        check(helper.resolve(date: "2024-10-06", time: "02:15", zone: "Australia/Lord_Howe") == .invalid, "Half-hour DST gap")
        check(helper.resolve(date: "2024-04-07", time: "01:45", zone: "Australia/Lord_Howe") == .ambiguous(date("2024-04-06T14:45:00Z"),date("2024-04-06T15:15:00Z")), "Half-hour repeated time")
        check(helper.resolve(date: "0001-01-01", time: "00:00", zone: "UTC") != .invalid, "Year 1 accepted")
        check(helper.resolve(date: "9999-12-31", time: "23:59:59", zone: "UTC") != .invalid, "Year 9999 accepted")
    }
    static func event(_ id: String, _ day: String, enabled: Bool? = nil, review: String? = nil) -> ApocalypseEventModel {
        .init(id: id, date: day, title: "Event " + id, explanation: "Details", source: "Local source", sourceURL: URL(string: "https://example.org")!, dateLabel: nil, countdownEnabled: enabled, reviewStatus: review, reviewNote: nil, caveat: nil, researchTitle: nil, researchNumber: nil)
    }
    static func modelAndCatalog(_ now: Date) throws {
        var e = SceneElementModel(kind: .countdown, frame: CGRect(x: 0,y: 0,width: 320,height: 80))
        e.countdown = .init(targetDate: now, timeZoneID: "UTC")
        var scene = EditorSceneModel(canvasSize: CGSize(width: 800,height: 500), elements: [e])
        check(try JSONDecoder().decode(EditorSceneModel.self, from: JSONEncoder().encode(scene)) == scene, "Countdown options round trip")
        check(!e.kind.hasEditableText && e.kind.hasTypography && !e.kind.isImage, "Countdown capabilities")
        for zone in ["", "Unknown/Timezone"] {
            scene.elements[0].countdown?.timeZoneID = zone
            do { _ = try scene.validated(); preconditionFailure("Invalid zone accepted") } catch { }
        }
        scene.elements[0] = e; scene.elements[0].countdown?.targetDate = Date(timeIntervalSinceReferenceDate: .infinity)
        do { _ = try scene.validated(); preconditionFailure("Infinite target accepted") } catch { }
        scene.elements[0].countdown = nil
        do { _ = try scene.validated(); preconditionFailure("Missing countdown payload accepted") } catch { }
        let old = EditorSceneModel(canvasSize: scene.canvasSize, elements: [SceneElementModel(kind: .text, frame: e.frame)])
        let oldData = try JSONEncoder().encode(old)
        check(!String(decoding: oldData, as: UTF8.self).contains("countdown"), "Old schema has no countdown payload")
        check(try JSONDecoder().decode(EditorSceneModel.self, from: oldData) == old, "Schema 1 old scene still decodes")
        let catalog = EventCatalogModel(events: [event("late","2026-11-14",review:"reported_secondary"),event("disabled","2026-11-12",enabled:false),event("first","2026-11-13"),event("range","2026–2027",enabled:false)])
        let helper = SceneCountdownPresentationController.self
        check(helper.nextEvent(in: catalog, at: now)?.id == "first", "Legacy nil reviewStatus retains approved countdown")
        check(helper.nextEvent(in: catalog, at: date("2026-11-12T21:00:00Z"))?.id == "late", "Preset advances exactly at Moscow midnight")
        check(helper.nextEvent(in: catalog, at: date("2026-11-13T21:00:00Z")) == nil, "Preset exhausted at final deadline")
        var preset = e.countdown!; preset.source = .apocalypse
        check(helper.value(preset,catalog:catalog,at:date("2026-11-13T21:00:00Z")) == "0 дней 00:00:00", "Exhausted preset zero")
        if CommandLine.arguments.count > 1 {
            let real = try loadEventCatalog(URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Resources/events.json"))
            check(helper.nextEvent(in: real, at: now)?.id == selectNextEvent(in: real, now: now)?.id, "Real catalog preserves previous nearest event")
            check(helper.nextEvent(in: real, at: now)?.id == "foerster-2026-11-13", "Original nearest event remains available")
        }
        let duplicate = SceneEditingStateModel.inserting([e], into: SceneSnapshot(scene: old, selection: []), offset: 0)
        check(duplicate.scene.elements.last?.countdown == e.countdown, "Duplicate preserves countdown payload")
    }
    static func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
    static func integration(_ now: Date) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("countdown-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        let state = SceneEditingStateModel(EditorSceneModel(canvasSize: CGSize(width: 800,height: 500)))
        let canvas = SceneCanvasController(state: state,store: store,now: now)
        var focuses = 0; canvas.onEditCountdown = { focuses += 1 }
        canvas.createCenteredCountdown()
        check(state.selected.count == 1 && state.scene.elements[0].frame.size == CGSize(width: 320,height: 80), "Default timer frame")
        check(state.scene.elements[0].countdown?.targetDate == now.addingTimeInterval(86400) && focuses == 1, "Default 24h and date control focus")
        let scene = state.scene
        state.undo(); check(state.scene.elements.isEmpty, "Add timer has one undo")
        state.redo(); check(state.scene == scene, "Redo restores timer")
        var updates = 0; state.onUpdate = { _ in updates += 1 }
        let presenter = ScenePresentationController(store: store), overlay = ScenePresentationController(store: store)
        let first = presenter.content(for: scene,at: now)
        check(first == overlay.content(for: scene,at: now), "Editor and overlay resolve shared instant identically")
        check(first != presenter.content(for: scene,at: now.addingTimeInterval(1)), "Visible seconds change")
        var minute = scene; minute.elements[0].countdown?.showsSeconds = false
        minute.elements[0].countdown?.targetDate = now.addingTimeInterval(86430)
        let minuteStart = presenter.content(for: minute,at: now)
        check(minuteStart == presenter.content(for: minute,at: now.addingTimeInterval(1)), "Minute render cache uses values")
        check(minuteStart != presenter.content(for: minute,at: now.addingTimeInterval(31)), "Minute changes at boundary")
        minute.elements[0].countdown?.format = .days
        let dayStart = presenter.content(for: minute,at: now)
        check(dayStart == presenter.content(for: minute,at: now.addingTimeInterval(1)), "Day render stable")
        check(dayStart != presenter.content(for: minute,at: now.addingTimeInterval(31)), "Day boundary changes")
        let slept = now.addingTimeInterval(86401)
        canvas.refresh(at: slept)
        check(updates == 0 && state.scene == scene, "Wake tick never mutates scene or history")
        let expired = presenter.content(for: scene,at: slept)
        check(expired == ScenePresentationController(store: store).content(for: scene,at: slept), "Relaunched presentation recomputes actual remaining time")
        check(expired == presenter.content(for: scene,at: slept.addingTimeInterval(5)), "Expired rendering remains stable")
        try store.save(scene)
        let file = directory.appendingPathComponent("scene.json")
        let before = try Data(contentsOf: file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let window = SceneEditorWindowController(scene: scene,hasSavedScene: true,store: store,now: now)
        var published = 0; window.onSceneChange = { _ in published += 1 }
        for tick in 1...5 { window.refresh(at: now.addingTimeInterval(Double(tick))) }
        window.refresh(at: slept); window.flush()
        check(published == 0 && !window.canUndo && window.scene == scene, "Editor tick does not publish or add Undo")
        check(try Data(contentsOf: file) == before, "Ticks do not save bytes")
        check((try FileManager.default.attributesOfItem(atPath:file.path))[.modificationDate] as? Date == attributes[.modificationDate] as? Date, "Ticks do not rewrite identical file")
        window.close()
        let inspectorView = SceneInspectorView(frame: .zero)
        let inspector = SceneInspectorController(state: state,view: inspectorView)
        let originalFrame = state.scene.elements[0].frame
        inspector.applyField(key:"size",raw:"58",label:"Size")
        inspector.applyMenu(key:"weight",index:6)
        check(state.scene.elements[0].frame == originalFrame && state.scene.elements[0].style.fontSize == 58, "Timer typography never fits empty persisted text")
    }
    static func inspector(_ now: Date) {
        var e = SceneElementModel(kind:.countdown, frame:CGRect(x:0,y:0,width:320,height:80))
        e.countdown = .init(targetDate:now,timeZoneID:"America/New_York")
        var other = e; other.id = UUID()
        let state = SceneEditingStateModel(EditorSceneModel(canvasSize:CGSize(width:800,height:500),elements:[e,other]))
        state.select([e.id])
        let view = SceneCountdownInspectorView()
        let controller = SceneCountdownInspectorController(state:state,view:view,catalog:.init(),now:now)
        var commits = 0
        state.onUpdate = { update in if case .committed = update { commits += 1 }; controller.refresh() }
        controller.refresh()
        let fields = descendants(view).compactMap { $0 as? NSTextField }
        let dateField = fields.first { $0.accessibilityLabel() == "Дата" }!
        let timeField = fields.first { $0.accessibilityLabel() == "Время" }!
        let menus = descendants(view).compactMap { $0 as? NSPopUpButton }
        let zoneMenu = menus.first { $0.identifier?.rawValue == "zone" }!
        let firstZoneItem = zoneMenu.item(at:0)!
        dateField.stringValue = "2024-11-"; timeField.stringValue = "01:"
        for tick in 1...3 { controller.refresh(at:now.addingTimeInterval(Double(tick))) }
        check(dateField.stringValue == "2024-11-" && timeField.stringValue == "01:" && zoneMenu.item(at:0) === firstZoneItem, "Ticks preserve partial native input and menu item identity")
        controller.editWall(date:"2024-03-10",time:"02:30")
        check(state.scene.elements[0].countdown == e.countdown && commits == 0, "Nonexistent time is inline only")
        controller.editWall(date:"2024-11-03",time:"01:30")
        let occurrence = menus.first { $0.identifier?.rawValue == "occurrence" }!
        check(!occurrence.isHidden && commits == 0, "Ambiguous wall time waits for explicit choice")
        controller.choose(key:"occurrence",index:1)
        check(state.scene.elements[0].countdown?.targetDate == date("2024-11-03T06:30:00Z") && commits == 1, "Second occurrence commits once")
        state.undo(); check(state.scene.elements[0] == e, "Wall time undo restores deadline")
        controller.editWall(date:"2024-11-03",time:"01:30")
        state.select([other.id]); let otherBefore = state.scene.elements[1]
        controller.choose(key:"occurrence",index:0)
        check(state.scene.elements[1] == otherBefore, "Stale ambiguous choice cannot edit another layer")
        state.select([e.id]); controller.editWall(date:"2024-11-03",time:"01:30")
        controller.choose(key:"occurrence",index:0)
        check(state.scene.elements[0].countdown?.targetDate == date("2024-11-03T05:30:00Z"), "First occurrence explicit choice")
        let target = state.scene.elements[0].countdown!.targetDate
        let utcIndex = zoneMenu.itemTitles.firstIndex(of:"UTC")!
        controller.choose(key:"zone",index:utcIndex)
        check(state.scene.elements[0].countdown?.targetDate == target && timeField.stringValue == "05:30:00", "Timezone change preserves instant and recomputes wall time")
        controller.editWall(date:"2024-11-03",time:"07:20:15")
        let custom = state.scene.elements[0].countdown!
        check(custom.targetDate == date("2024-11-03T07:20:15Z"), "Manual wall edit changes absolute date")
        controller.choose(key:"source",index:1); controller.refresh(at:now.addingTimeInterval(99999))
        controller.choose(key:"source",index:0)
        check(state.scene.elements[0].countdown == custom, "Source switch retains custom deadline and timezone")
        let beforeMixed = state.scene
        state.select([e.id,other.id]); controller.choose(key:"source",index:1)
        check(state.scene == beforeMixed && view.isHidden, "Mixed timer selection does not overwrite different values")
    }

}
