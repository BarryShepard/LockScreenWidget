import AppKit

enum SceneCanvasTool: Int, CaseIterable {
    case text, note, image, countdown, clock

    var title: String {
        switch self {
        case .text: return "Текст"
        case .note: return "Заметка"
        case .image: return "Картинка…"
        case .countdown: return "Таймер"
        case .clock: return "Часы"
        }
    }
    var instruction: String {
        self == .text ? "Щёлкните или протяните рамку для текста · Escape — отмена" :
            "Щёлкните для размещения: \(title) · Escape — отмена"
    }
}

struct SceneCanvasMenuItem {
    var title: String
    var action: SceneCanvasAction? = nil
    var enabled = true
    var children: [SceneCanvasMenuItem] = []
}

extension SceneCanvasView {
    func makeContextMenu(_ items: [SceneCanvasMenuItem]) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        for item in items {
            if item.title.isEmpty { menu.addItem(.separator()); continue }
            let native = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            native.isEnabled = item.enabled
            if !item.children.isEmpty { native.submenu = makeContextMenu(item.children) }
            if let action = item.action {
                native.action = #selector(contextAction(_:)); native.target = self; native.representedObject = action
            }
            menu.addItem(native)
        }
        return menu
    }

    @objc private func contextAction(_ item: NSMenuItem) {
        guard item.isEnabled, let action = item.representedObject as? SceneCanvasAction else { return }
        onAction?(action)
    }
}
