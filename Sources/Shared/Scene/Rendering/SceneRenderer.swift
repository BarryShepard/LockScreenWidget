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

struct SceneRenderContent: Equatable {
    let canvasSize: CGSize
    let elements: [SceneRenderElement]
}

struct SceneRenderElement: Equatable {
    let id: UUID
    let frame: CGRect
    let rotation: Double
    let cornerRadius: Double
    let opacity: Double
    let drawing: SceneRenderDrawing
}

enum SceneRenderDrawing: Equatable {
    case text(NSAttributedString, frame: CGRect)
    case image(NSImage, frame: CGRect)
    case missingImage(label: NSAttributedString, frame: CGRect, background: NSColor)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.text(left, leftFrame), .text(right, rightFrame)):
            return leftFrame == rightFrame && left.isEqual(to: right)
        case let (.image(left, leftFrame), .image(right, rightFrame)):
            // The presenter reuses the decoded image while it is cached.
            return leftFrame == rightFrame && left === right
        case let (.missingImage(left, leftFrame, leftBackground), .missingImage(right, rightFrame, rightBackground)):
            return leftFrame == rightFrame && left.isEqual(to: right) && leftBackground.isEqual(rightBackground)
        default:
            return false
        }
    }
}

final class SceneRenderer {
    func draw(_ content: SceneRenderContent, in viewport: SceneViewport, excluding: UUID? = nil) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.clip(to: viewport.rect)
        ctx.translateBy(x: viewport.rect.minX, y: viewport.rect.minY)
        ctx.scaleBy(x: viewport.scale, y: viewport.scale)
        for e in content.elements where e.id != excluding {
            ctx.saveGState()
            ctx.translateBy(x: e.frame.midX, y: e.frame.midY)
            ctx.rotate(by: e.rotation * .pi / 180)
            ctx.translateBy(x: -e.frame.width/2, y: -e.frame.height/2)
            let box = CGRect(origin: .zero, size: e.frame.size), radius = min(e.cornerRadius, box.width/2, box.height/2)
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).addClip()
            ctx.setAlpha(e.opacity); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            switch e.drawing {
            case let .text(text, frame):
                text.draw(with: frame, options: [.usesLineFragmentOrigin, .usesFontLeading])
            case let .image(image, frame):
                image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            case let .missingImage(label, frame, background):
                background.setFill(); box.fill()
                label.draw(in: frame)
            }
            ctx.endTransparencyLayer(); ctx.restoreGState()
        }
    }
}

class SceneDisplayView: NSView {
    var content: SceneRenderContent { didSet { if content != oldValue { needsDisplay = true } } }
    private let renderer = SceneRenderer()
    init(content: SceneRenderContent) {
        self.content = content
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func setFrameSize(_ newSize: NSSize) {
        let resized = newSize != frame.size
        super.setFrameSize(newSize)
        if resized { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) { renderer.draw(content, in: SceneViewport(size: content.canvasSize, in: bounds)) }
}
