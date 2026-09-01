import Foundation

/// 3D vector with Double components. 2D inputs are stored with z = 0.
public struct Vec3: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static prefix func - (v: Vec3) -> Vec3 { Vec3(-v.x, -v.y, -v.z) }
    public static func * (s: Double, v: Vec3) -> Vec3 { Vec3(s * v.x, s * v.y, s * v.z) }
    public static func * (v: Vec3, s: Double) -> Vec3 { s * v }
    public static func / (v: Vec3, s: Double) -> Vec3 { Vec3(v.x / s, v.y / s, v.z / s) }

    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }

    public func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    /// nil for the zero vector.
    public var normalized: Vec3? {
        let l = length
        guard l > 1e-12 else { return nil }
        return self / l
    }

    public var maxAbsComponent: Double { max(abs(x), abs(y), abs(z)) }

    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
