import Foundation

@main struct CoreTests {
    static func main() throws {
        let target = parseEventDay("2026-11-13")!
        assert(calculateCountdown(until: target, now: target.addingTimeInterval(-198 * 3600 - 51 * 60)) == "198:51:00")
        assert(calculateCountdown(until: target, now: target.addingTimeInterval(-86400)) == "24:00:00")
        assert(calculateCountdown(until: target, now: target.addingTimeInterval(-0.25)) == "00:00:01")
        assert(calculateCountdown(until: target, now: target.addingTimeInterval(1)) == "00:00:00")
        assert(parseEventDay("2027-02-29") == nil)
        assert(parseEventDay("2028-02-29") != nil)
        assert(parseEventDay("2027-13-01") == nil)
        assert(parseEventDay("2026-1-013") == nil)
        assert(parseEventDay("٢٠٢٦-11-13") == nil)
        let catalog = try loadEventCatalog(URL(fileURLWithPath: CommandLine.arguments[1]))
        assert(catalog.events.count == 58)
        assert(selectNextEvent(in: catalog, now: target.addingTimeInterval(-1))?.id == "foerster-2026-11-13")
        assert(selectNextEvent(in: catalog, now: target)?.id == "upcoming-01")
        assert(selectNextEvent(in: catalog, now: catalog.events.filter(eventHasCountdown).map(eventTarget).max()!) == nil)
        assert(catalog.events.filter(eventHasCountdown).count == 19)
        assert(catalog.events.filter { !eventHasCountdown($0) }.count == 39)
        assert(catalog.events.filter { !eventHasCountdown($0) }.allSatisfy { !makeCountdownDisplay(event: $0, now: target).counter.contains(":") })
        assert(catalog.events.allSatisfy { !displayedEventDate($0).contains("млрд") && !displayedEventDate($0).contains("млн") })
        assert(catalog.events.first { $0.id == "upcoming-75" } == nil)
        assert(catalog.events.first { $0.id == "upcoming-14" } == nil)
        assert(catalog.events.first { $0.id == "upcoming-35" }.map(displayedEventDate) == "2030")
        assert(catalog.events.filter(eventHasCountdown).allSatisfy { eventTarget($0) <= parseEventDay("2040-12-31")! })
        assert(selectNextEvent(in: EventCatalogModel(), now: target) == nil)
        let emptyDisplay = makeCountdownDisplay(event: nil, now: target)
        assert(emptyDisplay.counter == "00:00:00")
        assert(emptyDisplay.title == "Новых предсказаний пока нет")
        let bad = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: bad) }
        try JSONEncoder().encode([catalog.events[0], catalog.events[0]]).write(to: bad)
        do { _ = try loadEventCatalog(bad); fatalError("Duplicate IDs were accepted") }
        catch { }
        print("Catalog checks passed: dates, total hours, expiry, next event, invalid catalog.")
    }
}
