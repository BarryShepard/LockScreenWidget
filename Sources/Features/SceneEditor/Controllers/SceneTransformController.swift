import AppKit

/// Geometry for one gesture, always evaluated against its unmodified starting snapshot.
enum SceneTransformController {
    struct Handle: Equatable {
        let x: Int, y: Int
        var isCorner: Bool { x != 0 && y != 0 }
    }
    struct Target: Equatable {
        let handle: Handle
        let point: CGPoint
        let rotation: Bool
    }
    static let handles = [Handle(x: -1, y: -1), Handle(x: 0, y: -1), Handle(x: 1, y: -1),
                          Handle(x: 1, y: 0), Handle(x: 1, y: 1), Handle(x: 0, y: 1),
                          Handle(x: -1, y: 1), Handle(x: -1, y: 0)]
    static func rotate(_ p: CGPoint, _ a: CGFloat) -> CGPoint {
        CGPoint(x: p.x*cos(a)-p.y*sin(a), y: p.x*sin(a)+p.y*cos(a))
    }
    static func targets(_ elements: [SceneElementModel], scale: CGFloat) -> [Target] {
        guard !elements.isEmpty, let bounds = SceneGeometry.bounds(elements) else { return [] }
        let single = elements.count == 1 ? elements[0] : nil
        let f = single?.frame ?? bounds, a = CGFloat(single?.rotation ?? 0) * .pi/180
        let center = CGPoint(x: f.midX, y: f.midY)
        return handles.flatMap { h -> [Target] in
            let p = rotate(CGPoint(x: CGFloat(h.x)*f.width/2, y: CGFloat(h.y)*f.height/2), a)
            let point = CGPoint(x: center.x+p.x, y: center.y+p.y)
            var result = [Target(handle: h, point: point, rotation: false)]
            if h.isCorner {
                let outward = rotate(CGPoint(x: CGFloat(h.x)*12/scale, y: CGFloat(h.y)*12/scale), a)
                result.append(Target(handle: h, point: CGPoint(x: point.x+outward.x, y: point.y+outward.y), rotation: true))
            }
            return result
        }
    }
    static func hit(_ point: CGPoint, elements: [SceneElementModel], scale: CGFloat) -> Target? {
        let all = targets(elements, scale: scale)
        if let nearest = all.filter({ !$0.rotation }).min(by: { distance($0.point, point) < distance($1.point, point) }), distance(nearest.point, point)*scale <= 7 { return nearest }
        if let nearest = all.filter(\.rotation).min(by: { distance($0.point, point) < distance($1.point, point) }), distance(nearest.point, point)*scale <= 9 { return nearest }
        // Edges are targets along their full length.
        let resize = all.filter { !$0.rotation }
        for i in stride(from: 0, to: resize.count, by: 2) {
            let p = resize[i].point, q = resize[(i+2)%resize.count].point
            let v = CGPoint(x: q.x-p.x, y: q.y-p.y), w = CGPoint(x: point.x-p.x, y: point.y-p.y)
            let t = max(0, min(1, (w.x*v.x+w.y*v.y)/max(0.0001, v.x*v.x+v.y*v.y)))
            if distance(point, CGPoint(x: p.x+t*v.x, y: p.y+t*v.y))*scale <= 5 { return resize[(i+1)%resize.count] }
        }
        return nil
    }
    private static let rotationCursor: NSCursor = {
        guard let image = NSImage(systemSymbolName: "rotate.right", accessibilityDescription: "Вращение") else { return .crosshair }
        image.size = CGSize(width: 18, height: 18)
        return NSCursor(image: image, hotSpot: CGPoint(x: 9, y: 9))
    }()
    static func cursor(_ target: Target, rotation: Double) -> NSCursor {
        if target.rotation { return rotationCursor }
        let h = target.handle
        let vector = rotate(CGPoint(x: CGFloat(h.x), y: CGFloat(h.y)), rotation * .pi/180)
        let angle = atan2(vector.y, vector.x)
        let octant = (Int((angle / (.pi/4)).rounded()) % 8 + 8) % 8
        let positions: [NSCursor.FrameResizePosition] = [.right, .bottomRight, .bottom, .bottomLeft, .left, .topLeft, .top, .topRight]
        return NSCursor.frameResize(position: positions[octant], directions: .all)
    }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x-b.x, a.y-b.y) }
    static func applying(_ start: SceneSnapshot, target: Target, from: CGPoint, to: CGPoint, stretch: Bool, crop: Bool) -> SceneSnapshot {
        var result = start
        let chosen = start.scene.elements.filter { start.selection.contains($0.id) }
        guard !chosen.isEmpty, let group = SceneGeometry.bounds(chosen) else { return start }
        let single = chosen.count == 1 ? chosen[0] : nil
        let f = single?.frame ?? group, a = CGFloat(single?.rotation ?? 0) * CGFloat.pi / 180
        let center = CGPoint(x: f.midX, y: f.midY)
        if target.rotation {
            let da = atan2(to.y-center.y, to.x-center.x)-atan2(from.y-center.y, from.x-center.x)
            for i in result.scene.elements.indices where start.selection.contains(result.scene.elements[i].id) {
                var e = result.scene.elements[i]
                let offset = rotate(CGPoint(x: e.frame.midX-center.x, y: e.frame.midY-center.y), da)
                e.frame.origin = CGPoint(x: center.x+offset.x-e.frame.width/2, y: center.y+offset.y-e.frame.height/2)
                e.rotation += Double(da*180/CGFloat.pi)
                result.scene.elements[i] = e
            }
            return result
        }
        let h = target.handle
        let delta = rotate(CGPoint(x: to.x-from.x, y: to.y-from.y), -a)
        if crop, let e = single, e.kind == .image {
            let image = e.imageRect ?? CGRect(origin: .zero, size: f.size)
            var left: CGFloat = 0, top: CGFloat = 0, right = f.width, bottom = f.height
            let minSize: CGFloat = 1
            if h.x < 0 { left = max(image.minX, min(right-minSize, delta.x)) }
            if h.x > 0 { right = min(image.maxX, max(left+minSize, f.width+delta.x)) }
            if h.y < 0 { top = max(image.minY, min(bottom-minSize, delta.y)) }
            if h.y > 0 { bottom = min(image.maxY, max(top+minSize, f.height+delta.y)) }
            let shift = rotate(CGPoint(x: (left+right-f.width)/2, y: (top+bottom-f.height)/2), a)
            var changed = e
            changed.frame = CGRect(x: center.x+shift.x-(right-left)/2, y: center.y+shift.y-(bottom-top)/2, width: right-left, height: bottom-top)
            changed.imageRect = image.offsetBy(dx: -left, dy: -top)
            if let i = result.scene.elements.firstIndex(where: { $0.id == e.id }) { result.scene.elements[i] = changed }
            return result
        }
        var sx = h.x == 0 ? 1 : (f.width + CGFloat(h.x)*delta.x)/f.width
        var sy = h.y == 0 ? 1 : (f.height + CGFloat(h.y)*delta.y)/f.height
        if (!stretch || single == nil) && !(single?.kind == .note && h.y == 0) {
            let s: CGFloat
            if h.x == 0 { s = sy } else if h.y == 0 { s = sx }
            else { s = 1 + ((sx-1)*f.width*f.width + (sy-1)*f.height*f.height)/(f.width*f.width+f.height*f.height) }
            sx = s; sy = s
        }
        let minimum = max(1/f.width, 1/f.height)
        sx = max(minimum, sx); sy = max(minimum, sy)
        let anchorLocal = CGPoint(x: -CGFloat(h.x)*f.width/2, y: -CGFloat(h.y)*f.height/2)
        let anchorOffset = rotate(anchorLocal, a)
        let anchor = CGPoint(x: center.x+anchorOffset.x, y: center.y+anchorOffset.y)
        let newCenterOffset = rotate(CGPoint(x: -anchorLocal.x*sx, y: -anchorLocal.y*sy), a)
        let newCenter = CGPoint(x: anchor.x+newCenterOffset.x, y: anchor.y+newCenterOffset.y)
        for i in result.scene.elements.indices where start.selection.contains(result.scene.elements[i].id) {
            var e = result.scene.elements[i]
            let offset = CGPoint(x: e.frame.midX-center.x, y: e.frame.midY-center.y)
            let width = e.frame.width*sx, height = e.frame.height*sy
            e.frame = CGRect(x: newCenter.x+offset.x*sx-width/2, y: newCenter.y+offset.y*sy-height/2, width: width, height: height)
            if let image = e.imageRect { e.imageRect = CGRect(x: image.minX*sx, y: image.minY*sy, width: image.width*sx, height: image.height*sy) }
            if e.kind != .note { e.cornerRadius *= min(sx, sy) }
            if e.kind == .text || e.kind == .countdown { e.textScaleX = (e.textScaleX ?? 1)*sx; e.textScaleY = (e.textScaleY ?? 1)*sy }
            result.scene.elements[i] = e
        }
        return result
    }
}
