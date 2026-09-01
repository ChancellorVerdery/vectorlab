import Foundation

public enum Fmt {
    /// Up to 4 decimal places, trailing zeros stripped, no negative zero.
    public static func num(_ d: Double) -> String {
        guard d.isFinite else { return d.isNaN ? "NaN" : (d > 0 ? "∞" : "-∞") }
        // Scale-up can overflow for |d| > ~1.8e304; such values are exact
        // integers already, so skip the 4-decimal rounding there.
        let scaled = d * 10_000
        let rounded = scaled.isFinite ? scaled.rounded() / 10_000 : d
        var s: String
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            s = String(format: "%.0f", rounded)
        } else {
            s = String(format: "%.4f", rounded)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    public static func vector(_ v: Vec3) -> String {
        "⟨\(num(v.x)), \(num(v.y)), \(num(v.z))⟩"
    }

    public static func value(_ v: Value) -> String {
        switch v {
        case .scalar(let s): return num(s)
        case .vector(let vec, _):
            return "\(vector(vec))   |v| = \(num(vec.length))"
        case .point(let p): return "(\(num(p.x)), \(num(p.y)), \(num(p.z)))"
        }
    }
}
