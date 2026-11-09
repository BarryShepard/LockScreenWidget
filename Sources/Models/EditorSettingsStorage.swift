import Foundation

// Compatibility contract: keep the key and Codable field names from 258dbbf.
private let editorSettingsStorageKey = "editorSettings.v1"

func loadEditorSettings(from defaults: UserDefaults = .standard) -> EditorSettingsModel {
    if let data = defaults.data(forKey: editorSettingsStorageKey),
       let settings = try? JSONDecoder().decode(EditorSettingsModel.self, from: data) {
        return validateEditorSettings(settings)
    }
    var settings = EditorSettingsModel()
    if let old = defaults.array(forKey: "elementOffsets") as? [Double], old.count == 4, old.allSatisfy(\.isFinite) {
        settings.offsets = old + [0, 0]
    }
    return settings
}

func saveEditorSettings(_ settings: EditorSettingsModel, to defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: editorSettingsStorageKey) }
}
