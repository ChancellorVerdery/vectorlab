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
        s = s.replacingOccurrences(of: "\\langle", with: "⟨")
        s = s.replacingOccurrences(of: "\\rangle", with: "⟩")
        s = s.replacingOccurrences(of: "<", with: "⟨")
        s = s.replacingOccurrences(of: ">", with: "⟩")
        s = s.replacingOccurrences(of: "*", with: "·")
        s = s.replacingOccurrences(of: "sqrt(", with: "√(")
        s = s.replacing(/\bpi\b/, with: "π")
        return s
    }
}
