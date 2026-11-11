import AppKit

func makeCountdownPresentation(content: CountdownDisplayModel, settings: EditorSettingsModel) -> CountdownPresentation {
    let texts = [content.title, content.counter, content.information]
    let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
    let managerWeights = [1, 2, 3, 5, 6, 7, 9, 11, 14]
    let alignments: [NSTextAlignment] = [.left, .center, .right]
    let blocks = visibleBlockIndices(in: settings).map { index in
        let style = settings.typography[index]
        // A period is a label, never a fabricated ticking deadline.
        let size = index == 1 && !content.usesCountdown ? min(style.size, 42) : style.size
        let typography = TypographyPresentation(
            family: style.family, weight: weights[style.weight], managerWeight: managerWeights[style.weight],
            size: CGFloat(size), lineHeight: CGFloat(style.lineHeight),
            letterSpacing: CGFloat(style.spacing / 100 * size), alignment: alignments[style.alignment],
            verticalAlignment: CGFloat(style.verticalAlignment) / 2,
            usesMonospacedDigits: index == 1 && content.usesCountdown)
        return CountdownPresentation.Block(text: texts[index], typography: typography,
            offset: NSPoint(x: settings.offsets[index * 2], y: settings.offsets[index * 2 + 1]))
    }
    return CountdownPresentation(blocks: blocks)
}

func makeTypographyInspectorPresentation(settings: EditorSettingsModel, selectedIndices: Set<Int>,
                                         fallbackBlockIndex: Int) -> TypographyInspectorPresentation {
    let requestedIndex = selectedIndices.min() ?? fallbackBlockIndex
    let index = visibleBlockIndices(in: settings).contains(requestedIndex) ? requestedIndex : 0
    let style = settings.typography[index]
    let selectionText = selectedIndices.isEmpty ? "Выберите блок на холсте" :
        (selectedIndices.count == 1 ? "Настройки выбранного блока" :
            "Выбрано блоков: \(selectedIndices.count). Меняется только выбранное свойство.")
    return TypographyInspectorPresentation(selectedBlockIndex: index,
        isInformationVisible: settings.showInformation, selectionText: selectionText,
        family: style.family, weightIndex: style.weight,
        sizeText: String(format: "%g", style.size),
        lineHeightText: style.lineHeight == 0 ? "" : String(format: "%g", style.lineHeight),
        spacingText: String(format: "%g", style.spacing),
        horizontalAlignmentIndex: style.alignment, verticalAlignmentIndex: style.verticalAlignment,
        areControlsEnabled: !selectedIndices.isEmpty)
}
