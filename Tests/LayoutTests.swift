import AppKit

final class MemoryPreferences: UserDefaults {
    private var values: [String: Any] = [:]
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@main struct LayoutTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let events = try EventCatalog.load(root.appendingPathComponent("Resources/events.json"))
        let sizes: [(CGFloat, CGFloat)] = [(1024,768),(1280,800),(1440,900),(1728,1117),(1920,1080),(2560,1080)]
        for (width,height) in sizes {
            for event in events {
                let view = CountdownView(overlay: true, preferences: MemoryPreferences())
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
        let editable = CountdownView(overlay: false, preferences: MemoryPreferences())
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
        // Settings migration and persistence must not touch the user's real preferences.
        let preferences = MemoryPreferences()
        preferences.set([0.1, 0.2, 0.3, 0.4], forKey: "elementOffsets")
        let migrated = EditorSettings.load(from: preferences)
        assert(migrated.offsets == [0.1, 0.2, 0.3, 0.4, 0, 0])
        migrated.save(to: preferences)
        assert(EditorSettings.load(from: preferences) == migrated)
        let editor = CountdownView(overlay: true, preferences: MemoryPreferences())
        editor.frame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        editor.event = events[0]
        assert(editor.layout(in: editor.bounds).count == 2)
        editor.setInformationVisible(true)
        assert(editor.layout(in: editor.bounds).count == 3)
        editor.selectBlock(2)
        editor.moveElement(2, to: NSPoint(x: 0.05, y: 0.1))
        let infoBefore = editor.layout(in: editor.bounds)[2].frame
        editor.nudgeSelection(x: 1, y: 0)
        let infoAfter = editor.layout(in: editor.bounds)[2].frame
        assert(abs(infoAfter.minX - infoBefore.minX - 1) < 0.001)
        editor.nudgeSelection(x: 0, y: 1, largeStep: true)
        assert(abs(editor.layout(in: editor.bounds)[2].frame.minY - infoAfter.minY - 10) < 0.001)
        editor.centerSelection(horizontal: true)
        assert(abs(editor.layout(in: editor.bounds)[2].frame.midX - editor.bounds.midX) < 0.001)
        editor.centerSelection(horizontal: false)
        assert(abs(editor.layout(in: editor.bounds)[2].frame.midY - editor.bounds.midY) < 0.001)
        editor.setInformationVisible(false)
        assert(editor.selectedIndices.isEmpty)
        editor.selectBlock(0)
        var typography = editor.settings.typography[0]
        typography.family = "Helvetica Neue"
        typography.weight = 3
        typography.size = 38
        typography.lineHeight = 50
        typography.spacing = 5
        typography.alignment = 0
        typography.verticalAlignment = 2
        editor.setTypography(typography, for: [0])
        let styled = editor.layout(in: editor.bounds)[0]
        assert(abs((styled.attributes[.font] as! NSFont).pointSize - 38) < 0.001)
        assert(abs((styled.attributes[.kern] as! CGFloat) - 1.9) < 0.001)
        assert((styled.attributes[.paragraphStyle] as! NSParagraphStyle).alignment == .left)
        assert((styled.attributes[.paragraphStyle] as! NSParagraphStyle).minimumLineHeight == 50)
        assert(editor.settings.typography[1].size == 112, "Typography edits must preserve other blocks")
        typography.size = 26
        typography.lineHeight = 10
        editor.setTypography(typography, for: [0])
        let tight = editor.layout(in: editor.bounds)[0]
        let tightFont = tight.attributes[.font] as! NSFont
        assert(tight.frame.height >= tightFont.ascender - tightFont.descender, "Tight line height must retain glyph ink")
        // A group property edit must preserve individual point sizes.
        let preview = CountdownView(overlay: false, preferences: MemoryPreferences())
        preview.frame = NSRect(x: 0, y: 0, width: 1100, height: 540)
        preview.beginInteraction(at: .zero, extendingSelection: false)
        preview.dragInteraction(to: NSPoint(x: 1100, y: 540), constrainAxis: false)
        preview.editSelectedTypography { $0.spacing = 3 }
        assert(preview.settings.typography[0].size == 26 && preview.settings.typography[1].size == 112)
        assert(preview.settings.typography[0].spacing == 3 && preview.settings.typography[1].spacing == 3)
        preview.centerSelection(horizontal: false)
        let groupFrames = preview.layout(in: preview.bounds)
        let groupBounds = groupFrames[0].frame.union(groupFrames[1].frame)
        assert(abs(groupBounds.midY - preview.bounds.midY) < 0.001)
        var invalid = BlockTypography(size: -100, lineHeight: -1, spacing: 500, alignment: 9)
        invalid.validate()
        assert(invalid.size == 6 && invalid.lineHeight == 0 && invalid.spacing == 100 && invalid.alignment == 2)
        print("Typography, migration, information visibility, keyboard steps, and canvas centering passed.")
        print("Dragging, marquee/group selection, Shift axes, and shared edge constraints passed.")
        print("30 overlay layouts passed: system font, all events, six display sizes.")
    }
}
