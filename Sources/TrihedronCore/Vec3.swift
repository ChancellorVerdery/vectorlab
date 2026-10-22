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

    /// Overflow- and underflow-safe. The naive √(x²+y²+z²) is used whenever it
    /// is representable — identical bits, identical cost — but the sum of
    /// squares overflows to ∞ past ~1e154 and underflows to 0 below ~1e-162, so
    /// |<1e200, 1e200, 0>| answered ∞ and |<3e-200, 4e-200, 0>| answered 0.
    /// Both are silent wrong answers to a plain magnitude question.
    ///
    /// `> 0` is not a strong enough floor, and that left a BAND of wrong
    /// answers between the two ends pass 1 named. From ~1e-155 to ~1e-162 the
    /// sum of squares is SUBNORMAL: nonzero and finite, so the fast path took
    /// it, but carrying only a handful of significand bits. |<3e-162, 4e-162, 0>|
    /// printed 4.9702e-162 instead of 5e-162 — 0.6% out, in the digits the
    /// notebook shows. Requiring a NORMAL sum hands exactly that band to the
    /// reduced path, which is exact there, and moves nothing else: every value
    /// that was already taking the fast path still does, bit for bit.
    public var length: Double {
        let sum = x * x + y * y + z * z
        if sum.isFinite, sum >= .leastNormalMagnitude { return sum.squareRoot() }
        let m = maxAbsComponent
        // m is 0 (true zero vector), ∞, or NaN here — each is its own answer.
        guard m > 0, m.isFinite else { return m }
        let r = self / m
        return (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot() * m
    }

    /// nil for the zero vector or a non-finite one — and for nothing else.
    ///
    /// Reducing by the largest component before squaring is what makes this
    /// safe past ~1e154, where the sum of squares overflows and self/∞ used
    /// to hand out a (0, 0, 0) "unit" vector. It is equally exact at the
    /// bottom: <3e-320, 4e-320, 0> reduces to <0.75, 1, 0> and normalizes to
    /// <0.6, 0.8, 0> with |u| == 1, right down to the smallest subnormal.
    ///
    /// So there is no numerical range for a magnitude cutoff to protect, and
    /// the absolute `> 1e-12` that stood here through passes 1–5 was doing
    /// real harm. Direction is scale-free, but that test is not: it gave
    /// <3e-11, 4e-11, 0> a direction and denied one to <3e-13, 4e-13, 0>,
    /// which points exactly the same way. Trihedron has no unit system, so
    /// that made the answer depend on whether the user wrote metres or
    /// kilometres. It also put unit() at odds with mag(), honest since pass 2:
    /// one notebook line printed 5e-200 and the next called that vector zero.
    ///
    /// A vector has a direction iff it is nonzero and finite. Nothing that
    /// already had one moves by a single bit — the arithmetic is unchanged.
    public var normalized: Vec3? {
        guard isFinite else { return nil }
        let m = maxAbsComponent
        guard m > 0 else { return nil }
        let r = self / m
        let l = r.length
        guard l > 0, l.isFinite else { return nil }
        return r / l
    }

    /// Angle to another vector in radians, 0…π. nil when either is the zero
    /// vector. atan2(|a×b|, a·b) rather than acos(â·b̂): acos loses about half
    /// its digits near 0° and 180°, which is exactly where direction-cosine
    /// answers land — through acos a true 1e-6° reads back as 8.5e-7°.
    public func angle(to o: Vec3) -> Double? {
        guard let a = normalized, let b = o.normalized else { return nil }
        return Foundation.atan2(a.cross(b).length, a.dot(b))
    }

    public var maxAbsComponent: Double { max(abs(x), abs(y), abs(z)) }

    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
