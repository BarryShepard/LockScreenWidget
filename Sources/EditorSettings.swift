import AppKit

struct BlockTypography: Codable, Equatable {
    var family = "System"
    var weight = 6
    var size: Double
    /// Logical screen points; zero uses the font's natural line height.
    var lineHeight: Double = 0
    /// Percent of font size, matching typography editors.
    var spacing: Double = 0
    var alignment = 1
    var verticalAlignment = 0

    func font(scale: CGFloat, digits: Bool) -> NSFont {
        let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let pointSize = size * scale
        let base: NSFont
        if family == "System" {
            base = digits ? NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: weights[weight])
                          : NSFont.systemFont(ofSize: pointSize, weight: weights[weight])
        } else {
            let managerWeights = [1, 2, 3, 5, 6, 7, 9, 11, 14]
            base = NSFontManager.shared.font(withFamily: family, traits: [], weight: managerWeights[weight], size: pointSize)
                ?? NSFont.systemFont(ofSize: pointSize, weight: weights[weight])
        }
        guard digits else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: 6,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: 0]]
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? base
    }

    mutating func validate() {
        if family.isEmpty { family = "System" }
        weight = min(8, max(0, weight))
        size = size.isFinite ? min(400, max(6, size)) : 26
        lineHeight = lineHeight.isFinite ? min(600, max(0, lineHeight)) : 0
        spacing = spacing.isFinite ? min(100, max(-20, spacing)) : 0
        alignment = min(2, max(0, alignment))
        verticalAlignment = min(2, max(0, verticalAlignment))
    }
}

struct EditorSettings: Codable, Equatable {
    static let storageKey = "editorSettings.v1"
    var typography = [BlockTypography(size: 26), BlockTypography(size: 112, spacing: -2),
                      BlockTypography(weight: 3, size: 17)]
    var offsets: [Double] = [0, 0, 0, 0, 0, 0]
    var showInformation = false

    var visibleIndices: [Int] { showInformation ? [0, 1, 2] : [0, 1] }

    mutating func validate() {
        let defaults = EditorSettings()
        if typography.count != 3 { typography = defaults.typography }
        for index in typography.indices { typography[index].validate() }
        if offsets.count != 6 || offsets.contains(where: { !$0.isFinite }) { offsets = defaults.offsets }
    }

    static func load(from defaults: UserDefaults = .standard) -> EditorSettings {
        if let data = defaults.data(forKey: storageKey), var settings = try? JSONDecoder().decode(Self.self, from: data) {
            settings.validate()
            return settings
        }
        var settings = EditorSettings()
        if let old = defaults.array(forKey: "elementOffsets") as? [Double], old.count == 4, old.allSatisfy(\.isFinite) {
            settings.offsets = old + [0, 0]
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}
