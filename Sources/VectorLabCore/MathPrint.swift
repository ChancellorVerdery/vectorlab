import Foundation

/// Display-only prettifier: turns a raw notebook line into math notation.
/// Never fed back into the parser — the raw text stays the source of truth.
public enum MathPrint {
    public static func pretty(_ line: String) -> String {
        var s = line
        s = s.replacing(/\\hat\s*[({]\s*([\p{L}_][\p{L}\p{N}_]*)\s*[)}]/) { m in
            String(m.output.1 + "\u{0302}").precomposedStringWithCanonicalMapping
        }
        s = s.replacing(/\\hat\s+([\p{L}_][\p{L}\p{N}_]*)/) { m in
            String(m.output.1 + "\u{0302}").precomposedStringWithCanonicalMapping
        }
        s = s.replacing(/\\(?:vec|vector|overrightarrow)\s*[({]\s*([\p{L}_][\p{L}\p{N}_]*)\s*[)}]/) { m in
            String(m.output.1 + "\u{20D7}")
        }
        s = s.replacing(/\\(?:vec|vector|overrightarrow)\s+([\p{L}_][\p{L}\p{N}_]*)/) { m in
            String(m.output.1 + "\u{20D7}")
        }
        s = s.replacingOccurrences(of: "\\cdot", with: "·")
        s = s.replacingOccurrences(of: "\\times", with: "×")
        // Plain < > stay: the ⟨⟩ glyphs read like parentheses in monospace,
        // and parens mean points here — the distinction must be unmistakable.
        s = s.replacingOccurrences(of: "\\langle", with: "<")
        s = s.replacingOccurrences(of: "\\rangle", with: ">")
        s = s.replacingOccurrences(of: "*", with: "·")
        s = s.replacingOccurrences(of: "@", with: "∠")
        s = s.replacingOccurrences(of: "sqrt(", with: "√(")
        // Greek commands; unknown \commands are left untouched.
        s = s.replacing(/\\([a-zA-Z]+)/) { m in
            Lexer.greek[String(m.output.1)] ?? String(m.output.0)
        }
        s = s.replacing(/\bpi\b/, with: "π")
        s = applyScripts(s)
        return s
    }

    static let subscriptDigits: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    ]
    static let superscriptDigits: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    ]
    private static let subscriptSet = Set(subscriptDigits.values)
    private static let superscriptSet = Set(superscriptDigits.values).union(["⁻"])

    static let subscriptToPlain: [Character: Character] =
        Dictionary(uniqueKeysWithValues: subscriptDigits.map { ($1, $0) })
    static let superscriptToPlain: [Character: Character] =
        Dictionary(uniqueKeysWithValues: superscriptDigits.map { ($1, $0) })

    /// _1 → ₁ and ^2 → ² (digits only — Unicode has no capital-letter
    /// subscripts, so r_AB stays inline). Safe rules: a second ^ after an
    /// existing superscript run is left alone so 2^3^2 never merges into 2³².
    public static func applyScripts(_ input: String) -> String {
        let chars = Array(input)
        var out: [Character] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "_", i + 1 < chars.count, let sub = subscriptDigits[chars[i + 1]],
               let last = out.last, last.isLetter || subscriptSet.contains(last) || subscriptDigits[last] != nil {
                out.append(sub)
                i += 2
                while i < chars.count, let d = subscriptDigits[chars[i]] {
                    out.append(d)
                    i += 1
                }
                continue
            }
            if c == "^", let last = out.last, !superscriptSet.contains(last) {
                var j = i + 1
                var run: [Character] = []
                if j < chars.count, chars[j] == "-" { run.append("⁻"); j += 1 }
                var sawDigit = false
                while j < chars.count, let d = superscriptDigits[chars[j]] {
                    run.append(d)
                    sawDigit = true
                    j += 1
                }
                if sawDigit {
                    out.append(contentsOf: run)
                    i = j
                    continue
                }
            }
            // Continue an existing run: typing more digits after F₁ or 2³.
            if let sub = subscriptDigits[c], let last = out.last, subscriptSet.contains(last) {
                out.append(sub)
                i += 1
                continue
            }
            if let sup = superscriptDigits[c], let last = out.last, superscriptSet.contains(last) {
                out.append(sup)
                i += 1
                continue
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }
}
