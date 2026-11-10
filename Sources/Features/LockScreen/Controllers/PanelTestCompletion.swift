import AppKit

/// Instructions for restoring the editor after a temporary panel test.
enum PanelTestCompletion: Equatable {
    case restoreEditor
    case deferEditor
    case discardEditor
}

/// A deferred completion retains visibility intent across a secure-lock transition.
struct PanelTestWindowRestoration {
    private var restore = false

    mutating func hide(_ window: NSWindow?) {
        restore = window?.isVisible == true
        window?.orderOut(nil)
    }

    mutating func finish(_ completion: PanelTestCompletion, window: NSWindow?) {
        switch completion {
        case .restoreEditor:
            if restore { window?.makeKeyAndOrderFront(nil) }
            restore = false
        case .deferEditor: break
        case .discardEditor: restore = false
        }
    }
}
