import Foundation

@main struct CoreTests {
    static func main() throws {
        let target = ApocalypseEvent.parseDay("2026-11-13")!
        assert(Countdown.string(until: target, now: target.addingTimeInterval(-198 * 3600 - 51 * 60)) == "198:51:00")
        assert(Countdown.string(until: target, now: target.addingTimeInterval(-86400)) == "24:00:00")
        assert(Countdown.string(until: target, now: target.addingTimeInterval(-0.25)) == "00:00:01")
        assert(Countdown.string(until: target, now: target.addingTimeInterval(1)) == "00:00:00")
        assert(ApocalypseEvent.parseDay("2027-02-29") == nil)
        assert(ApocalypseEvent.parseDay("2028-02-29") != nil)
        assert(ApocalypseEvent.parseDay("2027-13-01") == nil)
        assert(ApocalypseEvent.parseDay("2026-1-013") == nil)
        assert(ApocalypseEvent.parseDay("٢٠٢٦-11-13") == nil)
        let catalog = try EventCatalog.load(URL(fileURLWithPath: CommandLine.arguments[1]))
        assert(catalog.count == 58)
        assert(EventCatalog.next(in: catalog, now: target.addingTimeInterval(-1))?.id == "foerster-2026-11-13")
        assert(EventCatalog.next(in: catalog, now: target)?.id == "upcoming-01")
        assert(EventCatalog.next(in: catalog, now: catalog.filter(\.hasCountdown).map(\.target).max()!) == nil)
        assert(catalog.filter(\.hasCountdown).count == 19)
        assert(catalog.filter { !$0.hasCountdown }.count == 39)
        assert(catalog.filter { !$0.hasCountdown }.allSatisfy { !$0.counterText(now: target).contains(":") })
        assert(catalog.allSatisfy { !$0.displayedDate.contains("млрд") && !$0.displayedDate.contains("млн") })
        assert(catalog.first { $0.id == "upcoming-75" } == nil)
        assert(catalog.first { $0.id == "upcoming-14" } == nil)
        assert(catalog.first { $0.id == "upcoming-35" }?.displayedDate == "2030")
        assert(catalog.filter(\.hasCountdown).allSatisfy { $0.target <= ApocalypseEvent.parseDay("2040-12-31")! })
        let bad = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: bad) }
        try JSONEncoder().encode([catalog[0], catalog[0]]).write(to: bad)
        do { _ = try EventCatalog.load(bad); fatalError("Duplicate IDs were accepted") }
        catch { }
        print("Catalog checks passed: dates, total hours, expiry, next event, invalid catalog.")
    }
}
