import AppKit
import CoreGraphics

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var events: [ApocalypseEvent] = []
    private var preview: NSWindow?
    private var previewView = CountdownView(overlay: false)
    private var panels: [OverlayPanel] = []
    private var statusItem: NSStatusItem?
    private var inspector: TypographyInspector?
    private var eventPicker: NSPopUpButton?
    private var enabledButton: NSButton?
    private var enabledMenu: NSMenuItem?
    private var tick: Timer?
    private var locked = false
    private var enabled = true
    private var testingPanel = false
    private var lockSpace: LockScreenSpace?
    private let distributed = DistributedNotificationCenter.default()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("launch")
        do {
            guard let url = Bundle.main.url(forResource: "events", withExtension: "json") else {
                throw NSError(domain: "TEotW", code: 1, userInfo: [NSLocalizedDescriptionKey: "Файл событий не найден."])
            }
            events = try EventCatalog.load(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось открыть каталог"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        makeMenu()
        distributed.addObserver(self, selector: #selector(didLock), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(didUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didUnlock),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        tick = Timer(timeInterval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(tick!, forMode: .common)
        locked = readLockState() ?? false
        updatePanels()
        showPreview()
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tick?.invalidate()
        distributed.removeObserver(self)
        panels.forEach { $0.orderOut(nil) }
        lockSpace?.tearDown()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func makeMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        main.addItem(app)
        app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "Завершить", action: #selector(quit), keyEquivalent: "q").target = self
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = StatusIcon.skull()
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.toolTip = "Следующий конец света"
        let menu = NSMenu()
        enabledMenu = menu.addItem(withTitle: "Показывать при блокировке", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledMenu?.target = self
        enabledMenu?.state = .on
        menu.addItem(withTitle: "Открыть предпросмотр", action: #selector(showPreview), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Проверить прозрачную панель (8 секунд)", action: #selector(testPanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Открыть источник", action: #selector(openSource), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Завершить", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem?.menu = menu
    }

    @objc private func showPreview() {
        if preview == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Следующий конец света — редактор"
            window.appearance = NSAppearance(named: .darkAqua)
            window.minSize = NSSize(width: 1120, height: 760)
            window.isReleasedWhenClosed = false
            let container = NSView()
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(white: 0.055, alpha: 1).cgColor
            window.contentView = container
            previewView.previewScreenSize = NSScreen.main?.frame.size ?? NSSize(width: 1512, height: 982)
            previewView.onLayoutChange = { [weak self] in
                self?.panels.forEach { ($0.contentView as? CountdownView)?.reloadPositions() }
            }
            previewView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(previewView)
            let inspector = TypographyInspector(canvas: previewView)
            self.inspector = inspector
            container.addSubview(inspector)
            previewView.onSelectionChange = { [weak inspector] in inspector?.refresh() }
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(separator)
            let controls = NSStackView()
            controls.orientation = .vertical
            controls.alignment = .leading
            controls.spacing = 10
            controls.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(controls)
            let row = NSStackView()
            row.spacing = 16
            let picker = NSPopUpButton()
            picker.addItem(withTitle: "Ближайшее событие")
            for event in events { picker.addItem(withTitle: "\(event.date) · \(event.title)") }
            picker.target = self
            picker.action = #selector(refresh)
            picker.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true
            eventPicker = picker
            row.addArrangedSubview(picker)
            let button = NSButton(checkboxWithTitle: "Показывать при блокировке", target: self, action: #selector(toggleEnabled))
            button.state = .on
            enabledButton = button
            row.addArrangedSubview(button)
            controls.addArrangedSubview(row)
            let test = NSButton(title: "Проверить прозрачную панель (8 секунд)", target: self, action: #selector(testPanel))
            let actions = NSStackView()
            actions.spacing = 16
            actions.addArrangedSubview(test)
            actions.addArrangedSubview(NSButton(title: "Сбросить расположение", target: self, action: #selector(resetLayout)))
            controls.addArrangedSubview(actions)
            let help = NSTextField(wrappingLabelWithString: "Перетаскивайте блоки; Shift — движение по оси. Выделяйте группу рамкой с пустого места или добавляйте блоки с Shift. Положение сохраняется автоматически.")
            help.textColor = NSColor(white: 0.75, alpha: 1)
            help.font = .systemFont(ofSize: 12)
            controls.addArrangedSubview(help)
            let convention = NSTextField(wrappingLabelWithString: "Час в источниках не задан: считаем до 00:00 по Москве. Выбор выше меняет только предпросмотр; при блокировке показывается ближайшее событие.")
            convention.textColor = NSColor(white: 0.55, alpha: 1)
            convention.font = .systemFont(ofSize: 11)
            controls.addArrangedSubview(convention)
            NSLayoutConstraint.activate([
                previewView.topAnchor.constraint(equalTo: container.topAnchor),
                previewView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: separator.leadingAnchor),
                separator.topAnchor.constraint(equalTo: container.topAnchor),
                separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1),
                separator.trailingAnchor.constraint(equalTo: inspector.leadingAnchor),
                inspector.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                inspector.topAnchor.constraint(equalTo: container.topAnchor),
                inspector.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                inspector.widthAnchor.constraint(equalToConstant: 332),
                previewView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -8),
                controls.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
                controls.trailingAnchor.constraint(equalTo: separator.leadingAnchor, constant: -28),
                controls.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
            ])
            window.center()
            preview = window
            previewView.selectBlock(0)
        }
        NSApp.activate(ignoringOtherApps: true)
        preview?.makeKeyAndOrderFront(nil)
        refresh()
    }

    @objc private func resetLayout() { previewView.resetPositions() }

    @objc private func toggleEnabled() {
        enabled.toggle()
        enabledButton?.state = enabled ? .on : .off
        enabledMenu?.state = enabled ? .on : .off
        updatePanels()
    }

    @objc private func refresh() {
        let now = Date()
        let index = eventPicker?.indexOfSelectedItem ?? 0
        previewView.event = index > 0 && index <= events.count ? events[index - 1] : EventCatalog.next(in: events, now: now)
        previewView.now = now
        let actual = readLockState() ?? false
        if actual != locked {
            log("lock-poll=\(actual)")
            locked = actual
            updatePanels()
        }
        for panel in panels {
            if let view = panel.contentView as? CountdownView {
                view.event = EventCatalog.next(in: events, now: now)
                view.now = now
            }
            // loginwindow may finish ordering its shield after the lock notification.
            if (locked && enabled) || testingPanel { panel.orderFrontRegardless() }
        }
    }

    private func readLockState() -> Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        // The dictionary key is undocumented. Fail closed unless the session is ours and active.
        guard let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool, onConsole else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    @objc private func didLock() {
        log("lock-notification")
        testingPanel = false
        locked = true
        updatePanels()
        for delay in [0.5, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.locked, self.enabled, self.readLockState() == true else { return }
                self.updatePanels()
                self.logPanelState()
            }
        }
    }
    @objc private func didUnlock() { log("unlock-or-inactive-notification"); locked = false; updatePanels() }
    @objc private func screenWake() { locked = readLockState() ?? false; updatePanels() }
    @objc private func screensChanged() { clearPanels(); updatePanels() }

    @objc private func testPanel() {
        guard !locked else { return }
        testingPanel = true
        let restorePreview = preview?.isVisible == true
        preview?.orderOut(nil)
        updatePanels()
        logPanelState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            self.testingPanel = false
            self.updatePanels()
            if restorePreview && !self.locked { self.preview?.makeKeyAndOrderFront(nil) }
        }
    }

    private func updatePanels() {
        log("panels: locked=\(locked) enabled=\(enabled)")
        let show = (locked && enabled) || testingPanel
        guard show else { clearPanels(); return }
        preparePanels()
        if locked {
            if lockSpace == nil { lockSpace = LockScreenSpace() }
            guard let lockSpace else { log("space: unavailable \(LockScreenSpace.lastFailure)"); clearPanels(); return }
            for panel in panels {
                panel.orderFrontRegardless()
                guard lockSpace.attach(panel) else { log("space: attach-failed \(LockScreenSpace.lastFailure)"); clearPanels(); return }
            }
            log("space: attached panels=\(panels.count)")
        }
        let event = EventCatalog.next(in: events, now: Date())
        for panel in panels {
            panel.level = .statusBar
            panel.contentView?.isHidden = false
            (panel.contentView as? CountdownView)?.event = event
            (panel.contentView as? CountdownView)?.now = Date()
            panel.contentView?.display()
            panel.orderFrontRegardless()
        }
    }

    private func clearPanels() {
        // Remove visible content before dismantling the elevated space.
        panels.forEach { $0.orderOut(nil) }
        lockSpace?.tearDown()
        lockSpace = nil
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    private func preparePanels() {
        if panels.isEmpty {
            for screen in NSScreen.screens {
                // The system clock is disabled in Lock Screen settings; keep authentication clear below.
                let rect = CountdownView.overlayFrame(in: screen.frame)
                let panel = OverlayPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false, screen: screen)
                panel.canBecomeVisibleWithoutLogin = true
                panel.title = "Отсчёт — прозрачная панель"
                panel.level = .statusBar
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.animationBehavior = .none
                panel.contentView = CountdownView(overlay: true)
                panel.contentView?.isHidden = true
                panels.append(panel)
            }
        }
    }

    private func logPanelState() {
        for panel in panels {
            log("panel: visible=\(panel.isVisible) activeSpace=\(panel.isOnActiveSpace) occlusion=\(panel.occlusionState.rawValue) level=\(panel.level.rawValue) contentSize=\(panel.contentView?.bounds.size ?? .zero) draws=\((panel.contentView as? CountdownView)?.drawCount ?? 0) loginVisible=\(panel.canBecomeVisibleWithoutLogin)")
        }
    }

    @objc private func openSource() {
        if let event = EventCatalog.next(in: events, now: Date()) { NSWorkspace.shared.open(event.sourceURL) }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func log(_ message: String) {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("TEotW-diagnostics.log")
        let data = Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8)
        if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url); return }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data) } catch { }
    }
}
