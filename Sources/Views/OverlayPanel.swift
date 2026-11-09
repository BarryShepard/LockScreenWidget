import AppKit

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(screen: NSScreen) {
        self.init(contentRect: CountdownView.overlayFrame(in: screen.frame),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
        canBecomeVisibleWithoutLogin = true
        title = "Отсчёт — прозрачная панель"
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = CountdownView(overlay: true)
        contentView?.isHidden = true
    }
}
