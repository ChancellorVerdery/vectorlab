import Foundation

enum Token: Equatable {
    case number(Double)
    case ident(String)
    case vecKeyword          // \vec, \vector, \hat, or plain "vec" — cosmetic prefix
    case plus, minus, star, slash, caret, equals, comma
    case lparen, rparen, langle, rangle, lbracket, rbracket
    case pipe, angleOp, dotOp, crossOp, degree, memberDot
}

enum Lexer {
    static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0

        func scanNumber() {
            var s = ""
            while i < chars.count, chars[i].isNumber || chars[i] == "." {
                s.append(chars[i]); i += 1
            }
            if i < chars.count, chars[i] == "e" || chars[i] == "E",
               i + 1 < chars.count, chars[i + 1].isNumber || ((chars[i + 1] == "+" || chars[i + 1] == "-") && i + 2 < chars.count && chars[i + 2].isNumber) {
                s.append(chars[i]); i += 1
                if chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
                while i < chars.count, chars[i].isNumber { s.append(chars[i]); i += 1 }
            }
            tokens.append(.number(Double(s) ?? 0))
        }

        func scanIdent() -> String {
            var s = ""
            while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                s.append(chars[i]); i += 1
            }
            return s
        }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber { scanNumber(); continue }
            if c == ".", i + 1 < chars.count, chars[i + 1].isNumber { scanNumber(); continue }
            if c.isLetter || c == "_" {
                let word = scanIdent()
                tokens.append(word == "vec" ? .vecKeyword : .ident(word))
                continue
            }
            if c == "\\" {
                i += 1
                let cmd = scanIdent()
                switch cmd {
                case "vec", "vector", "hat", "overrightarrow": tokens.append(.vecKeyword)
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
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
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
