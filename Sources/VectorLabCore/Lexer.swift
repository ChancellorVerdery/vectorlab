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
    /// ASCII digits only — Unicode numerals like ² or ½ must error, not lex.
    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

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

        func scanIdent() -> String {
            var s = ""
            while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                s.append(chars[i]); i += 1
            }
            // û typed directly and u + combining hat must be the same name.
            return s.precomposedStringWithCanonicalMapping
        }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if isDigit(c) { try scanNumber(); continue }
            if c == ".", i + 1 < chars.count, isDigit(chars[i + 1]) { try scanNumber(); continue }
            if c.isLetter || c == "_" {
                let word = scanIdent()
                tokens.append(word == "vec" ? .vecKeyword : .ident(word))
                continue
            }
            if c == "\\" {
                i += 1
                let cmd = scanIdent()
                switch cmd {
                case "vec", "vector", "overrightarrow": tokens.append(.vecKeyword)
                case "hat": tokens.append(.hatKeyword)
                case "cdot": tokens.append(.dotOp)
                case "times": tokens.append(.crossOp)
                case "langle": tokens.append(.langle)
                case "rangle": tokens.append(.rangle)
                case "pi": tokens.append(.ident("pi"))
                default: throw EvalError("unknown command \\\(cmd)")
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
            default: throw EvalError("unexpected character '\(c)'")
            }
        }
        return tokens
    }
}
