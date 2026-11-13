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
        try clocks(now)
        wallTimes()
        try modelAndCatalog(now)
        try integration(now)
        try countdownTransforms(now)
        inspector(now)
        nativeInspectorTransactions()
        print("Scene countdown tests passed")
    }
    static func clocks(_ now: Date) throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        var clock = SceneClockModel()
        check(SceneClockPresentationController.value(clock, at: now, systemZone: utc) == "12:00", "Clock follows system zone")
        clock.timeZoneID = "Europe/Moscow"; clock.showsSeconds = true
        check(SceneClockPresentationController.value(clock, at: now.addingTimeInterval(5), systemZone: utc) == "15:00:05", "Clock stores explicit zone and seconds")
        clock.uses24Hour = false
        check(SceneClockPresentationController.value(clock, at: now, systemZone: utc) == "3:00:00 PM", "12-hour clock has period")
        clock.timeZoneID = "UTC"
        check(SceneClockPresentationController.value(clock, at: date("2026-11-13T00:00:00Z")) == "12:00:00 AM", "12-hour midnight")
        check(SceneClockPresentationController.value(clock, at: now) == "12:00:00 PM", "12-hour noon")
        clock.timeZoneID = "America/New_York"; clock.uses24Hour = true
        check(SceneClockPresentationController.value(clock, at: date("2026-11-01T05:30:00Z")) == "01:30:00" && SceneClockPresentationController.value(clock, at: date("2026-11-01T06:30:00Z")) == "01:30:00", "Clock handles repeated local hour")
        var element = SceneElementModel(kind: .clock, frame: CGRect(x: 20,y: 20,width: 300,height: 90))
        element.clock = SceneClockModel(timeZoneID: "UTC", showsSeconds: false, uses24Hour: true)
        let scene = EditorSceneModel(canvasSize: CGSize(width: 800,height: 500),elements: [element])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clock-tests-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SceneStore(directory: root)
        try store.save(scene)
        check(try store.load() == scene, "Clock store round trip")
        let presenter = ScenePresentationController(store: store)
        let first = presenter.content(for: scene, at: now)
        check(presenter.content(for: scene, at: now.addingTimeInterval(1)) == first, "Seconds-hidden clock avoids redraw")
        check(presenter.content(for: scene, at: now.addingTimeInterval(60)) != first, "Clock updates next minute")
        let state = SceneEditingStateModel(scene)
        let view = SceneClockInspectorView(frame: .zero)
        let controller = SceneClockInspectorController(state: state, view: view)
        state.select([element.id]); controller.refresh()
        check(!view.isHidden, "Clock controls visible")
        view.onChoice?("seconds",1)
        check(state.scene.elements[0].clock?.showsSeconds == true, "Clock seconds control")
        state.undo(); check(state.scene == scene, "Clock control is one Undo")
        var broken = scene; broken.elements[0].clock?.timeZoneID = "Invalid/Zone"
        do { _ = try broken.validated(); check(false, "Invalid clock zone rejected") } catch {}
        broken = scene; broken.elements[0].clock = nil
        do { _ = try broken.validated(); check(false, "Missing clock payload rejected") } catch {}
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
        check(helper.resolve(date: "0001-01-01", time: "00:00", zone: "UTC") == .invalid, "Dates before supported Gregorian years rejected")
        check(helper.resolve(date: "1500-02-29", time: "00:00", zone: "UTC") == .invalid, "Hybrid-calendar Julian leap date is not accepted")
        check(helper.resolve(date: "1582-10-10", time: "00:00", zone: "UTC") == .invalid, "Cutover year is explicitly outside editor range")
        check(helper.resolve(date: "1583-01-01", time: "00:00", zone: "UTC") != .invalid, "First supported full Gregorian year")
        check(helper.wallFields(date("1500-01-01T00:00:00Z"),zone:"UTC") == nil, "Historical target remains stored but is outside supported editor display")
        check(helper.resolve(date: "1700-02-29", time: "00:00", zone: "UTC") == .invalid, "Gregorian century is not a leap year")
        check(helper.resolve(date: "2000-02-29", time: "00:00", zone: "UTC") != .invalid, "Gregorian 400-year leap rule")
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

    static func countdownTransforms(_ now: Date) throws {
        var timer = SceneElementModel(kind: .countdown,frame: CGRect(x: 100,y: 100,width: 320,height: 80),rotation: 25,cornerRadius: 6)
        timer.countdown = .init(targetDate: now.addingTimeInterval(90000),timeZoneID: "UTC")
        let state = SceneEditingStateModel(EditorSceneModel(canvasSize: CGSize(width: 1200,height: 800),elements: [timer]))
        state.select([timer.id]); let original = state.value
        func resized(_ start: SceneSnapshot, sx: CGFloat, sy: CGFloat, stretch: Bool) -> SceneSnapshot {
            let element = start.scene.elements[0]
            let corner = SceneTransformController.targets([element],scale: 1).first { !$0.rotation && $0.handle.x == 1 && $0.handle.y == 1 }!
            let delta = SceneTransformController.rotate(CGPoint(x: element.frame.width*(sx-1),y: element.frame.height*(sy-1)),element.rotation * .pi/180)
            return SceneTransformController.applying(start,target: corner,from: corner.point,to: CGPoint(x: corner.point.x+delta.x,y: corner.point.y+delta.y),stretch: stretch,crop: false)
        }
        func near<T: BinaryFloatingPoint>(_ a: T?, _ b: T) -> Bool { a.map { abs($0-b) < 0.00001 } ?? false }
        let proportional = resized(original,sx: 1.5,sy: 1.5,stretch: false)
        check(near(proportional.scene.elements[0].textScaleX,1.5) && near(proportional.scene.elements[0].textScaleY,1.5), "Countdown proportional corner resize scales digits")
        check(proportional.scene.elements[0].style == timer.style && proportional.scene.elements[0].countdown == timer.countdown, "Countdown resize retains base typography and deadline options")
        state.preview(proportional); state.finish(from: original)
        let stretched = resized(proportional,sx: 1.25,sy: 1.75,stretch: true)
        let scaled = stretched.scene.elements[0]
        check(near(scaled.textScaleX,1.875) && near(scaled.textScaleY,2.625), "Shift resize compounds independent countdown text axes")
        let anchorBefore = SceneGeometry.corners(timer)[0], anchorAfter = SceneGeometry.corners(scaled)[0]
        check(hypot(anchorBefore.x-anchorAfter.x,anchorBefore.y-anchorAfter.y) < 0.00001, "Rotated countdown resize preserves opposite anchor")
        state.preview(stretched); state.finish(from: proportional)
        state.undo(); check(state.value == proportional, "Undo Shift resize restores proportional countdown scale")
        state.undo(); check(state.value == original && !state.canUndo, "Undo proportional resize restores original scales once")
        state.redo(); state.redo(); check(state.value == stretched && !state.canRedo, "Redo restores both countdown transforms")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("countdown-transform-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        try store.save(state.scene)
        let restored = try store.load()!
        check(restored == stretched.scene, "Countdown scales and settings persist together")
        let presenter = ScenePresentationController(store: store)
        for instant in [now, now.addingTimeInterval(1)] {
            guard case let .text(text,frame,sx,sy) = presenter.content(for: restored,at: instant).elements[0].drawing else { preconditionFailure("Countdown must render dynamic text") }
            check(near(sx,1.875) && near(sy,2.625) && near(frame.width,320), "Dynamic presenter applies persisted transform scales and logical width")
            check(text.string == SceneCountdownPresentationController.value(timer.countdown!,catalog: .init(),at: instant), "Scaled countdown retains live values on subsequent ticks")
        }
    }

    static func nativeInspectorTransactions() {
        // Hidden native windows exercise actual field-editor/end-edit and target-action
        // ordering without opening an app, changing the clipboard or showing a panel.
        do {
            let f = NativeCountdownInspectorFixture(target: date("2027-01-01T08:00:00Z"))
            f.type("Время", "10:15:00")
            for tick in 1...3 { f.controller.refresh(at: Date().addingTimeInterval(Double(tick))) }
            check(f.field("Время").currentEditor()?.string == "10:15:00", "Ticks preserve active native wall input")
            f.choose("zone", "Europe/Moscow")
            check(f.timer.targetDate == date("2027-01-01T10:15:00Z") && f.timer.timeZoneID == "Europe/Moscow", "Native time commits in original UTC before timezone action")
            check(f.field("Дата").stringValue == "2027-01-01" && f.field("Время").stringValue == "13:15:00", "Both native fields immediately reflect Moscow wall time")
            check(f.field("Время").currentEditor() == nil && f.commits == 2, "Wall edit and zone are each committed once")
            let after = f.state.scene
            _ = f.window.makeFirstResponder(nil)
            f.view.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: f.field("Время")))
            check(f.state.scene == after && f.commits == 2, "Later or duplicate field end cannot reinterpret the old UTC text")
            f.state.undo()
            check(f.timer.targetDate == date("2027-01-01T10:15:00Z") && f.timer.timeZoneID == "UTC", "Undo zone keeps the preceding wall edit")
            f.state.undo()
            check(f.timer.targetDate == date("2027-01-01T08:00:00Z") && !f.state.canUndo, "No duplicate Undo entry for native completion")
        }
        do {
            let f = NativeCountdownInspectorFixture(target: date("2027-01-01T23:30:00Z"))
            f.type("Дата", "2027-01-02")
            f.choose("zone", "Europe/Moscow")
            check(f.timer.targetDate == date("2027-01-02T23:30:00Z"), "Active calendar date commits under original timezone")
            check(f.field("Дата").stringValue == "2027-01-03" && f.field("Время").stringValue == "02:30:00", "Timezone refresh crosses midnight in both fields")
            _ = f.window.makeFirstResponder(nil)
            check(f.timer.targetDate == date("2027-01-02T23:30:00Z") && f.commits == 2, "Midnight crossing has no late stale commit")
        }
        for choice in ["source", "format", "seconds"] {
            let f = NativeCountdownInspectorFixture(target: date("2027-01-01T08:00:00Z"))
            f.type("Время", "10:15:00")
            if choice == "source" { f.choose(choice, "Конец света") }
            if choice == "format" { f.choose(choice, "Суммарные часы") }
            if choice == "seconds" { f.toggleSeconds(false) }
            check(f.timer.targetDate == date("2027-01-01T10:15:00Z") && f.commits == 2, "Native pending edit completes before \(choice)")
            if choice == "source" {
                check(f.timer.source == .apocalypse, "Captured source choice survives reentrant menu render")
                f.choose("source", "Своя дата")
                check(f.field("Время").stringValue == "10:15:00", "Custom wall time survives pending-input source switch")
            }
            if choice == "format" { check(f.timer.format == .totalHours, "Captured format choice survives reentrant render") }
            if choice == "seconds" { check(!f.timer.showsSeconds, "Captured checkbox choice survives reentrant render") }
        }
        do {
            let f = NativeCountdownInspectorFixture(target: date("2027-01-01T08:00:00Z"))
            f.type("Дата", "2027-02-02")
            let other = f.state.scene.elements[1]
            f.state.select([other.id]) // End may be delivered after selection changed.
            check(f.state.scene.elements[0].countdown?.targetDate == date("2027-02-02T08:00:00Z") && f.state.scene.elements[1] == other, "Native pending edit stays bound to original layer")
            check(f.field("Дата").stringValue == "2027-06-01" && f.field("Время").currentEditor() == nil && f.commits == 1, "Selection refresh displays new layer after completing old field once")
            f.state.undo(); check(!f.state.canUndo && f.state.scene.elements[0].countdown?.targetDate == date("2027-01-01T08:00:00Z"), "Selection transfer creates one edit Undo")
        }
        do {
            let f = NativeCountdownInspectorFixture(target: date("2027-01-01T08:00:00Z"))
            check(f.window.makeFirstResponder(f.field("Время")), "Untouched native field gets focus")
            let before = f.state.scene
            f.state.select([before.elements[1].id])
            check(f.state.scene == before && f.commits == 0 && f.field("Время").currentEditor() == nil && f.field("Время").stringValue == "12:00:00", "Untouched field ends on selection without stale text or history")
        }
        do {
            let f = NativeCountdownInspectorFixture(target: date("2024-03-10T12:00:00Z"), zone: "America/New_York")
            f.type("Время", "02:30")
            f.choose("source", "Конец света")
            check(f.timer.source == .custom && f.timer.targetDate == date("2024-03-10T12:00:00Z") && f.commits == 0, "Invalid native wall input blocks source change without coercion")
            check(f.field("Время").stringValue == "02:30" && f.menu("source").titleOfSelectedItem == "Своя дата", "Invalid draft stays visible with original source")
            f.choose("zone", "UTC")
            check(f.timer.timeZoneID == "America/New_York" && f.menu("zone").titleOfSelectedItem == "America/New_York", "Invalid draft is never reinterpreted in a different zone")
            check(descendants(f.view).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Сначала исправьте") && $0.stringValue.contains("1583–9999") }, "Rejected menu choice explains draft and supported range inline")
            f.choose("format", "Суммарные часы"); f.toggleSeconds(false)
            check(f.timer.format == .totalHours && !f.timer.showsSeconds && f.field("Время").stringValue == "02:30" && f.commits == 2, "Independent formatting preserves unresolved draft")
            f.type("Время", "03:30")
            f.choose("source", "Конец света")
            check(f.timer.targetDate == date("2024-03-10T07:30:00Z") && f.timer.source == .apocalypse && f.commits == 4, "Corrected native input commits before originally intended source choice")
        }
        do {
            let f = NativeCountdownInspectorFixture(target: date("2024-11-03T12:00:00Z"), zone: "America/New_York")
            f.type("Время", "01:30")
            f.choose("zone", "UTC")
            check(f.timer.timeZoneID == "America/New_York" && f.commits == 0 && !f.menu("occurrence").isHidden, "Native ambiguous draft requires explicit occurrence before zone change")
            f.chooseIndex("occurrence", 2)
            check(f.timer.targetDate == date("2024-11-03T06:30:00Z") && f.commits == 1, "Native second-occurrence action commits exactly once")
            f.choose("zone", "UTC")
            check(f.field("Время").stringValue == "06:30:00" && f.commits == 2, "Zone change after occurrence preserves resolved instant")
        }
        do {
            let f = NativeCountdownInspectorFixture(target: date("2024-11-03T12:00:00Z"), zone: "America/New_York")
            f.type("Время", "01:30")
            let before = f.state.scene
            f.state.select([before.elements[1].id])
            check(f.state.scene == before && f.commits == 0 && f.menu("occurrence").isHidden, "Unresolved native edit cannot be applied to a different selected layer")
        }
    }

}


private final class NativeCountdownInspectorFixture {
    let state: SceneEditingStateModel
    let view = SceneCountdownInspectorView()
    let controller: SceneCountdownInspectorController
    let window: NSWindow
    var commits = 0
    var timer: SceneCountdownModel { state.scene.elements[0].countdown! }
    init(target: Date, zone: String = "UTC") {
        var first = SceneElementModel(kind: .countdown, frame: CGRect(x: 0,y: 0,width: 320,height: 80))
        first.countdown = .init(targetDate: target,timeZoneID: zone)
        var second = first; second.id = UUID()
        second.countdown = .init(targetDate: SceneCountdownTests.date("2027-06-01T12:00:00Z"),timeZoneID: "UTC")
        state = SceneEditingStateModel(EditorSceneModel(canvasSize: CGSize(width: 800,height: 500),elements: [first,second]))
        state.select([first.id])
        controller = SceneCountdownInspectorController(state: state,view: view,catalog: .init(),now: target)
        window = NSWindow(contentRect: CGRect(x: 0,y: 0,width: 340,height: 700),styleMask: .borderless,backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        state.onUpdate = { [weak self] update in
            guard let self else { return }
            if case .committed = update { self.commits += 1 }
            self.controller.refresh()
        }
        controller.refresh()
    }
    deinit { window.close() }
    func field(_ label: String) -> NSTextField {
        SceneCountdownTests.descendants(view).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == label }!
    }
    func menu(_ key: String) -> NSPopUpButton {
        SceneCountdownTests.descendants(view).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == key }!
    }
    func type(_ label: String, _ text: String) {
        let field = field(label)
        SceneCountdownTests.check(window.makeFirstResponder(field), "Native wall field accepts focus")
        let editor = field.currentEditor() as! NSTextView
        editor.insertText(text, replacementRange: NSRange(location: 0,length: editor.string.utf16.count))
        SceneCountdownTests.check(editor.string == text, "Native field-editor insertion is visible")
    }
    func choose(_ key: String, _ title: String) {
        let menu = menu(key)
        SceneCountdownTests.check(menu.itemTitles.contains(title), "Native popup contains requested choice")
        menu.selectItem(withTitle: title)
        SceneCountdownTests.check(menu.sendAction(menu.action!, to: menu.target), "Native popup target/action dispatched")
    }
    func chooseIndex(_ key: String, _ index: Int) {
        let menu = menu(key); menu.selectItem(at: index)
        SceneCountdownTests.check(menu.sendAction(menu.action!, to: menu.target), "Native occurrence action dispatched")
    }
    func toggleSeconds(_ shows: Bool) {
        let button = SceneCountdownTests.descendants(view).compactMap { $0 as? NSButton }.first { $0.title == "Показывать секунды" }!
        button.state = shows ? .on : .off
        SceneCountdownTests.check(button.sendAction(button.action!, to: button.target), "Native checkbox action dispatched")
    }
}
