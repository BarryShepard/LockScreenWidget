import AppKit

if CommandLine.arguments.contains("--probe-space") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.ignoresMouseEvents = true
    panel.canBecomeVisibleWithoutLogin = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    let control = OverlayPanel(contentRect: panel.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    control.isReleasedWhenClosed = false
    control.ignoresMouseEvents = true
    control.isOpaque = false
    control.backgroundColor = .clear
    control.hasShadow = false
    control.level = .screenSaver
    control.orderFrontRegardless()
    panel.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    func targetAboveControl() -> Bool {
        let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let ids = list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
        guard let targetIndex = ids.firstIndex(of: panel.windowNumber),
              let controlIndex = ids.firstIndex(of: control.windowNumber) else { print("probeWindowsMissing=true"); return false }
        print("probeIndices: target=\(targetIndex) control=\(controlIndex)")
        return targetIndex < controlIndex
    }
    print("aboveControlBefore=\(targetAboveControl())")
    let space = LockScreenSpace()
    print("spaceCreated=\(space != nil)")
    print("spaceFailure=\(LockScreenSpace.lastFailure)")
    print("attachIssued=\(space?.attach(panel) ?? false)")
    panel.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    print("aboveControlAfter=\(targetAboveControl())")
    print("attachFailure=\(LockScreenSpace.lastFailure)")
    // The probe window has no visible content and ignores input.
    panel.orderOut(nil)
    space?.tearDown()
    panel.close()
    control.orderOut(nil)
    control.close()
    print("spaceCleanupIssued=\(space != nil)")
} else if CommandLine.arguments.contains("--diagnose") {
    let url = Bundle.main.url(forResource: "events", withExtension: "json")!
    let events = try EventCatalog.load(url)
    print("events=\(events.count)")
    print("font=\(AppFont.font(20).fontName)")
    if let next = EventCatalog.next(in: events, now: Date()) {
        print("next=\(next.id) countdown=\(Countdown.string(until: next.target, now: Date()))")
    }
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    let hasLockKey = session?["CGSSessionScreenIsLocked"] != nil
    print("lockStateKeyPresent=\(hasLockKey)")
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
