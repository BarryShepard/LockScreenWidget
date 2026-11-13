import AppKit

/// Radius gestures live inside a leaf; their hit area stays separate from transforms.
enum SceneCornerController {
    struct Target {
        let elementID: UUID
        let point: CGPoint
        let initialRadius: CGFloat
        let maximumRadius: CGFloat
        let radiusPerPoint: CGFloat
    }

    static func target(_ elements: [SceneElementModel], scale: CGFloat) -> Target? {
        guard let element = elements.last, scale.isFinite, scale > 0 else { return nil }
        let maximum = CGFloat(element.maximumCornerRadius)
        let inset = 18/scale, span = maximum-inset
        // Small frames keep numeric radius editing; squeezing another target in is ambiguous.
        guard span >= 10/scale else { return nil }
        let radius = CGFloat(element.effectiveCornerRadius)
        let distance = inset + span*(radius/maximum)
        let offset = SceneTransformController.rotate(CGPoint(x: distance-element.frame.width/2,
            y: distance-element.frame.height/2), element.rotation * .pi/180)
        let point = CGPoint(x: element.frame.midX+offset.x, y: element.frame.midY+offset.y)
        let separate = SceneTransformController.targets(elements, scale: scale).allSatisfy {
            hypot($0.point.x-point.x, $0.point.y-point.y)*scale >= 15
        }
        guard separate else { return nil }
        return Target(elementID: element.id, point: point, initialRadius: radius,
                      maximumRadius: maximum, radiusPerPoint: maximum/span)
    }

    static func hit(_ point: CGPoint, elements: [SceneElementModel], scale: CGFloat) -> Target? {
        guard let target = target(elements, scale: scale),
              hypot(point.x-target.point.x, point.y-target.point.y)*scale <= 7 else { return nil }
        return target
    }

    static func applying(_ start: SceneSnapshot, target: Target, from: CGPoint, to: CGPoint) -> SceneSnapshot {
        guard let primary = start.scene.elements.first(where: { $0.id == target.elementID }),
              start.selection.contains(primary.id) else { return start }
        let delta = SceneTransformController.rotate(CGPoint(x: to.x-from.x, y: to.y-from.y), -primary.rotation * .pi/180)
        let radius = max(0, min(target.maximumRadius, target.initialRadius+(delta.x+delta.y)/2*target.radiusPerPoint))
        var next = start
        for i in next.scene.elements.indices where start.selection.contains(next.scene.elements[i].id) {
            next.scene.elements[i].cornerRadius = min(Double(radius), next.scene.elements[i].maximumCornerRadius)
        }
        return next
    }
}
