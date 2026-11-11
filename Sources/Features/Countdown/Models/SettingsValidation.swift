import Foundation

func visibleBlockIndices(in settings: EditorSettingsModel) -> [Int] {
    settings.showInformation ? [0, 1, 2] : [0, 1]
}

func validateFontSize(_ value: Double) -> Double {
    value.isFinite ? min(400, max(6, value)) : 26
}

func validateBlockTypography(_ value: BlockTypographyModel) -> BlockTypographyModel {
    var valid = value
    if valid.family.isEmpty { valid.family = "System" }
    valid.weight = min(8, max(0, valid.weight))
    valid.size = validateFontSize(valid.size)
    valid.lineHeight = valid.lineHeight.isFinite ? min(600, max(0, valid.lineHeight)) : 0
    valid.spacing = valid.spacing.isFinite ? min(100, max(-20, valid.spacing)) : 0
    valid.alignment = min(2, max(0, valid.alignment))
    valid.verticalAlignment = min(2, max(0, valid.verticalAlignment))
    return valid
}

func validateEditorSettings(_ value: EditorSettingsModel) -> EditorSettingsModel {
    var valid = value
    let defaults = EditorSettingsModel()
    if valid.typography.count != 3 { valid.typography = defaults.typography }
    valid.typography = valid.typography.map(validateBlockTypography)
    if valid.offsets.count != 6 || valid.offsets.contains(where: { !$0.isFinite }) { valid.offsets = defaults.offsets }
    return valid
}

func parseTypographyNumber(_ value: String, allowsAutomatic: Bool = false) -> Double? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if allowsAutomatic, ["", "авто", "auto"].contains(text) { return 0 }
    guard let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite else { return nil }
    return number
}
