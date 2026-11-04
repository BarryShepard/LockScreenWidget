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
        assert(catalog.count == 5)
        assert(EventCatalog.next(in: catalog, now: target.addingTimeInterval(-1))?.id == "foerster-2026-11-13")
        assert(EventCatalog.next(in: catalog, now: target)?.id == "whitecloud-2027-05-21")
        assert(EventCatalog.next(in: catalog, now: catalog.last!.target) == nil)
        let bad = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: bad) }
        try JSONEncoder().encode([catalog[0], catalog[0]]).write(to: bad)
        do { _ = try EventCatalog.load(bad); fatalError("Duplicate IDs were accepted") }
        catch { }
        print("14 checks passed: dates, total hours, expiry, next event, invalid catalog.")
    }
}
