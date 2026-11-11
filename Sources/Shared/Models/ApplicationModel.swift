import Foundation

/// Shared current data. Controllers are responsible for updating these values.
final class ApplicationModel {
    var catalog: EventCatalogModel
    var settings: EditorSettingsModel
    var isEnabled = true

    init(catalog: EventCatalogModel, settings: EditorSettingsModel) {
        self.catalog = catalog
        self.settings = settings
    }
}
