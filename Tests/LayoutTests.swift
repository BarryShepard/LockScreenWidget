import AppKit

@main struct LayoutTests {
    static func main() throws {
        let _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let events = try loadEventCatalog(root.appendingPathComponent("Resources/events.json")).events
        let sizes: [(CGFloat, CGFloat)] = [(1024,768),(1280,800),(1440,900),(1728,1117),(1920,1080),(2560,1080)]
        for (width,height) in sizes {
            for event in events {
                let view = CountdownView(overlay: true)
                view.render(makeCountdownPresentation(
                    content: makeCountdownDisplay(event: event, now: parseEventDay("2026-11-04")!),
                    settings: EditorSettingsModel()))
                let frame = CountdownView.overlayFrame(in: NSRect(x: 0, y: 0, width: width, height: height))
                let bounds = NSRect(origin: .zero, size: frame.size)
                view.frame = bounds
                let runs = view.layout(in: bounds)
                assert(runs.count == 2)
                assert(runs.allSatisfy { bounds.contains($0.frame) }, "Clipped text at \(width)x\(height), \(event.id)")
                for pair in zip(runs, runs.dropFirst()) { assert(pair.0.frame.maxY <= pair.1.frame.minY) }
            }
        }
        // Controller-prepared period labels preserve the font cap without changing stored settings.
        let periodView = CountdownView(overlay: true)
        let periodSettings = EditorSettingsModel()
        periodView.render(makeCountdownPresentation(content: CountdownDisplayModel(counter: "2030", usesCountdown: false),
                                                   settings: periodSettings))
        let periodRun = periodView.layout(in: NSRect(x: 0, y: 0, width: 1512, height: 982))[1]
        assert((periodRun.attributes[.font] as! NSFont).pointSize == 42)
        assert(abs((periodRun.attributes[.kern] as! CGFloat) - (-0.84)) < 0.001)
        assert(periodSettings.typography[1].size == 112)
        func makeEditor() -> EditorWindowController {
            let controller = EditorWindowController(model: ApplicationModel(catalog: EventCatalogModel(events: events), settings: EditorSettingsModel()), preferences: MemoryPreferences())
            controller.canvas.previewScreenSize = NSSize(width: 1512, height: 982)
            return controller
        }
        let editable = makeEditor()
        editable.canvas.frame = NSRect(x: 0, y: 0, width: 1100, height: 540)
        editable.selectEvent(at: 1)
        editable.moveElement(0, to: .zero)
        editable.moveElement(1, to: .zero)
        let original = editable.canvas.layout(in: editable.canvas.bounds)
        editable.moveElement(0, to: NSPoint(x: 0.1, y: 0.1))
        let moved = editable.canvas.layout(in: editable.canvas.bounds)
        assert(moved[0].frame.minX > original[0].frame.minX)
        assert(moved[0].frame.minY > original[0].frame.minY)
        assert(moved[1].frame == original[1].frame, "Moving title must not move timer")
        editable.moveElement(1, to: NSPoint(x: -10, y: 10))
        assert(editable.canvas.bounds.contains(editable.canvas.layout(in: editable.canvas.bounds)[1].frame), "Dragging must stay on screen")
        editable.moveElement(0, to: .zero)
        editable.moveElement(1, to: .zero)
        editable.beginInteraction(at: .zero, extendingSelection: false)
        editable.dragInteraction(to: NSPoint(x: 1100, y: 540), constrainAxis: false)
        assert(editable.selectedIndices == [0, 1], "Marquee must select both blocks")
        let groupStart = editable.canvas.layout(in: editable.canvas.bounds)
        let anchor = NSPoint(x: groupStart[0].frame.midX, y: groupStart[0].frame.midY)
        editable.beginInteraction(at: anchor, extendingSelection: false)
        editable.dragInteraction(to: NSPoint(x: anchor.x + 40, y: anchor.y + 10), constrainAxis: true)
        let horizontal = editable.canvas.layout(in: editable.canvas.bounds)
        for index in 0..<2 {
            assert(abs(horizontal[index].frame.minX - groupStart[index].frame.minX - 40) < 0.001)
            assert(abs(horizontal[index].frame.minY - groupStart[index].frame.minY) < 0.001)
        }
        editable.dragInteraction(to: NSPoint(x: anchor.x + 50, y: anchor.y + 120), constrainAxis: true)
        assert(abs(editable.canvas.layout(in: editable.canvas.bounds)[0].frame.minY - groupStart[0].frame.minY) < 0.001,
               "Shift axis must remain locked during the gesture")
        editable.dragInteraction(to: NSPoint(x: anchor.x + 5000, y: anchor.y + 5000), constrainAxis: false)
        let atEdge = editable.canvas.layout(in: editable.canvas.bounds)
        assert(abs((atEdge[1].frame.minY - atEdge[0].frame.minY) -
                   (groupStart[1].frame.minY - groupStart[0].frame.minY)) < 0.001,
               "Group spacing must survive edge clamping")
        // Clear selection, select one element, and choose a vertical axis.
        editable.moveElement(0, to: .zero)
        editable.moveElement(1, to: .zero)
        editable.beginInteraction(at: .zero, extendingSelection: false)
        editable.beginInteraction(at: anchor, extendingSelection: false)
        editable.dragInteraction(to: NSPoint(x: anchor.x + 8, y: anchor.y + 40), constrainAxis: true)
        let vertical = editable.canvas.layout(in: editable.canvas.bounds)
        assert(abs(vertical[0].frame.minX - groupStart[0].frame.minX) < 0.001)
        assert(abs(vertical[0].frame.minY - groupStart[0].frame.minY - 40) < 0.001)
        assert(vertical[1].frame == groupStart[1].frame)
        editable.beginInteraction(at: NSPoint(x: vertical[1].frame.midX, y: vertical[1].frame.midY), extendingSelection: true)
        assert(editable.selectedIndices == [0, 1], "Shift click must add a block")
        // Settings persistence is covered independently by SettingsTests.
        let editor = makeEditor()
        editor.canvas.frame = NSRect(x: 0, y: 0, width: 1544, height: 1014)
        editor.selectEvent(at: 1)
        assert(editor.canvas.layout(in: editor.canvas.bounds).count == 2)
        editor.setInformationVisible(true)
        assert(editor.canvas.layout(in: editor.canvas.bounds).count == 3)
        editor.selectBlock(2)
        editor.moveElement(2, to: NSPoint(x: 0.05, y: 0.1))
        let infoBefore = editor.canvas.layout(in: editor.canvas.bounds)[2].frame
        editor.nudgeSelection(x: 1, y: 0)
        let infoAfter = editor.canvas.layout(in: editor.canvas.bounds)[2].frame
        assert(abs(infoAfter.minX - infoBefore.minX - 1) < 0.001)
        editor.nudgeSelection(x: 0, y: 1, largeStep: true)
        assert(abs(editor.canvas.layout(in: editor.canvas.bounds)[2].frame.minY - infoAfter.minY - 10) < 0.001)
        editor.centerSelection(horizontal: true)
        assert(abs(editor.canvas.layout(in: editor.canvas.bounds)[2].frame.midX - editor.canvas.bounds.midX) < 0.001)
        editor.centerSelection(horizontal: false)
        assert(abs(editor.canvas.layout(in: editor.canvas.bounds)[2].frame.midY - editor.canvas.bounds.midY) < 0.001)
        editor.setInformationVisible(false)
        assert(editor.selectedIndices.isEmpty)
        assert(editor.editorView.inspector.block.indexOfSelectedItem == 0)
        assert(editor.editorView.inspector.block.item(at: 2)?.isEnabled == false)
        assert(!editor.editorView.inspector.size.isEnabled)
        editor.selectBlock(0)
        var typography = editor.model.settings.typography[0]
        typography.family = "Helvetica Neue"
        typography.weight = 3
        typography.size = 38
        typography.lineHeight = 50
        typography.spacing = 5
        typography.alignment = 0
        typography.verticalAlignment = 2
        editor.setTypography(typography, for: [0])
        let styled = editor.canvas.layout(in: editor.canvas.bounds)[0]
        assert(abs((styled.attributes[.font] as! NSFont).pointSize - 38) < 0.001)
        assert(abs((styled.attributes[.kern] as! CGFloat) - 1.9) < 0.001)
        assert((styled.attributes[.paragraphStyle] as! NSParagraphStyle).alignment == .left)
        assert((styled.attributes[.paragraphStyle] as! NSParagraphStyle).minimumLineHeight == 50)
        assert(styled.verticalAlignment == 1, "Bottom alignment must use all spare text-box height")
        assert(editor.model.settings.typography[1].size == 112, "Typography edits must preserve other blocks")
        typography.size = 26
        typography.lineHeight = 10
        editor.setTypography(typography, for: [0])
        let tight = editor.canvas.layout(in: editor.canvas.bounds)[0]
        let tightFont = tight.attributes[.font] as! NSFont
        assert(tight.frame.height >= tightFont.ascender - tightFont.descender, "Tight line height must retain glyph ink")
        // A group property edit must preserve individual point sizes.
        let preview = makeEditor()
        preview.canvas.frame = NSRect(x: 0, y: 0, width: 1100, height: 540)
        preview.beginInteraction(at: .zero, extendingSelection: false)
        preview.dragInteraction(to: NSPoint(x: 1100, y: 540), constrainAxis: false)
        preview.editSelectedTypography { $0.spacing = 3 }
        assert(preview.model.settings.typography[0].size == 26 && preview.model.settings.typography[1].size == 112)
        assert(preview.model.settings.typography[0].spacing == 3 && preview.model.settings.typography[1].spacing == 3)
        preview.centerSelection(horizontal: false)
        let groupFrames = preview.canvas.layout(in: preview.canvas.bounds)
        let groupBounds = groupFrames[0].frame.union(groupFrames[1].frame)
        assert(abs(groupBounds.midY - preview.canvas.bounds.midY) < 0.001)
        let invalid = validateBlockTypography(BlockTypographyModel(size: -100, lineHeight: -1, spacing: 500, alignment: 9))
        assert(invalid.size == 6 && invalid.lineHeight == 0 && invalid.spacing == 100 && invalid.alignment == 2)
        // Input travels through the controller, and live text is not reset by ticks.
        editor.selectBlock(0)
        let sizeField = editor.editorView.inspector.size
        sizeField.stringValue = "38,5"
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sizeField))
        assert(editor.model.settings.typography[0].size == 38.5)
        editor.refresh(at: parseEventDay("2026-11-09")!)
        assert(sizeField.stringValue == "38,5", "A tick must not rewrite an in-progress field")
        assert(loadEditorSettings(from: editor.preferences).typography[0].size == 38.5)
        sizeField.stringValue = "-"
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sizeField))
        assert(editor.model.settings.typography[0].size == 38.5)
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: sizeField))
        assert(sizeField.stringValue == "38.5")
        let lock = LockScreenController(model: editor.model, readLockState: { false })
        let ticker = CountdownController { now in editor.refresh(at: now); lock.refresh(at: now) }
        editor.selectEvent(at: events.firstIndex { $0.id == "upcoming-35" }! + 1)
        let deadline = parseEventDay("2026-11-13")!
        ticker.refresh(at: deadline.addingTimeInterval(-1))
        assert(lock.currentDisplay.counter == "00:00:01")
        assert(editor.canvas.presentation.blocks[1].text == "2030", "Preview choice must not replace the lock-screen event")
        ticker.refresh(at: deadline)
        assert(lock.currentDisplay.title == events.first { $0.id == "upcoming-01" }!.title)
        editor.selectEvent(at: 0)
        ticker.refresh(at: deadline)
        assert(editor.canvas.presentation.blocks[1].text == lock.currentDisplay.counter)
        print("Typography, migration, information visibility, keyboard steps, and canvas centering passed.")
        print("Dragging, marquee/group selection, Shift axes, and shared edge constraints passed.")
        print("348 overlay layouts passed: system font, all events, six display sizes.")
    }
}
