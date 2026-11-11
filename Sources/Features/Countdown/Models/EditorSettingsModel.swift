import Foundation

struct EditorSettingsModel: Codable, Equatable {
    var typography = [BlockTypographyModel(size: 26), BlockTypographyModel(size: 112, spacing: -2),
                      BlockTypographyModel(weight: 3, size: 17)]
    var offsets: [Double] = [0, 0, 0, 0, 0, 0]
    var showInformation = false
}
