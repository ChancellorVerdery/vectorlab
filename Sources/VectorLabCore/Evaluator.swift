import Foundation

/// Evaluates statements against a growing environment of named values.
/// Pure value semantics: no reference state, safe to rerun from scratch.
struct Evaluator {
    private(set) var env: [String: Value] = [:]

    /// When on (the app default), definitions must use proper notation:
    /// vector values need the \vec mark (or a typed arrow), and hatted
    /// names (û) must hold true unit vectors.
    var strictNotation = false

    static let reservedNames: Set<String> = ["i", "j", "k", "pi", "e", "point", "vec", "origin"]

    static let builtinConstants: [String: Value] = [
        "i": .vector(Vec3(1, 0, 0), anchor: nil),
        "j": .vector(Vec3(0, 1, 0), anchor: nil),
        "k": .vector(Vec3(0, 0, 1), anchor: nil),
        "pi": .scalar(Double.pi),
        "e": .scalar(M_E),
        "origin": .point(.zero),
    ]

    static let functionNames: Set<String> = [
        "unit", "hat", "normalize", "mag", "norm", "length", "abs",
        "dot", "cross", "angle", "proj", "comp", "triple", "moment",
        "dist", "resultant", "sqrt", "sin", "cos", "tan", "asin", "acos",
        "atan", "atan2", "ln", "log", "exp", "deg", "rad",
    ]

    init() {}

    /// Runs a statement; definitions mutate the environment.
    /// Returns nil for blank/comment lines.
    mutating func execute(_ stmt: Statement) throws -> (name: String?, value: Value)? {
        switch stmt {
        case .blank, .comment:
            return nil
        case .definition(let name, let isPoint, let isVec, let expr):
            guard !Self.reservedNames.contains(name) else {
                throw EvalError("'\(name)' is reserved")
            }
            var value = try eval(expr)
            if isPoint {
                value = .point(try value.asPosition("point \(name)"))
            }
            if strictNotation {
                try checkNotation(name: name, isVec: isVec, isPoint: isPoint, value: value)
            }
            env[name] = value
            return (name, value)
        case .expression(let expr):
            return (nil, try eval(expr))
        }
    }

    func eval(_ e: Expr) throws -> Value {
        switch e {
        case .number(let n):
            return .scalar(n)

        case .ident(let name):
            return try resolve(name)

        case .vecLiteral(let parts):
            let comps = try parts.map { try eval($0).asScalar("vector component") }
            return .vector(Vec3(comps[0], comps[1], comps.count == 3 ? comps[2] : 0), anchor: nil)

        case .polar(let magE, let angE):
            let m = try eval(magE).asScalar("magnitude before ∠")
            let a = try eval(angE).asScalar("angle after ∠") * .pi / 180
            return .vector(Vec3(m * Foundation.cos(a), m * Foundation.sin(a), 0), anchor: nil)

        case .magnitude(let inner):
            switch try eval(inner) {
            case .scalar(let s): return .scalar(abs(s))
            case .vector(let v, _): return .scalar(v.length)
            case .point: throw EvalError("|…| needs a vector or number, got a point")
            }

        case .member(let inner, let m):
            let v = try eval(inner).asPosition(".\(m)")
            switch m {
            case "x": return .scalar(v.x)
            case "y": return .scalar(v.y)
            default: return .scalar(v.z)
            }

        case .unaryMinus(let inner):
            switch try eval(inner) {
            case .scalar(let s): return .scalar(-s)
            case .vector(let v, let a): return .vector(-v, anchor: a)
            case .point: throw EvalError("can't negate a point")
            }

        case .binary(let op, let lhsE, let rhsE):
            return try binary(op, try eval(lhsE), try eval(rhsE))

        case .call(let name, let args):
            return try call(name, args)
        }
    }

    // MARK: - Strict notation

    private func checkNotation(name: String, isVec: Bool, isPoint: Bool, value: Value) throws {
        // Scalar-level check: grapheme-based contains() can't see the
        // combining hat inside the û cluster.
        let isHat = name.decomposedStringWithCanonicalMapping.unicodeScalars
            .contains { $0.value == 0x0302 }
        switch value {
        case .vector(let v, _):
            if isHat {
                if abs(v.length - 1) > 1e-6 {
                    throw EvalError("\(name) must be a unit vector, but |\(name)| = \(Fmt.num(v.length)) — wrap the value in unit(…)")
                }
            } else if !isVec {
                throw EvalError("'\(name)' holds a vector — write \\vec \(name) (renders as \(name)\u{20D7}) to use proper notation")
            }
        case .scalar:
            if isHat { throw EvalError("\(name) must be a unit vector, but got a number") }
            if isVec { throw EvalError("\\vec \(name) must be a vector, but got a number") }
        case .point:
            if isHat { throw EvalError("\(name) must be a unit vector, not a point") }
            if isVec, !isPoint { throw EvalError("\\vec \(name) must be a vector, but got a point") }
        }
    }

    // MARK: - Identifier resolution

    private func resolve(_ name: String) throws -> Value {
        if let v = env[name] { return v }
        if let v = Self.builtinConstants[name] { return v }
        if let v = try autoPositionVector(name) { return v }
        if Self.functionNames.contains(name.lowercased()) {
            throw EvalError("'\(name)' is a function — call it like \(name)(…)")
        }
        throw EvalError("'\(name)' is not defined")
    }

    /// r_AB where A and B are defined resolves to B − A, anchored at A.
    private func autoPositionVector(_ name: String) throws -> Value? {
        guard let underscore = name.firstIndex(of: "_") else { return nil }
        let base = String(name[..<underscore])
        guard base == "r" || base == "R" else { return nil }
        let rest = String(name[name.index(after: underscore)...])
        guard rest.count >= 2 else { return nil }

        var candidates: [(Vec3, Vec3)] = []
        for cut in 1..<rest.count {
            let aName = String(rest.prefix(cut))
            let bName = String(rest.dropFirst(cut))
            guard let a = env[aName], let b = env[bName],
                  !a.isScalar, !b.isScalar,
                  let pa = try? a.asPosition("r_"), let pb = try? b.asPosition("r_")
            else { continue }
            candidates.append((pa, pb))
        }
        guard !candidates.isEmpty else {
            throw EvalError("to use \(name), define points \(rest.map(String.init).joined(separator: " and ")) first")
        }
        guard candidates.count == 1 else {
            throw EvalError("\(name) is ambiguous — multiple point splits match")
        }
        let (a, b) = candidates[0]
        return .vector(b - a, anchor: a)
    }

    // MARK: - Operators

    private func binary(_ op: BinOp, _ l: Value, _ r: Value) throws -> Value {
        switch op {
        case .add:
            switch (l, r) {
            case (.scalar(let a), .scalar(let b)): return .scalar(a + b)
            case (.vector(let a, let aa), .vector(let b, let ba)):
                return .vector(a + b, anchor: aa == ba ? aa : nil)
            case (.point(let p), .vector(let v, _)), (.vector(let v, _), .point(let p)):
                return .point(p + v)
            case (.point, .point): throw EvalError("can't add two points — subtract them to get a vector")
            default: throw EvalError("can't add \(l.typeName) and \(r.typeName)")
            }

        case .sub:
            switch (l, r) {
            case (.scalar(let a), .scalar(let b)): return .scalar(a - b)
            case (.vector(let a, let aa), .vector(let b, let ba)):
                return .vector(a - b, anchor: aa == ba ? aa : nil)
            case (.point(let p), .point(let q)):
                return .vector(p - q, anchor: q)   // B - A: vector from A to B, drawn at A
            case (.point(let p), .vector(let v, _)): return .point(p - v)
            default: throw EvalError("can't subtract \(r.typeName) from \(l.typeName)")
            }

        case .mul:
            switch (l, r) {
            case (.scalar(let a), .scalar(let b)): return .scalar(a * b)
            case (.scalar(let s), .vector(let v, let a)): return .vector(s * v, anchor: a)
            case (.vector(let v, let a), .scalar(let s)): return .vector(s * v, anchor: a)
            case (.vector(let a, _), .vector(let b, _)): return .scalar(a.dot(b))   // v*v = dot
            default: throw EvalError("can't multiply \(l.typeName) and \(r.typeName) — subtract points to get vectors first")
            }

        case .dotProduct:
            switch (l, r) {
            case (.scalar(let a), .scalar(let b)): return .scalar(a * b)
            case (.vector(let a, _), .vector(let b, _)): return .scalar(a.dot(b))
            // 2 · v is plain scaling — mathprint rewrites * as ·, so the
            // rendered text must evaluate identically to the typed text.
            case (.scalar(let s), .vector(let v, let a)): return .vector(s * v, anchor: a)
            case (.vector(let v, let a), .scalar(let s)): return .vector(s * v, anchor: a)
            default: throw EvalError("dot product needs two vectors, got \(l.typeName) and \(r.typeName)")
            }

        case .crossProduct:
            guard case .vector(let a, _) = l, case .vector(let b, _) = r else {
                throw EvalError("cross product needs two vectors, got \(l.typeName) and \(r.typeName)")
            }
            return .vector(a.cross(b), anchor: nil)

        case .div:
            switch (l, r) {
            case (.scalar(let a), .scalar(let b)):
                guard b != 0 else { throw EvalError("division by zero") }
                return .scalar(a / b)
            case (.vector(let v, let a), .scalar(let s)):
                guard s != 0 else { throw EvalError("division by zero") }
                return .vector(v / s, anchor: a)
            default: throw EvalError("can't divide \(l.typeName) by \(r.typeName)")
            }

        case .pow:
            guard case .scalar(let a) = l, case .scalar(let b) = r else {
                throw EvalError("'^' needs numbers — for vectors use v*v or mag(v)^2")
            }
            return .scalar(Foundation.pow(a, b))
        }
    }

    // MARK: - Functions (trig is degree-based; inverse trig returns degrees)

    private func call(_ rawName: String, _ argExprs: [Expr]) throws -> Value {
        let name = rawName.lowercased()
        let args = try argExprs.map { try eval($0) }

        func arity(_ n: Int) throws {
            guard args.count == n else { throw EvalError("\(rawName)(…) takes \(n) argument\(n == 1 ? "" : "s")") }
        }
        func vec(_ idx: Int) throws -> Vec3 { try args[idx].asVector("\(rawName)(…) argument \(idx + 1)") }
        func num(_ idx: Int) throws -> Double { try args[idx].asScalar("\(rawName)(…) argument \(idx + 1)") }

        switch name {
        case "unit", "hat", "normalize":
            try arity(1)
            guard case .vector(let v, let a) = args[0] else {
                throw EvalError("\(rawName)(…) needs a vector, got \(args[0].typeName)")
            }
            guard let u = v.normalized else { throw EvalError("can't take the unit of a zero vector") }
            return .vector(u, anchor: a)

        case "mag", "norm", "length":
            try arity(1)
            return .scalar(try vec(0).length)

        case "abs":
            try arity(1)
            switch args[0] {
            case .scalar(let s): return .scalar(Swift.abs(s))
            case .vector(let v, _): return .scalar(v.length)
            case .point: throw EvalError("abs(…) needs a number or vector")
            }

        case "dot":
            try arity(2)
            return .scalar(try vec(0).dot(try vec(1)))

        case "cross":
            try arity(2)
            return .vector(try vec(0).cross(try vec(1)), anchor: nil)

        case "angle":
            try arity(2)
            let a = try vec(0), b = try vec(1)
            guard let ua = a.normalized, let ub = b.normalized else {
                throw EvalError("angle(…) needs nonzero vectors")
            }
            let c = min(1, max(-1, ua.dot(ub)))
            return .scalar(Foundation.acos(c) * 180 / .pi)

        case "proj":   // vector projection of a onto b
            try arity(2)
            let a = try vec(0), b = try vec(1)
            let bb = b.dot(b)
            guard bb > 1e-24 else { throw EvalError("can't project onto a zero vector") }
            return .vector((a.dot(b) / bb) * b, anchor: nil)

        case "comp":   // scalar component of a along b
            try arity(2)
            let a = try vec(0), b = try vec(1)
            guard let ub = b.normalized else { throw EvalError("can't project onto a zero vector") }
            return .scalar(a.dot(ub))

        case "triple":   // a · (b × c)
            try arity(3)
            return .scalar(try vec(0).dot(try vec(1).cross(try vec(2))))

        case "moment":
            if args.count == 2 {                       // M = r × F
                return .vector(try vec(0).cross(try vec(1)), anchor: nil)
            }
            try arity(3)                               // moment(axis, r, F): scalar about axis
            guard let ua = try vec(0).normalized else { throw EvalError("moment axis can't be zero") }
            return .scalar(ua.dot(try vec(1).cross(try vec(2))))

        case "dist":
            try arity(2)
            let a = try args[0].asPosition("dist(…) argument 1")
            let b = try args[1].asPosition("dist(…) argument 2")
            return .scalar((b - a).length)

        case "resultant":
            guard !args.isEmpty else { throw EvalError("resultant(…) needs at least one vector") }
            var sum = Vec3.zero
            for (idx, v) in args.enumerated() {
                sum = sum + (try v.asVector("resultant(…) argument \(idx + 1)"))
            }
            return .vector(sum, anchor: nil)

        case "sqrt":
            try arity(1)
            let x = try num(0)
            guard x >= 0 else { throw EvalError("sqrt of a negative number") }
            return .scalar(x.squareRoot())

        case "sin": try arity(1); return .scalar(Foundation.sin(try num(0) * .pi / 180))
        case "cos": try arity(1); return .scalar(Foundation.cos(try num(0) * .pi / 180))
        case "tan": try arity(1); return .scalar(Foundation.tan(try num(0) * .pi / 180))

        case "asin", "acos":
            try arity(1)
            let x = try num(0)
            guard (-1...1).contains(x) else { throw EvalError("\(name)(…) needs a value in [-1, 1]") }
            return .scalar((name == "asin" ? Foundation.asin(x) : Foundation.acos(x)) * 180 / .pi)

        case "atan": try arity(1); return .scalar(Foundation.atan(try num(0)) * 180 / .pi)
        case "atan2": try arity(2); return .scalar(Foundation.atan2(try num(0), try num(1)) * 180 / .pi)

        case "ln":
            try arity(1)
            let x = try num(0)
            guard x > 0 else { throw EvalError("ln of a non-positive number") }
            return .scalar(Foundation.log(x))
        case "log":
            try arity(1)
            let x = try num(0)
            guard x > 0 else { throw EvalError("log of a non-positive number") }
            return .scalar(Foundation.log10(x))
        case "exp": try arity(1); return .scalar(Foundation.exp(try num(0)))

        case "deg": try arity(1); return .scalar(try num(0) * 180 / .pi)   // radians → degrees
        case "rad": try arity(1); return .scalar(try num(0) * .pi / 180)   // degrees → radians

        default:
            throw EvalError("unknown function '\(rawName)'")
        }
    }
}

private extension Value {
    var isScalar: Bool { if case .scalar = self { return true }; return false }
}
