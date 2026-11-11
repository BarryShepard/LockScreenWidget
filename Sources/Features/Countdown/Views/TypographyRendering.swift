import AppKit

func makeTypographyFont(_ typography: TypographyPresentation, scale: CGFloat) -> NSFont {
    let pointSize = typography.size * scale
    let base: NSFont
    if typography.family == "System" {
        base = typography.usesMonospacedDigits ? NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: typography.weight)
                                              : NSFont.systemFont(ofSize: pointSize, weight: typography.weight)
    } else {
        base = NSFontManager.shared.font(withFamily: typography.family, traits: [], weight: typography.managerWeight, size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize, weight: typography.weight)
    }
    guard typography.usesMonospacedDigits else { return base }
    let descriptor = base.fontDescriptor.addingAttributes([
        .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: 6,
                            NSFontDescriptor.FeatureKey.selectorIdentifier: 0]]
    ])
    return NSFont(descriptor: descriptor, size: pointSize) ?? base
}
