import AppKit

enum SceneScreenIdentity {
    static func identifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func matchingIndex(target: String?, available: [String?]) -> Int? {
        guard let target else { return nil }
        return available.firstIndex { $0 == target }
    }
}

final class LockScreenController: NSObject {
    private let model: ApplicationModel
    private let readLockState: () -> Bool?
    private let makePanels: (() -> [OverlayPanel])?
    private let targetScreenID: String?
    private var scene: EditorSceneModel?
    private var sceneStore: SceneStore?
    private var scenePresentation: ScenePresentationController?
    private var sceneContent: SceneRenderContent?
    private let scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void
    private let distributed = DistributedNotificationCenter.default()
    private var panels: [OverlayPanel] = []
    private var lockSpace: LockScreenSpace?
    private var locked = false
    private var observing = false
    private var testingPanel = false
    private var testGeneration = 0
    private(set) var currentDisplay = CountdownDisplayModel()
    var onEnabledChange: (() -> Void)?
    var onTestWillBegin: (() -> Void)?
    var onTestDidEnd: ((PanelTestCompletion) -> Void)?

    init(model: ApplicationModel, readLockState: @escaping () -> Bool? = readSessionLockState,
         makePanels: (() -> [OverlayPanel])? = nil,
         targetScreenID: String? = NSScreen.main.flatMap(SceneScreenIdentity.identifier),
         scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        self.model = model
        self.readLockState = readLockState
        self.makePanels = makePanels
        self.targetScreenID = targetScreenID
        self.scheduleAfter = scheduleAfter
        super.init()
    }

    func start() {
        guard !observing else { return }
        observing = true
        distributed.addObserver(self, selector: #selector(didLock), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(didUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sessionResigned),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenWake),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        locked = readLockState() ?? false
        updatePanels(at: Date())
    }

    func stop() {
        observing = false
        distributed.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        cancelPanelTest(completion: .discardEditor)
        clearPanels()
    }

    func refresh(at now: Date) {
        currentDisplay = makeCountdownDisplay(event: selectNextEvent(in: model.catalog, now: now), now: now)
        let actual = readLockState() ?? false
        if actual != locked {
            logDiagnostic("lock-poll=\(actual)")
            locked = actual
            cancelPanelTest(completion: locked ? .deferEditor : .restoreEditor)
            updatePanels(at: now)
        }
        renderCountdownPanels()
        for panel in panels where (locked && model.isEnabled) || testingPanel {
            // loginwindow may finish ordering its shield after the lock notification.
            panel.orderFrontRegardless()
        }
    }

    func settingsDidChange() { renderCountdownPanels() }

    /// A committed empty scene is still scene content; nil alone means legacy fallback.
    func sceneDidChange(_ scene: EditorSceneModel?, store: SceneStore) {
        guard self.scene != scene || sceneStore !== store else { return }
        let routeChanged = (self.scene == nil) != (scene == nil)
        self.scene = scene
        if sceneStore !== store {
            sceneStore = store
            scenePresentation = ScenePresentationController(store: store)
        }
        if let scene, let scenePresentation {
            sceneContent = scenePresentation.content(for: scene)
        } else {
            sceneContent = nil
        }
        if routeChanged {
            clearPanels()
            if observing { updatePanels(at: Date()) }
        } else if let sceneContent {
            for panel in panels { (panel.contentView as? SceneDisplayView)?.content = sceneContent }
        }
    }

    @objc func toggleEnabled() {
        model.isEnabled.toggle()
        if !model.isEnabled { cancelPanelTest(completion: locked ? .deferEditor : .restoreEditor) }
        onEnabledChange?()
        updatePanels(at: Date())
    }

    @objc private func didLock() {
        logDiagnostic("lock-notification")
        locked = true
        cancelPanelTest(completion: .deferEditor)
        updatePanels(at: Date())
        for delay in [0.5, 2.0] {
            scheduleAfter(delay) { [weak self] in
                guard let self, self.observing, self.locked, self.model.isEnabled, self.readLockState() == true else { return }
                self.updatePanels(at: Date())
                self.logPanelState()
            }
        }
    }

    @objc private func didUnlock() {
        logDiagnostic("unlock-notification")
        locked = false
        cancelPanelTest(completion: .restoreEditor)
        updatePanels(at: Date())
    }

    @objc private func sessionResigned() {
        logDiagnostic("inactive-notification")
        locked = false
        cancelPanelTest(completion: .deferEditor)
        clearPanels()
    }

    @objc private func screenWake() {
        locked = readLockState() ?? false
        if locked { cancelPanelTest(completion: .deferEditor) }
        else if !testingPanel { onTestDidEnd?(.restoreEditor) }
        updatePanels(at: Date())
    }
    @objc private func screensChanged() { clearPanels(); updatePanels(at: Date()) }

    @objc func testPanel() {
        guard !locked else { return }
        if !testingPanel { onTestWillBegin?() }
        testingPanel = true
        testGeneration += 1
        let generation = testGeneration
        updatePanels(at: Date())
        logPanelState()
        scheduleAfter(8) { [weak self] in
            guard let self, self.testingPanel, self.testGeneration == generation else { return }
            self.cancelPanelTest(completion: self.locked ? .deferEditor : .restoreEditor)
            self.updatePanels(at: Date())
        }
    }

    private func cancelPanelTest(completion: PanelTestCompletion) {
        testGeneration += 1
        testingPanel = false
        onTestDidEnd?(completion)
    }

    private func updatePanels(at now: Date) {
        logDiagnostic("panels: locked=\(locked) enabled=\(model.isEnabled)")
        guard (locked && model.isEnabled) || testingPanel else { clearPanels(); return }
        if panels.isEmpty { panels = createPanels() }
        guard !panels.isEmpty else { return }
        if locked {
            if lockSpace == nil { lockSpace = LockScreenSpace() }
            guard let lockSpace else { logDiagnostic("space: unavailable \(LockScreenSpace.lastFailure)"); clearPanels(); return }
            for panel in panels {
                panel.orderFrontRegardless()
                guard lockSpace.attach(panel) else {
                    logDiagnostic("space: attach-failed \(LockScreenSpace.lastFailure)")
                    clearPanels()
                    return
                }
            }
            logDiagnostic("space: attached panels=\(panels.count)")
        }
        currentDisplay = makeCountdownDisplay(event: selectNextEvent(in: model.catalog, now: now), now: now)
        renderCountdownPanels()
        for panel in panels {
            panel.level = .statusBar
            panel.contentView?.isHidden = false
            panel.contentView?.displayIfNeeded()
            panel.orderFrontRegardless()
        }
    }

    private func renderCountdownPanels() {
        guard scene == nil else { return }
        for panel in panels {
            (panel.contentView as? CountdownView)?.render(makeCountdownPresentation(content: currentDisplay, settings: model.settings))
        }
    }

    private func createPanels() -> [OverlayPanel] {
        let result: [OverlayPanel]
        if let makePanels { result = makePanels() }
        else if scene != nil {
            let screens = NSScreen.screens
            guard let index = SceneScreenIdentity.matchingIndex(target: targetScreenID,
                                                               available: screens.map(SceneScreenIdentity.identifier)) else {
                logDiagnostic("scene-screen: launch display unavailable; no replacement display selected")
                return []
            }
            result = [OverlayPanel(screenFrame: screens[index].frame)]
        } else { result = NSScreen.screens.map { OverlayPanel(screenFrame: $0.frame) } }
        if let sceneContent {
            for panel in result {
                panel.contentView = SceneDisplayView(content: sceneContent)
                panel.contentView?.isHidden = true
            }
        }
        return result
    }

    private func clearPanels() {
        // Remove visible content before dismantling the elevated space.
        panels.forEach { $0.orderOut(nil) }
        lockSpace?.tearDown()
        lockSpace = nil
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    private func logPanelState() {
        for panel in panels {
            let content = panel.contentView is SceneDisplayView ? "scene" : "countdown"
            logDiagnostic("panel: visible=\(panel.isVisible) activeSpace=\(panel.isOnActiveSpace) occlusion=\(panel.occlusionState.rawValue) level=\(panel.level.rawValue) content=\(content) contentSize=\(panel.contentView?.bounds.size ?? .zero) draws=\((panel.contentView as? CountdownView)?.drawCount ?? 0) loginVisible=\(panel.canBecomeVisibleWithoutLogin)")
        }
    }
}
