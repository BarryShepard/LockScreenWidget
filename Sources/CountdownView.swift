import AppKit
import CoreText

enum AppFont {
    static var family = "Helvetica Neue"

    static func register(url: URL? = Bundle.main.url(forResource: "Manrope", withExtension: "ttf", subdirectory: "Fonts")) {
        guard let url = url else { return }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            family = "Manrope"
        }
    }

    static func font(_ size: CGFloat, digits: Bool = false) -> NSFont {
        let base = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
        guard digits else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

final class CountdownView: NSView {
    struct TextRun {
        let text: String
        let attributes: [NSAttributedString.Key: Any]
        let frame: NSRect
    }
    var event: ApocalypseEvent? { didSet { needsDisplay = true } }
    var now = Date() { didSet { needsDisplay = true } }
    let isOverlay: Bool
    private(set) var drawCount = 0

    init(overlay: Bool) {
        isOverlay = overlay
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        if !isOverlay {
            NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
            bounds.fill()
        }
        for run in layout(in: bounds) {
            (run.text as NSString).draw(with: run.frame, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: run.attributes)
        }
    }

    func layout(in bounds: NSRect) -> [TextRun] {
        var scale = min(1.35, bounds.width / 1000, bounds.height / 390)
        var runs = makeRuns(in: bounds, scale: scale)
        while runs.contains(where: { $0.frame.maxY > bounds.height - 8 }) && scale > 0.4 {
            scale *= 0.94
            runs = makeRuns(in: bounds, scale: scale)
        }
        return runs
    }

    private func makeRuns(in bounds: NSRect, scale: CGFloat) -> [TextRun] {
        let width = bounds.width
        let availableWidth = max(100, width - 64 * scale)
        let title = event?.title.uppercased(with: Locale(identifier: "ru_RU")) ?? "НОВЫХ ПРЕДСКАЗАНИЙ ПОКА НЕТ"
        let timer = event.map { Countdown.string(until: $0.target, now: now) } ?? "00:00:00"
        let explanation = event?.explanation ?? "Все назначенные даты прошли.\nПланета продолжает работу."
        let source = event?.source ?? "Каталог ожидает следующую дату"

        var timerSize: CGFloat = 112 * scale
        while (timer as NSString).size(withAttributes: [.font: AppFont.font(timerSize, digits: true),
                                                       .kern: -0.045 * timerSize]).width > availableWidth && timerSize > 28 {
            timerSize -= 1
        }
        let titleStyle = style(size: 18 * scale, color: .white, kern: 18 * scale * 0.06)
        let timerStyle = style(size: timerSize, color: .white, kern: -0.045 * timerSize, digits: true)
        let explanationStyle = style(size: 17 * scale, color: NSColor(white: 0.88, alpha: 1), lineSpacing: 5 * scale)
        let sourceStyle = style(size: 12 * scale, color: NSColor(white: 0.68, alpha: 1))
        let textWidth = min(availableWidth, 810 * scale)
        let items: [(String, [NSAttributedString.Key: Any], CGFloat, CGFloat)] = [
            (title, titleStyle, textWidth, 15 * scale),
            (timer, timerStyle, availableWidth, 25 * scale),
            (explanation, explanationStyle, textWidth, 16 * scale),
            (source, sourceStyle, textWidth, 0)
        ]
        let heights = items.map { textHeight($0.0, attributes: $0.1, width: $0.2) }
        let total = zip(items, heights).reduce(CGFloat(0)) { $0 + $1.1 + $1.0.3 }
        var y = max(12, (bounds.height - total) / 2)
        var runs: [TextRun] = []
        for (index, item) in items.enumerated() {
            let rect = NSRect(x: (width - item.2) / 2, y: y, width: item.2, height: heights[index])
            runs.append(TextRun(text: item.0, attributes: item.1, frame: rect))
            y += heights[index] + item.3
        }
        return runs
    }

    private func style(size: CGFloat, color: NSColor, kern: CGFloat = 0, digits: Bool = false,
                       lineSpacing: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = lineSpacing
        var attributes: [NSAttributedString.Key: Any] = [.font: AppFont.font(size, digits: digits),
            .foregroundColor: color, .kern: kern, .paragraphStyle: paragraph]
        if isOverlay {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
            shadow.shadowBlurRadius = 9
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            attributes[.shadow] = shadow
        }
        return attributes
    }

    private func textHeight(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(with: NSSize(width: width, height: 2000),
              options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).height) + 2
    }
}
