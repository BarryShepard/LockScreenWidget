/// Instructions for restoring the editor after a temporary panel test.
enum PanelTestCompletion: Equatable {
    case restoreEditor
    case deferEditor
    case discardEditor
}
