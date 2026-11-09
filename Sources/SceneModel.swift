import AppKit

enum SceneElementKind: String, Codable { case text, image }

enum SceneError: LocalizedError {
    case invalid(String)
    case storage(String, Error)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .storage(let message, _): return message
        }
    }
}

struct SceneColor: Codable, Equatable {
    var red: Double = 1
    var green: Double = 1
    var blue: Double = 1
    var alpha: Double = 1

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

struct SceneTextStyle: Codable, Equatable {
    var family = "System"
    /// Indices from ultra light (0) through black (8).
    var weight = 3
    var fontSize: Double = 32
    /// Logical points; zero selects the font's natural line height.
    var lineHeight: Double = 0
    /// Percent of font size, matching the typography inspector.
    var letterSpacing: Double = 0
    var horizontalAlignment = 0
    var verticalAlignment = 0
    var color = SceneColor()

    func font(scale: CGFloat) -> NSFont {
        let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let index = min(8, max(0, weight))
        let pointSize = fontSize.isFinite && fontSize > 0 && scale.isFinite && scale > 0 &&
            (fontSize * scale).isFinite ? fontSize * scale : 32
        if family != "System" {
            let managerWeights = [1, 2, 3, 5, 6, 7, 9, 11, 14]
            if let font = NSFontManager.shared.font(withFamily: family, traits: [],
                                                    weight: managerWeights[index], size: pointSize) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: pointSize, weight: weights[index])
    }
}

struct SceneElement: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: SceneElementKind
    var name: String
    var frame: CGRect
    var rotation: Double
    var cornerRadius: Double
    var opacity: Double
    var text: String
    var style: SceneTextStyle
    var assetID: String?
    /// Image placement in element-local, top-left-origin logical points.
    var imageRect: CGRect?

    init(kind: SceneElementKind, frame: CGRect, id: UUID = UUID(), name: String? = nil,
         rotation: Double = 0, cornerRadius: Double = 0, opacity: Double = 1,
         text: String? = nil, style: SceneTextStyle = SceneTextStyle(),
         assetID: String? = nil, imageRect: CGRect? = nil) {
        self.id = id
        self.kind = kind
        self.name = name ?? (kind == .text ? "Текст" : "Изображение")
        self.frame = frame
        self.rotation = rotation
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.text = text ?? (kind == .text ? "Текст" : "")
        self.style = style
        self.assetID = assetID
        self.imageRect = imageRect
    }
}

struct EditorScene: Codable, Equatable {
    static let currentVersion = 1
    var schemaVersion: Int
    var canvasSize: CGSize
    var elements: [SceneElement]

    init(canvasSize: CGSize, elements: [SceneElement] = []) {
        schemaVersion = Self.currentVersion
        self.canvasSize = canvasSize
        self.elements = elements
    }

    func validated() throws -> EditorScene {
        guard schemaVersion == Self.currentVersion else {
            throw SceneError.invalid("Версия документа не поддерживается: \(schemaVersion).")
        }
        guard Self.validSize(canvasSize) else {
            throw SceneError.invalid("Размер холста должен быть конечным положительным числом.")
        }
        var identifiers = Set<UUID>()
        for element in elements {
            guard identifiers.insert(element.id).inserted else {
                throw SceneError.invalid("В документе повторяется идентификатор элемента.")
            }
            guard Self.validRect(element.frame), element.rotation.isFinite,
                  element.cornerRadius.isFinite, element.cornerRadius >= 0,
                  element.opacity.isFinite, (0...1).contains(element.opacity),
                  element.imageRect.map(Self.validRect) ?? true else {
                throw SceneError.invalid("У элемента «\(element.name)» некорректные размеры или параметры отображения.")
            }
            let style = element.style
            guard !style.family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (0...8).contains(style.weight), style.fontSize.isFinite, style.fontSize > 0,
                  style.lineHeight.isFinite, style.lineHeight >= 0,
                  style.letterSpacing.isFinite,
                  (0...2).contains(style.horizontalAlignment), (0...2).contains(style.verticalAlignment),
                  [style.color.red, style.color.green, style.color.blue, style.color.alpha]
                    .allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw SceneError.invalid("У элемента «\(element.name)» некорректный стиль текста.")
            }
            if let assetID = element.assetID, !Self.isSafeAssetID(assetID) {
                throw SceneError.invalid("У изображения некорректный идентификатор файла.")
            }
        }
        return self
    }

    static func isSafeAssetID(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.utf8.count <= 255 &&
            value.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) ||
                (97...122).contains(byte) || byte == 45 || byte == 95 || byte == 46
            }
    }

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func validRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && validSize(rect.size) &&
            (rect.origin.x + rect.size.width).isFinite && (rect.origin.y + rect.size.height).isFinite
    }
}
