import AppKit

@main struct LayoutTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let events = try EventCatalog.load(root.appendingPathComponent("Resources/events.json"))
        let sizes: [(CGFloat, CGFloat)] = [(1024,768),(1280,800),(1440,900),(1728,1117),(1920,1080),(2560,1080)]
        for (width,height) in sizes {
            for event in events {
                let view = CountdownView(overlay: true)
                view.event = event
                view.now = ApocalypseEvent.parseDay("2026-11-04")!
                let frame = CountdownView.overlayFrame(in: NSRect(x: 0, y: 0, width: width, height: height))
                let bounds = NSRect(origin: .zero, size: frame.size)
                view.frame = bounds
                view.moveElement(0, to: .zero)
                view.moveElement(1, to: .zero)
                let runs = view.layout(in: bounds)
                assert(runs.count == 2)
                assert(runs.allSatisfy { bounds.contains($0.frame) }, "Clipped text at \(width)x\(height), \(event.id)")
                for pair in zip(runs, runs.dropFirst()) { assert(pair.0.frame.maxY <= pair.1.frame.minY) }
            }
        }
        let editable = CountdownView(overlay: false)
        editable.frame = NSRect(x: 0, y: 0, width: 1100, height: 540)
        editable.event = events[0]
        editable.moveElement(0, to: .zero)
        editable.moveElement(1, to: .zero)
        let original = editable.layout(in: editable.bounds)
        editable.moveElement(0, to: NSPoint(x: 0.1, y: 0.1))
        let moved = editable.layout(in: editable.bounds)
        assert(moved[0].frame.minX > original[0].frame.minX)
        assert(moved[0].frame.minY > original[0].frame.minY)
        assert(moved[1].frame == original[1].frame, "Moving title must not move timer")
        editable.moveElement(1, to: NSPoint(x: -10, y: 10))
        assert(editable.bounds.contains(editable.layout(in: editable.bounds)[1].frame), "Dragging must stay on screen")
        editable.moveElement(0, to: .zero)
        editable.moveElement(1, to: .zero)
        editable.beginInteraction(at: .zero, extendingSelection: false)
        editable.dragInteraction(to: NSPoint(x: 1100, y: 540), constrainAxis: false)
        assert(editable.selectedIndices == [0, 1], "Marquee must select both blocks")
        let groupStart = editable.layout(in: editable.bounds)
        let anchor = NSPoint(x: groupStart[0].frame.midX, y: groupStart[0].frame.midY)
        editable.beginInteraction(at: anchor, extendingSelection: false)
        editable.dragInteraction(to: NSPoint(x: anchor.x + 40, y: anchor.y + 10), constrainAxis: true)
        let horizontal = editable.layout(in: editable.bounds)
        for index in 0..<2 {
            assert(abs(horizontal[index].frame.minX - groupStart[index].frame.minX - 40) < 0.001)
            assert(abs(horizontal[index].frame.minY - groupStart[index].frame.minY) < 0.001)
        }
        editable.dragInteraction(to: NSPoint(x: anchor.x + 50, y: anchor.y + 120), constrainAxis: true)
        assert(abs(editable.layout(in: editable.bounds)[0].frame.minY - groupStart[0].frame.minY) < 0.001,
               "Shift axis must remain locked during the gesture")
        editable.dragInteraction(to: NSPoint(x: anchor.x + 5000, y: anchor.y + 5000), constrainAxis: false)
        let atEdge = editable.layout(in: editable.bounds)
        assert(abs((atEdge[1].frame.minY - atEdge[0].frame.minY) -
                   (groupStart[1].frame.minY - groupStart[0].frame.minY)) < 0.001,
               "Group spacing must survive edge clamping")
        // Clear selection, select one element, and choose a vertical axis.
        editable.moveElement(0, to: .zero)
        editable.moveElement(1, to: .zero)
        editable.beginInteraction(at: .zero, extendingSelection: false)
        editable.beginInteraction(at: anchor, extendingSelection: false)
        editable.dragInteraction(to: NSPoint(x: anchor.x + 8, y: anchor.y + 40), constrainAxis: true)
        let vertical = editable.layout(in: editable.bounds)
        assert(abs(vertical[0].frame.minX - groupStart[0].frame.minX) < 0.001)
        assert(abs(vertical[0].frame.minY - groupStart[0].frame.minY - 40) < 0.001)
        assert(vertical[1].frame == groupStart[1].frame)
        editable.beginInteraction(at: NSPoint(x: vertical[1].frame.midX, y: vertical[1].frame.midY), extendingSelection: true)
        assert(editable.selectedIndices == [0, 1], "Shift click must add a block")
        print("Dragging, marquee/group selection, Shift axes, and shared edge constraints passed.")
        print("30 overlay layouts passed: system font, all events, six display sizes.")
    }
}
