import Foundation

indirect enum Expr: Equatable {
    case number(Double)
    case ident(String)
    case call(String, [Expr])
    case vecLiteral([Expr])      // ⟨…⟩ or […]; 2 or 3 components, 2 means z = 0
    case pointLiteral([Expr])    // (x, y[, z]) — parens are coordinates, a point
    case polar(Expr, Expr)       // magnitude ∠ angle(degrees), in the XY plane
    case magnitude(Expr)         // |v|
    case member(Expr, String)    // v.x  v.y  v.z
    case unaryMinus(Expr)
    case binary(BinOp, Expr, Expr)
}

enum BinOp: Equatable {
    case add, sub, mul, div, pow, dotProduct, crossProduct
}

enum Statement: Equatable {
    case blank
    case comment(String)
    case definition(name: String, isPoint: Bool, isVec: Bool, expr: Expr)
    case expression(Expr)
}

struct Parser {
    private let tokens: [Token]
    private var i = 0

    static func parseLine(_ line: String) throws -> Statement {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { return .comment(trimmed) }

        var p = Parser(tokens: try Self.foldHats(Lexer.tokenize(trimmed)))
        return try p.statement()
    }

    /// \hat u (also \hat(u) and \hat{u}) collapses to the single distinct
    /// identifier û before parsing, so hats work anywhere a name does.
    private static func foldHats(_ tokens: [Token]) throws -> [Token] {
        var out: [Token] = []
        var i = 0
        while i < tokens.count {
            guard tokens[i] == .hatKeyword else {
                out.append(tokens[i])
                i += 1
                continue
            }
            var j = i + 1
            let wrapped = j < tokens.count && tokens[j] == .lparen
            if wrapped { j += 1 }
            guard j < tokens.count, case .ident(let n) = tokens[j] else {
                throw EvalError("\\hat takes a single name, like \\hat u or \\hat(u)")
            }
            j += 1
            if wrapped {
                guard j < tokens.count, tokens[j] == .rparen else {
                    throw EvalError("\\hat takes a single name, like \\hat u or \\hat(u)")
                }
                j += 1
            }
            out.append(.ident((n + "\u{0302}").precomposedStringWithCanonicalMapping))
            i = j
        }
        return out
    }

    private init(tokens: [Token]) { self.tokens = tokens }

    private var peek: Token? { i < tokens.count ? tokens[i] : nil }
    private func peek(_ ahead: Int) -> Token? { i + ahead < tokens.count ? tokens[i + ahead] : nil }
    private mutating func advance() -> Token? {
        defer { i += 1 }
        return peek
    }

    private mutating func expect(_ t: Token, _ what: String) throws {
        guard peek == t else { throw EvalError("expected \(what)") }
        i += 1
    }

    private mutating func statement() throws -> Statement {
        var isVec = false
        if peek == .vecKeyword {   // \vec F = ...,  F⃗ = ...,  or bare  \vec r_AB
            isVec = true
            i += 1
        }

        var isPoint = false
        if case .ident("point") = peek ?? .comma,
           case .ident = peek(1) ?? .comma, peek(2) == .equals {
            isPoint = true
            i += 1
            if peek == .vecKeyword { isVec = true; i += 1 }
        }

        if case .ident(let name) = peek ?? .comma, peek(1) == .equals {
            i += 2
            let e = try expression()
            try expectEnd()
            return .definition(name: name, isPoint: isPoint, isVec: isVec, expr: e)
        }
        if isPoint { throw EvalError("expected: point NAME = (x, y, z)") }

        let e = try expression()
        try expectEnd()
        return .expression(e)
    }

    private mutating func expectEnd() throws {
        if let t = peek { throw EvalError("unexpected trailing input near \(describe(t))") }
    }

    private func describe(_ t: Token) -> String {
        switch t {
        case .number(let n): return "'\(Fmt.num(n))'"
        case .ident(let s): return "'\(s)'"
        default: return "'\(t)'"
        }
    }

    // MARK: - Expression grammar (precedence low → high)

    private mutating func expression() throws -> Expr { try additive() }

    private mutating func additive() throws -> Expr {
        var lhs = try multiplicative()
        while let t = peek, t == .plus || t == .minus {
            i += 1
            let rhs = try multiplicative()
            lhs = .binary(t == .plus ? .add : .sub, lhs, rhs)
        }
        return lhs
    }

    /// Starters that allow implicit multiplication after a NUMBER literal:
    /// 3i, 2x, 2(a+b), 4⟨1,0,0⟩. `|` is excluded (breaks closing-pipe
    /// detection), and numbers are excluded so a missed comma (`<1 2, 3>`)
    /// or missed operator (`100 200`) errors instead of silently multiplying.
    private func startsImplicitFactor(_ t: Token) -> Bool {
        switch t {
        case .ident, .lparen, .langle, .lbracket: return true
        default: return false
        }
    }

    /// True when the token just consumed can be the left side of an implicit
    /// multiply: a number literal (3i, 2x) or a closing paren — engineers
    /// write cos(theta)i + sin(theta)j.
    private func previousTokenAllowsImplicitMul() -> Bool {
        guard i > 0 else { return false }
        switch tokens[i - 1] {
        case .number, .rparen: return true
        default: return false
        }
    }

    private mutating func multiplicative() throws -> Expr {
        var lhs = try polarTerm()
        loop: while let t = peek {
            let op: BinOp
            switch t {
            case .star: op = .mul
            case .slash: op = .div
            case .dotOp: op = .dotProduct
            case .crossOp: op = .crossProduct
            default:
                // ponytail: juxtaposition multiplies only after a number or `)`
                // (3i, 2x, cos(t)i); ident chains like `2 pi r` need explicit `*`
                if startsImplicitFactor(t), previousTokenAllowsImplicitMul() {
                    op = .mul
                } else {
                    break loop
                }
            }
            if t == .star || t == .slash || t == .dotOp || t == .crossOp { i += 1 }
            let rhs = try polarTerm()
            lhs = .binary(op, lhs, rhs)
        }
        return lhs
    }

    private mutating func polarTerm() throws -> Expr {
        let lhs = try unary()
        if peek == .angleOp {
            i += 1
            var angle = try unary()
            // Fold 10∠2theta / 10∠2(…): implicit multiply inside the angle operand,
            // which sits below multiplicative() and would otherwise miss it.
            while let t = peek, t == .lparen || isIdentToken(t), previousTokenAllowsImplicitMul() {
                angle = .binary(.mul, angle, try unary())
            }
            return .polar(lhs, angle)
        }
        return lhs
    }

    private func isIdentToken(_ t: Token) -> Bool {
        if case .ident = t { return true }
        return false
    }

    private mutating func unary() throws -> Expr {
        if peek == .minus {
            i += 1
            return .unaryMinus(try unary())
        }
        if peek == .plus { i += 1; return try unary() }
        return try power()
    }

    private mutating func power() throws -> Expr {
        let base = try postfix()
        if peek == .caret {
            i += 1
            let exp = try unary()   // right-associative, allows 2^-3
            return .binary(.pow, base, exp)
        }
        return base
    }

    private mutating func postfix() throws -> Expr {
        var e = try primary()
        loop: while let t = peek {
            switch t {
            case .memberDot:
                i += 1
                guard case .ident(let m)? = peek, ["x", "y", "z"].contains(m) else {
                    throw EvalError("expected .x, .y or .z")
                }
                i += 1
                e = .member(e, m)
            case .degree:
                i += 1   // trig is degree-based already; ° is cosmetic
            default:
                break loop
            }
        }
        return e
    }

    private mutating func primary() throws -> Expr {
        guard let t = peek else { throw EvalError("unexpected end of input") }
        switch t {
        case .number(let n):
            i += 1
            return .number(n)

        case .ident(let name):
            i += 1
            if peek == .lparen {
                i += 1
                var args: [Expr] = []
                if peek != .rparen {
                    repeat {
                        args.append(try expression())
                        if peek == .comma { i += 1 } else { break }
                    } while true
                }
                try expect(.rparen, "')'")
                return .call(name, args)
            }
            return .ident(name)

        case .lparen:
            i += 1
            var parts = [try expression()]
            while peek == .comma {
                i += 1
                parts.append(try expression())
            }
            try expect(.rparen, "')'")
            if parts.count == 1 { return parts[0] }
            guard parts.count <= 3 else { throw EvalError("points have at most 3 coordinates") }
            return .pointLiteral(parts)

        case .langle, .lbracket:
            let closing: Token = (t == .langle) ? .rangle : .rbracket
            i += 1
            var parts = [try expression()]
            while peek == .comma {
                i += 1
                parts.append(try expression())
            }
            try expect(closing, t == .langle ? "'>'" : "']'")
            guard (2...3).contains(parts.count) else {
                throw EvalError("vectors need 2 or 3 components")
            }
            return .vecLiteral(parts)

        case .pipe:
            i += 1
            let inner = try additive()
            try expect(.pipe, "closing '|'")
            return .magnitude(inner)

        case .vecKeyword:
            i += 1   // stray \vec inside an expression: cosmetic
            return try primary()

        default:
            throw EvalError("unexpected \(describe(t))")
        }
    }
}
