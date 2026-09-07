import Foundation

public enum Fmt {
    /// Up to 4 decimal places, trailing zeros stripped, no negative zero —
    /// but only inside the band where fixed point tells the truth.
    ///
    /// Below 1e-4 the 4-decimal rounding printed EVERY nonzero value as "0",
    /// so `mag(<3e-200, 4e-200, 0>)` computed 5e-200 (pass 2) and the notebook
    /// showed `0`. At 1e15 and above it printed the exact binary expansion:
    /// 1e305 came out as 305 characters beginning "99999999…", digits the
    /// value does not carry. Outside the band, scientific notation.
    public static func num(_ d: Double) -> String {
        guard d.isFinite else { return d.isNaN ? "NaN" : (d > 0 ? "∞" : "-∞") }
        if d == 0 { return "0" }              // also folds -0
        let a = abs(d)
        if a < 1e-4 || a >= 1e15 { return scientific(d) }
        // Four decimals carries five significant digits at |d| >= 1 and four
        // at |d| >= 0.1 — but only ONE at the bottom of the band. 1.2345e-4
        // printed "0.0001", 19% wrong, while 9e-5 (one notch BELOW the cutoff,
        // on the scientific path) printed with five. sin(0.01) printed 0.0002
        // while the smaller sin(0.005) printed 8.7266e-5: the less extreme
        // input got the worse answer. Below 0.1, add one decimal place per
        // leading zero, so the whole fixed band carries >= 4 significant
        // digits. Nothing at |d| >= 0.1 moves by a single bit.
        // Significant digits = integer digits + decimals; keep that in [4, 15].
        // A Double carries about 15-17, so four decimals on a value near 1e14
        // printed 123456789012345.5938 — the SAME binary residue pass 3
        // removed above 1e15, still on show one notch below its cutoff.
        var intDigits = 0
        var t = a
        while t >= 1 { t /= 10; intDigits += 1 }
        var decimals = intDigits >= 1 ? min(4, max(0, 15 - intDigits)) : 4
        if intDigits == 0 {
            var probe = a
            while probe < 0.1 { probe *= 10; decimals += 1 }
        }
        var scale = 1.0
        for _ in 0..<decimals { scale *= 10 }
        let rounded = (d * scale).rounded() / scale   // |d| < 1e15: cannot overflow
        var s: String
        if rounded == rounded.rounded() {
            s = String(format: "%.0f", rounded)
        } else {
            s = String(format: "%.\(decimals)f", rounded)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    /// 1.4142e200, 5e-200 — five significant digits, no "+" and no zero-padded
    /// exponent, and readable straight back by `Double(_:)`.
    private static func scientific(_ d: Double) -> String {
        let raw = String(format: "%.4e", d)
        guard let e = raw.firstIndex(of: "e") else { return raw }
        var mantissa = String(raw[raw.startIndex..<e])
        var exponent = String(raw[raw.index(after: e)...])
        while mantissa.contains("."), mantissa.hasSuffix("0") { mantissa.removeLast() }
        if mantissa.hasSuffix(".") { mantissa.removeLast() }
        let negative = exponent.hasPrefix("-")
        exponent = exponent.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        while exponent.count > 1, exponent.hasPrefix("0") { exponent.removeFirst() }
        return "\(mantissa)e\(negative ? "-" : "")\(exponent)"
    }

    public static func vector(_ v: Vec3) -> String {
        // Plain <>: the ⟨⟩ glyphs look like parens in monospace, and parens
        // mean points — results must model the notation users should write.
        "<\(num(v.x)), \(num(v.y)), \(num(v.z))>"
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
