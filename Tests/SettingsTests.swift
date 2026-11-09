import Foundation

@main struct SettingsTests {
    static func main() throws {
        let preferences = MemoryPreferences()
        preferences.set([0.1, 0.2, 0.3, 0.4], forKey: "elementOffsets")
        assert(loadEditorSettings(from: preferences).offsets == [0.1, 0.2, 0.3, 0.4, 0, 0])

        // Literal pre-refactor payload: renaming Swift types must not rename JSON keys.
        let oldJSON = #"{"typography":[{"family":"Helvetica Neue","weight":3,"size":38,"lineHeight":50,"spacing":5,"alignment":0,"verticalAlignment":2},{"family":"System","weight":6,"size":112,"lineHeight":0,"spacing":-2,"alignment":1,"verticalAlignment":0},{"family":"System","weight":3,"size":17,"lineHeight":0,"spacing":0,"alignment":1,"verticalAlignment":0}],"offsets":[0.05,0.1,0,0,-0.1,0.2],"showInformation":true}"#
        preferences.set(Data(oldJSON.utf8), forKey: "editorSettings.v1")
        let loaded = loadEditorSettings(from: preferences)
        assert(loaded.typography[0].family == "Helvetica Neue")
        assert(loaded.typography[0].size == 38 && loaded.typography[0].verticalAlignment == 2)
        assert(loaded.typography[1].size == 112 && loaded.showInformation)
        assert(loaded.offsets == [0.05, 0.1, 0, 0, -0.1, 0.2])
        saveEditorSettings(loaded, to: preferences)
        assert(loadEditorSettings(from: preferences) == loaded)
        let encoded = try JSONSerialization.jsonObject(with: preferences.data(forKey: "editorSettings.v1")!) as! NSDictionary
        let original = try JSONSerialization.jsonObject(with: Data(oldJSON.utf8)) as! NSDictionary
        assert(encoded == original, "Saving must preserve the v1 JSON format")

        let invalid = BlockTypographyModel(family: "", weight: 99, size: -.infinity,
            lineHeight: -.infinity, spacing: .nan, alignment: -1, verticalAlignment: 99)
        let valid = validateBlockTypography(invalid)
        assert(valid.family == "System" && valid.weight == 8 && valid.size == 26)
        assert(valid.lineHeight == 0 && valid.spacing == 0 && valid.alignment == 0 && valid.verticalAlignment == 2)
        assert(invalid.family.isEmpty, "Validation returns a value without mutating its input")
        let clamped = validateBlockTypography(BlockTypographyModel(size: -100, lineHeight: -1, spacing: 500, alignment: 9))
        assert(clamped.size == 6 && clamped.lineHeight == 0 && clamped.spacing == 100 && clamped.alignment == 2)
        var malformed = EditorSettingsModel()
        malformed.typography = []
        malformed.offsets = [.nan]
        assert(validateEditorSettings(malformed) == EditorSettingsModel())
        preferences.set(Data("invalid JSON".utf8), forKey: "editorSettings.v1")
        assert(loadEditorSettings(from: preferences).offsets == [0.1, 0.2, 0.3, 0.4, 0, 0])
        preferences.set([Double.infinity, 0, 0, 0], forKey: "elementOffsets")
        assert(loadEditorSettings(from: preferences) == EditorSettingsModel())
        assert(parseTypographyNumber(" 12,5 ") == 12.5)
        assert(parseTypographyNumber("Авто", allowsAutomatic: true) == 0)
        assert(parseTypographyNumber("", allowsAutomatic: true) == 0)
        assert(parseTypographyNumber("-", allowsAutomatic: false) == nil)
        assert(parseTypographyNumber("nan") == nil)
        print("Settings checks passed: v1 compatibility, legacy migration, round-trip, validation and numeric input.")
    }
}
