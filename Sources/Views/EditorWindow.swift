import AppKit

final class EditorWindow: NSWindow {
    convenience init(content: EditorView) {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        title = "Следующий конец света — редактор"
        appearance = NSAppearance(named: .darkAqua)
        minSize = NSSize(width: 1120, height: 760)
        isReleasedWhenClosed = false
        contentView = content
        center()
    }
}
