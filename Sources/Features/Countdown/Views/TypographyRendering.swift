import AppKit

func makeTypographyFont(_ typography: BlockTypographyModel, scale: CGFloat, digits: Bool) -> NSFont {
    let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
    let pointSize = typography.size * scale
    let base: NSFont
    if typography.family == "System" {
        base = digits ? NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: weights[typography.weight])
                      : NSFont.systemFont(ofSize: pointSize, weight: weights[typography.weight])
    } else {
        let managerWeights = [1, 2, 3, 5, 6, 7, 9, 11, 14]
        base = NSFontManager.shared.font(withFamily: typography.family, traits: [], weight: managerWeights[typography.weight], size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize, weight: weights[typography.weight])
    }
    guard digits else { return base }
    let descriptor = base.fontDescriptor.addingAttributes([
        .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: 6,
                            NSFontDescriptor.FeatureKey.selectorIdentifier: 0]]
    ])
    return NSFont(descriptor: descriptor, size: pointSize) ?? base
}
