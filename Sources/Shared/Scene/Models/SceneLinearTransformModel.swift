import Foundation

/// Center-relative residual map. Rotation stays independently editable in the inspector.
struct SceneLinearTransformModel: Codable, Equatable {
    var a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1
    var determinant: Double { a*d-b*c }
    var isValid: Bool {
        [a,b,c,d,determinant].allSatisfy(\.isFinite) && determinant > 0 &&
        [d/determinant, -b/determinant, -c/determinant, a/determinant].allSatisfy(\.isFinite)
    }
    func applying(_ p: CGPoint) -> CGPoint {
        CGPoint(x: a*p.x+c*p.y, y: b*p.x+d*p.y)
    }
    func inverse(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (d*p.x-c*p.y)/determinant, y: (-b*p.x+a*p.y)/determinant)
    }
    func followed(by m: Self) -> Self {
        Self(a: m.a*a+m.c*b, b: m.b*a+m.d*b, c: m.a*c+m.c*d, d: m.b*c+m.d*d)
    }
    static func rotation(_ radians: Double) -> Self {
        Self(a: cos(radians), b: sin(radians), c: -sin(radians), d: cos(radians))
    }
}

extension SceneElementModel {
    func localVector(_ p: CGPoint) -> CGPoint {
        SceneLinearTransformModel.rotation(rotation * .pi/180).applying((linearTransform ?? .init()).applying(p))
    }
    func inverseVector(_ p: CGPoint) -> CGPoint {
        (linearTransform ?? .init()).inverse(SceneLinearTransformModel.rotation(-rotation * .pi/180).applying(p))
    }
    func localPoint(_ p: CGPoint) -> CGPoint {
        let v = localVector(CGPoint(x: p.x-frame.width/2, y: p.y-frame.height/2))
        return CGPoint(x: frame.midX+v.x, y: frame.midY+v.y)
    }
}
