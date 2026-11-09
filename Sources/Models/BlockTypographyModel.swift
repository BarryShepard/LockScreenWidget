import Foundation

struct BlockTypographyModel: Codable, Equatable {
    var family = "System"
    var weight = 6
    var size: Double
    /// Logical screen points; zero uses the font's natural line height.
    var lineHeight: Double = 0
    /// Percent of font size, matching typography editors.
    var spacing: Double = 0
    var alignment = 1
    var verticalAlignment = 0
}
