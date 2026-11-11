import AppKit

/// Immutable display inputs; event selection and settings interpretation belong to controllers.
struct CountdownPresentation {
    struct Block {
        let text: String
        let typography: TypographyPresentation
        let offset: NSPoint
    }

    let blocks: [Block]
}

struct TypographyPresentation {
    let family: String
    let weight: NSFont.Weight
    let managerWeight: Int
    let size: CGFloat
    let lineHeight: CGFloat
    let letterSpacing: CGFloat
    let alignment: NSTextAlignment
    /// Fraction of spare text-box height above the text, from zero to one.
    let verticalAlignment: CGFloat
    let usesMonospacedDigits: Bool
}

struct TypographyInspectorPresentation {
    let selectedBlockIndex: Int
    let isInformationVisible: Bool
    let selectionText: String
    let family: String
    let weightIndex: Int
    let sizeText: String
    let lineHeightText: String
    let spacingText: String
    let horizontalAlignmentIndex: Int
    let verticalAlignmentIndex: Int
    let areControlsEnabled: Bool
}
