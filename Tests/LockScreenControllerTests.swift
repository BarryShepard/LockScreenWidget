import AppKit

@main struct LockScreenControllerTests {
    static func main() {
        let _ = NSApplication.shared
        let model = ApplicationModel(catalog: EventCatalogModel(), settings: EditorSettingsModel())
        var locked = false
        var delayedActions: [() -> Void] = []
        var began = 0
        var completions: [PanelTestCompletion] = []
        let controller = LockScreenController(model: model, readLockState: { locked }, makePanels: { [] },
            scheduleAfter: { _, action in delayedActions.append(action) })
        controller.onTestWillBegin = { began += 1 }
        controller.onTestDidEnd = { completions.append($0) }
        controller.start()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        controller.testPanel()
        assert(began == 1 && delayedActions.count == 1)
        controller.testPanel()
        assert(began == 1 && delayedActions.count == 2, "A repeated test must preserve the initial editor visibility")
        delayedActions[0]()
        assert(completions.isEmpty, "An older timeout must not finish the newer test")
        delayedActions[1]()
        assert(completions == [.restoreEditor])

        controller.testPanel()
        locked = true
        controller.refresh(at: now)
        assert(completions.last == .deferEditor)
        locked = false
        controller.refresh(at: now)
        assert(completions.last == .restoreEditor, "Unlock must restore the editor after an interrupted test")
        let completionCount = completions.count
        delayedActions[2]()
        assert(completions.count == completionCount, "Interrupted test timeout must be inert")

        controller.testPanel()
        controller.toggleEnabled()
        assert(!model.isEnabled && completions.last == .restoreEditor)
        controller.testPanel()
        controller.stop()
        assert(completions.last == .discardEditor)
        let stoppedCount = completions.count
        delayedActions.last?()
        assert(completions.count == stoppedCount, "Shutdown must invalidate pending callbacks")

        // Test the receiving controller too: deferral must preserve visibility intent.
        let editor = EditorWindowController(model: model, preferences: MemoryPreferences())
        editor.showPreview()
        assert(editor.window?.isVisible == true)
        editor.hideForPanelTest()
        editor.finishPanelTest(.deferEditor)
        assert(editor.window?.isVisible == false)
        editor.finishPanelTest(.restoreEditor)
        assert(editor.window?.isVisible == true)
        editor.hideForPanelTest()
        editor.finishPanelTest(.discardEditor)
        editor.finishPanelTest(.restoreEditor)
        assert(editor.window?.isVisible == false)
        editor.close()
        print("Panel lifecycle checks passed: repeated tests, lock/unlock restoration, disable and shutdown.")
    }
}
