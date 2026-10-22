import Foundation

/// Degree-based trigonometry that is exact on the quadrant multiples.
///
/// Foundation's sin/cos take radians, and no multiple of 90° except 0 has an
/// exact radian representation — `cos(90 * .pi / 180)` is 6.1232e-17, not 0.
/// Fmt's four-decimal rounding hid that until pass 3 gave it scientific
/// notation below 1e-4 (rightly: `mag()` has to be able to print 5e-200), at
/// which point the residue surfaced on the most common line in the app:
/// `\vec F = 500 ∠ 90` printed `<3.0616e-14, 500, 0>` for a force pointing
/// straight up, and a load balance that should cancel left `-6.1232e-15`
/// behind. This is a statics tool; the axes are where the numbers live.
enum Trig {
    /// 0…3 when `deg` is an exact multiple of 90, else nil.
    /// `truncatingRemainder` is exact for every finite Double, so this asks
    /// the question about the value the user actually has, at any magnitude.
    private static func quadrant(_ deg: Double) -> Int? {
        guard deg.isFinite, deg.truncatingRemainder(dividingBy: 90) == 0 else { return nil }
        let m = Int(deg.truncatingRemainder(dividingBy: 360) / 90)   // -3…3, exact
        return m < 0 ? m + 4 : m
    }

    /// Reducing into (-360, 360) first is exact — it is the identity for every
    /// angle anyone types — and it keeps the radian conversion's relative
    /// error from being scaled up by a huge degree count.
    private static func radians(_ deg: Double) -> Double {
        guard deg.isFinite else { return deg }
        return deg.truncatingRemainder(dividingBy: 360) * .pi / 180
    }

    static func sin(_ deg: Double) -> Double {
        if let q = quadrant(deg) { return [0, 1, 0, -1][q] }
        return Foundation.sin(radians(deg))
    }

    static func cos(_ deg: Double) -> Double {
        if let q = quadrant(deg) { return [1, 0, -1, 0][q] }
        return Foundation.cos(radians(deg))
    }

    /// nil at the odd multiples of 90, where the tangent is undefined.
    /// Foundation answers 1.6331e16 there, which reads on screen as a real
    /// (enormous) number rather than as the vertical asymptote it is.
    static func tan(_ deg: Double) -> Double? {
        if let q = quadrant(deg) { return q.isMultiple(of: 2) ? 0 : nil }
        return Foundation.tan(radians(deg))
    }
}
