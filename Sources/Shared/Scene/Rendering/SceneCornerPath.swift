import CoreGraphics
import SwiftUI

/// The system's continuous corner shape, shared by scene rendering and text editing.
enum SceneCornerPath {
    static func path(in rect: CGRect, radius: CGFloat) -> CGPath {
        let limited = radius.isFinite ? max(0, min(radius, rect.width/2, rect.height/2)) : 0
        guard limited > 0 else { return CGPath(rect: rect, transform: nil) }
        return RoundedRectangle(cornerRadius: limited, style: .continuous).path(in: rect).cgPath
    }
}
