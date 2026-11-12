import AppKit

/// Converts document typography to AppKit values and applies text sizing rules.
enum SceneTextLayout {
    static func font(_ style: SceneTextStyleModel, scale: CGFloat = 1) -> NSFont {
        let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let index = min(8, max(0, style.weight))
        let pointSize = style.fontSize.isFinite && style.fontSize > 0 && scale.isFinite && scale > 0 &&
            (style.fontSize * scale).isFinite ? style.fontSize * scale : 32
        if style.family != "System" {
            let managerWeights = [1, 2, 3, 5, 6, 7, 9, 11, 14]
            if let font = NSFontManager.shared.font(withFamily: style.family, traits: [],
                                                    weight: managerWeights[index], size: pointSize) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: pointSize, weight: weights[index])
    }

    static func color(_ color: SceneColor) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    static func attributes(_ style: SceneTextStyleModel, scale: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.alignment = [NSTextAlignment.left, .center, .right][style.horizontalAlignment]
        p.lineBreakMode = .byWordWrapping
        if style.lineHeight > 0 { p.minimumLineHeight = style.lineHeight*scale; p.maximumLineHeight = p.minimumLineHeight }
        return [.font: font(style, scale: scale), .foregroundColor: color(style.color), .paragraphStyle: p,
                .kern: style.letterSpacing/100 * style.fontSize * scale]
    }

    static func measure(_ e: SceneElementModel, width: CGFloat) -> CGSize {
        // A trailing newline owns a real empty line while the insertion point is there.
        let content = (e.text.isEmpty || e.text.hasSuffix("\n")) ? e.text + "\u{200B}" : e.text
        let s = NSAttributedString(string: content, attributes: attributes(e.style))
        let r = s.boundingRect(with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }

    static func fit(_ e: inout SceneElementModel, minimumHeight: CGFloat = 1) {
        guard e.kind != .note else { return }
        let auto = e.autoTextWidth == true
        let sx = e.textScaleX ?? 1, sy = e.textScaleY ?? 1
        if auto { e.frame.size.width = max(28 * sx, (measure(e, width: .greatestFiniteMagnitude).width + 2) * sx) }
        e.frame.size.height = max(minimumHeight, measure(e, width: e.frame.width / sx).height * sy)
    }

    static func contentRect(_ e: SceneElementModel) -> CGRect {
        let p = e.kind == .note ? e.resolvedNote.padding : 0
        return CGRect(x: p, y: p, width: max(0, e.frame.width - 2*p), height: max(0, e.frame.height - 2*p))
    }

    static func overflows(_ e: SceneElementModel) -> Bool {
        let rect = contentRect(e)
        return rect.width <= 0 || measure(e, width: rect.width).height > rect.height
    }

    static func yOffset(_ e: SceneElementModel) -> CGFloat {
        if e.kind == .note {
            let rect = contentRect(e)
            let free = max(0, rect.height - measure(e, width: rect.width).height)
            return rect.minY + [0, free/2, free][e.style.verticalAlignment]
        }
        let sy = e.textScaleY ?? 1
        let free = max(0, e.frame.height / sy - measure(e, width: e.frame.width / (e.textScaleX ?? 1)).height)
        return [0, free/2, free][e.style.verticalAlignment]
    }
}
