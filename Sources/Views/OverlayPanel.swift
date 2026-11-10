import AppKit

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(screenFrame: NSRect) {
        let target = CountdownView.overlayFrame(in: screenFrame)
        self.init(contentRect: NSRect(origin: .zero, size: target.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // setFrame uses global screen coordinates, including displays left of or above the main one.
        setFrame(target, display: false)
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
