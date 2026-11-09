import AppKit

struct SceneViewport {
    let rect: CGRect
    let scale: CGFloat
    init(size: CGSize, in bounds: CGRect) {
        scale = max(0.0001, min(bounds.width/size.width, bounds.height/size.height))
        rect = CGRect(x: bounds.midX-size.width*scale/2, y: bounds.midY-size.height*scale/2,
                      width: size.width*scale, height: size.height*scale)
    }
    func scenePoint(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x-rect.minX)/scale, y: (p.y-rect.minY)/scale) }
    func viewPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX+p.x*scale, y: rect.minY+p.y*scale) }
    func viewRect(_ r: CGRect) -> CGRect {
        CGRect(origin: viewPoint(r.origin), size: CGSize(width: r.width*scale, height: r.height*scale))
    }
}

enum SceneTextLayout {
    static func attributes(_ style: SceneTextStyle, scale: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.alignment = [NSTextAlignment.left, .center, .right][style.horizontalAlignment]
        p.lineBreakMode = .byWordWrapping
        if style.lineHeight > 0 { p.minimumLineHeight = style.lineHeight*scale; p.maximumLineHeight = p.minimumLineHeight }
        return [.font: style.font(scale: scale), .foregroundColor: style.color.nsColor, .paragraphStyle: p,
                .kern: style.letterSpacing/100 * style.fontSize * scale]
    }
    static func measure(_ e: SceneElement, width: CGFloat) -> CGSize {
        // A trailing newline owns a real empty line while the insertion point is there.
        let content = (e.text.isEmpty || e.text.hasSuffix("\n")) ? e.text + "\u{200B}" : e.text
        let s = NSAttributedString(string: content, attributes: attributes(e.style))
        let r = s.boundingRect(with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }
    static func fit(_ e: inout SceneElement, minimumHeight: CGFloat = 1) {
        let auto = e.autoTextWidth == true
        if auto { e.frame.size.width = max(28, measure(e, width: .greatestFiniteMagnitude).width + 2) }
        e.frame.size.height = max(minimumHeight, measure(e, width: e.frame.width).height)
    }
    static func yOffset(_ e: SceneElement) -> CGFloat {
        let free = max(0, e.frame.height - measure(e, width: e.frame.width).height)
        return [0, free/2, free][e.style.verticalAlignment]
    }
}

final class SceneRenderer {
    private let store: SceneStore
    private let cache = NSCache<NSString, NSImage>()
    init(store: SceneStore) { self.store = store; cache.countLimit = 32; cache.totalCostLimit = 64*1024*1024 }
    private func image(_ id: String) -> NSImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let image = store.image(for: id) else { return nil }
        let size = image.representations.first
        let cost = min(64*1024*1024.0, CGFloat(size?.pixelsWide ?? 1)*CGFloat(size?.pixelsHigh ?? 1)*4)
        cache.setObject(image, forKey: id as NSString, cost: Int(max(1, cost)))
        return image
    }
    func draw(_ scene: EditorScene, in viewport: SceneViewport, excluding: UUID? = nil) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.clip(to: viewport.rect)
        ctx.translateBy(x: viewport.rect.minX, y: viewport.rect.minY)
        ctx.scaleBy(x: viewport.scale, y: viewport.scale)
        for e in scene.elements where e.id != excluding {
            ctx.saveGState()
            ctx.translateBy(x: e.frame.midX, y: e.frame.midY)
            ctx.rotate(by: e.rotation * .pi / 180)
            ctx.translateBy(x: -e.frame.width/2, y: -e.frame.height/2)
            let box = CGRect(origin: .zero, size: e.frame.size), radius = min(e.cornerRadius, box.width/2, box.height/2)
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).addClip()
            ctx.setAlpha(e.opacity); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            switch e.kind {
            case .text:
                let y = SceneTextLayout.yOffset(e)
                NSAttributedString(string: e.text, attributes: SceneTextLayout.attributes(e.style))
                    .draw(with: CGRect(x: 0, y: y, width: box.width, height: max(1, box.height-y)),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
            case .image:
                if let id = e.assetID, let img = image(id) {
                    img.draw(in: e.imageRect ?? box, from: .zero, operation: .sourceOver, fraction: 1,
                             respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
                } else {
                    NSColor(white: 0.25, alpha: 0.85).setFill(); box.fill()
                    ("Нет изображения" as NSString).draw(in: box.insetBy(dx: 5, dy: 5),
                        withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13)])
                }
            }
            ctx.endTransparencyLayer(); ctx.restoreGState()
        }
    }
}

final class SceneDisplayView: NSView {
    var scene: EditorScene { didSet { needsDisplay = true } }
    private let renderer: SceneRenderer
    init(scene: EditorScene, store: SceneStore) {
        self.scene = scene; renderer = SceneRenderer(store: store)
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { renderer.draw(scene, in: SceneViewport(size: scene.canvasSize, in: bounds)) }
}
