import Foundation

/// Display-only prettifier: turns a raw notebook line into math notation.
/// Never fed back into the parser — the raw text stays the source of truth.
public enum MathPrint {
    public static func pretty(_ line: String) -> String {
        var s = line
        // The name a hat goes on is the LEXER's idea of a name: letters, ASCII
        // digits, underscore. `\p{N}` was every Unicode number, which includes
        // the script glyphs applyScripts makes - so `\hat u` then `^2` hatted
        // the EXPONENT and produced a combining circumflex sitting on a
        // superscript two. The lexer refuses that character outright, so the
        // user's line stopped parsing on "unexpected character". Same class
        // mistake, and same correction, as pass 10's `pi` rule.
        s = s.replacing(/\\hat\s*[({]\s*([\p{L}_][\p{L}0-9_]*)\s*[)}]/) { m in
            String(m.output.1 + "\u{0302}").precomposedStringWithCanonicalMapping
        }
        s = s.replacing(/\\hat\s+([\p{L}_][\p{L}0-9_]*)/) { m in
            String(m.output.1 + "\u{0302}").precomposedStringWithCanonicalMapping
        }
        // \vec stays in the text: the notebook renders it as a full-width
        // arrow OVER the name (a combining char could only mark one letter).
        s = s.replacing(/\\(?:vec|vector|overrightarrow)\s*[({]\s*([\p{L}_][\p{L}\p{N}_]*)\s*[)}]/) { m in
            #"\vec "# + String(m.output.1)
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
        s = applyScripts(s)
        // `pi` is the constant only when it is not part of a longer name.
        // `\b` is a UAX #29 word boundary, which is the wrong notion twice:
        //   * U+00B7 (what the `*` rule above produces) is MidLetter, so
        //     "pi·r" reads as ONE word and pi never rendered at all; and
        //   * the script glyphs applyScripts makes are not word characters,
        //     so "x^2pi" only converted on a SECOND pass, which cost the user
        //     a third Return (renderOrSubmit only commits at a fixed point).
        // Use the lexer's own idea of a name character instead - letters,
        // ASCII digits, underscore - so this is a one-pass rule. `spin`,
        // `2pi` and `F_2pi` are all still left alone.
        // (lookbehind is not supported, so the preceding character is captured
        // and put back rather than asserted.)
        s = s.replacing(/(^|[^\p{L}0-9_])pi(?![\p{L}0-9_])/) { m in
            String(m.output.1) + "π"
        }
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
    /// existing superscript run is left alone so 2^3^2 never merges into 2³²,
    /// and a fractional exponent is never superscripted at all — there is no
    /// superscript "." to put in it.
    ///
    /// This is NOT display-only. RichEntryField writes the result back into
    /// the entry's text binding on every keystroke, so whatever comes out of
    /// here is the string the parser then sees.
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
            // A decimal point after a superscript run means the exponent was
            // fractional all along: 2^3.5 superscripts the 3 the instant it is
            // typed, and the "." arrives one keystroke later. Unicode has no
            // superscript ".", so 2³.5 lexed as 2^3 followed by a stray .5 and
            // the user's own line stopped parsing. Put the run back into ^ form.
            if c == ".", let last = out.last, superscriptSet.contains(last) {
                var run: [Character] = []
                while let l = out.last, superscriptSet.contains(l) {
                    run.append(out.removeLast())
                }
                out.append("^")
                for ch in run.reversed() {
                    out.append(ch == "⁻" ? "-" : (superscriptToPlain[ch] ?? ch))
                }
                out.append(".")
                i += 1
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
                // …and don't create the problem in the first place when the
                // whole exponent is already visible: 2^3.5 in one paste.
                if sawDigit, !(j < chars.count && chars[j] == ".") {
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
