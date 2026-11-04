import AppKit

@main struct LayoutTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        AppFont.register(url: root.appendingPathComponent("Resources/Fonts/Manrope.ttf"))
        assert(AppFont.font(20).fontName.contains("Manrope"))
        let events = try EventCatalog.load(root.appendingPathComponent("Resources/events.json"))
        let sizes: [(CGFloat, CGFloat)] = [(1024,768),(1280,800),(1440,900),(1728,1117),(1920,1080),(2560,1080)]
        for (width,height) in sizes {
            for event in events {
                let view = CountdownView(overlay: true)
                view.event = event
                view.now = ApocalypseEvent.parseDay("2026-11-04")!
                let bounds = NSRect(x: 0, y: 0, width: min(1150,width * 0.88), height: min(390,height * 0.39))
                let runs = view.layout(in: bounds)
                assert(runs.count == 4)
                assert(runs.allSatisfy { bounds.contains($0.frame) }, "Clipped text at \(width)x\(height), \(event.id)")
                for pair in zip(runs, runs.dropFirst()) { assert(pair.0.frame.maxY <= pair.1.frame.minY) }
            }
        }
        print("30 overlay layouts passed: bundled Manrope, all events, six display sizes.")
    }
}
