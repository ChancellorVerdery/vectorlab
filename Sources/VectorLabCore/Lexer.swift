import Foundation

enum Token: Equatable {
    case number(Double)
    case ident(String)
    case vecKeyword          // \vec, \vector, or plain "vec" — cosmetic prefix
    case hatKeyword          // \hat X names the distinct identifier X̂
    case plus, minus, star, slash, caret, equals, comma
    case lparen, rparen, langle, rangle, lbracket, rbracket
    case pipe, angleOp, dotOp, crossOp, degree, memberDot
}

enum Lexer {
    /// LaTeX Greek commands → the letter they produce. Shared with MathPrint.
    static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ",
        "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "vartheta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο",
        "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ",
        "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ",
        "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ",
        "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
    ]

    /// ASCII digits only — Unicode numerals like ² or ½ must error, not lex.
    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    /// Identifier characters: ASCII letters/digits/underscore, subscript
    /// digits (F₁ ≡ F_1), plus any letter-initial grapheme so û, θ, and F⃗
    /// (letter + combining mark) work — including digits carrying marks (1⃗).
    private static func isIdentChar(_ c: Character) -> Bool {
        if c == "_" { return true }
        if c.isASCII { return c.isLetter || c.isNumber }
        if MathPrint.subscriptToPlain[c] != nil { return true }
        guard let first = c.unicodeScalars.first else { return false }
        if first.properties.isAlphabetic { return true }
        return c.unicodeScalars.count > 1 && (("0"..."9").contains(String(first)) || first == "_")
    }

    static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0

        func scanNumber() throws {
            var s = ""
            while i < chars.count, isDigit(chars[i]) || chars[i] == "." {
                s.append(chars[i]); i += 1
            }
            if i < chars.count, chars[i] == "e" || chars[i] == "E",
               i + 1 < chars.count, isDigit(chars[i + 1]) || ((chars[i + 1] == "+" || chars[i + 1] == "-") && i + 2 < chars.count && isDigit(chars[i + 2])) {
                s.append(chars[i]); i += 1
                if chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
                while i < chars.count, isDigit(chars[i]) { s.append(chars[i]); i += 1 }
            }
            guard let d = Double(s) else { throw EvalError("invalid number '\(s)'") }
            tokens.append(.number(d))
        }

        func scanIdent() -> (name: String, hadArrow: Bool) {
            var s = ""
            while i < chars.count, isIdentChar(chars[i]) {
                s.append(chars[i]); i += 1
            }
            // Subscript digits are the same name as their _n spelling: F₁ ≡ F_1.
            var normalized = ""
            var inSubscript = false
            for ch in s {
                if let plain = MathPrint.subscriptToPlain[ch] {
                    if !inSubscript { normalized.append("_") }
                    normalized.append(plain)
                    inSubscript = true
                } else {
                    normalized.append(ch)
                    inSubscript = false
                }
            }
            // The arrow in F⃗ means the same as \vec F — strip it from the
            // name, but report it so definitions count as vector-marked.
            // û typed directly and u + combining hat must be the same name.
            // Scalar-level check: grapheme-based contains() can't find a
            // lone combining mark inside a cluster like P⃗.
            let hadArrow = normalized.unicodeScalars.contains { $0.value == 0x20D7 }
            var cleaned = normalized.replacingOccurrences(of: "\u{20D7}", with: "")
                .precomposedStringWithCanonicalMapping
            if cleaned == "π" { cleaned = "pi" }
            return (cleaned, hadArrow)
        }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if isDigit(c) { try scanNumber(); continue }
            if c == ".", i + 1 < chars.count, isDigit(chars[i + 1]) { try scanNumber(); continue }
            if isIdentChar(c), MathPrint.subscriptToPlain[c] == nil {
                let (word, hadArrow) = scanIdent()
                if hadArrow { tokens.append(.vecKeyword) }
                tokens.append(word == "vec" ? .vecKeyword : .ident(word))
                continue
            }
            // Superscript run is a power: 2³ ≡ 2^3, 2⁻¹ ≡ 2^-1.
            if MathPrint.superscriptToPlain[c] != nil || c == "⁻" {
                tokens.append(.caret)
                if c == "⁻" { tokens.append(.minus); i += 1 }
                var digits = ""
                while i < chars.count, let d = MathPrint.superscriptToPlain[chars[i]] {
                    digits.append(d)
                    i += 1
                }
                guard let value = Double(digits) else { throw EvalError("superscript needs digits") }
                tokens.append(.number(value))
                continue
            }
            if c == "\\" {
                i += 1
                let cmd = scanIdent().name
                switch cmd {
                case "vec", "vector", "overrightarrow": tokens.append(.vecKeyword)
                case "hat": tokens.append(.hatKeyword)
                case "cdot": tokens.append(.dotOp)
                case "times": tokens.append(.crossOp)
                case "langle": tokens.append(.langle)
                case "rangle": tokens.append(.rangle)
                default:
                    guard let letter = Self.greek[cmd] else {
                        throw EvalError("unknown command \\\(cmd)")
                    }
                    // π is the constant; other Greek letters are plain names.
                    tokens.append(.ident(letter == "π" ? "pi" : letter))
                }
                continue
            }
            i += 1
            switch c {
            case "+": tokens.append(.plus)
            case "-", "−", "–": tokens.append(.minus)
            case "*", "∗": tokens.append(.star)
            case "/": tokens.append(.slash)
            case "^": tokens.append(.caret)
            case "=": tokens.append(.equals)
            case ",": tokens.append(.comma)
            case "(", "{": tokens.append(.lparen)   // LaTeX braces act as parens
            case ")", "}": tokens.append(.rparen)
            case "<", "⟨", "〈": tokens.append(.langle)
            case ">", "⟩", "〉": tokens.append(.rangle)
            case "[": tokens.append(.lbracket)
            case "]": tokens.append(.rbracket)
            case "|": tokens.append(.pipe)
            case "∠", "@": tokens.append(.angleOp)
            case "·", "⋅", "•": tokens.append(.dotOp)
            case "×": tokens.append(.crossOp)
            case "°": tokens.append(.degree)
            case ".": tokens.append(.memberDot)
            case "π": tokens.append(.ident("pi"))
            case "√": tokens.append(.ident("sqrt"))
            default: throw EvalError("unexpected character '\(c)'")
            }
        }
        return tokens
    }
}
