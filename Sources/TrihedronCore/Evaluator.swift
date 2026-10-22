import Foundation

/// Evaluates statements against a growing environment of named values.
/// Pure value semantics: no reference state, safe to rerun from scratch.
struct Evaluator {
    var env: [String: Value] = [:]

    /// Names the notebook has turned into graphs (`y = x^2` with x unbound).
    /// A graph is not a Value, so the name leaves `env` and lands here, and
    /// reading it back gets a message that says what it is.
    private(set) var graphs: Set<String> = []

    /// The three names that become graph variables when nothing binds them.
    static let axisNames = ["x", "y", "z"]

    /// When on (the app default), definitions must use proper notation:
    /// vector values need the \vec mark (or a typed arrow), and hatted
    /// names (û) must hold true unit vectors.
    var strictNotation = false

    static let reservedNames: Set<String> = [
        "i", "j", "k", "î", "ĵ", "k\u{0302}", "pi", "e", "point", "vec", "origin",
    ]

    static let builtinConstants: [String: Value] = [
        "i": .vector(Vec3(1, 0, 0), anchor: nil),
        "j": .vector(Vec3(0, 1, 0), anchor: nil),
        "k": .vector(Vec3(0, 0, 1), anchor: nil),
        // Hatted basis vectors — standard statics notation. k̂ has no
        // precomposed Unicode form, hence the combining-mark spelling.
        "î": .vector(Vec3(1, 0, 0), anchor: nil),
        "ĵ": .vector(Vec3(0, 1, 0), anchor: nil),
        "k\u{0302}": .vector(Vec3(0, 0, 1), anchor: nil),
        "pi": .scalar(Double.pi),
        "e": .scalar(M_E),
        "origin": .point(.zero),
    ]

    static let functionNames: Set<String> = [
        "unit", "hat", "normalize", "mag", "norm", "length", "abs",
        "dot", "cross", "angle", "proj", "comp", "triple", "moment",
        "dist", "resultant", "sqrt", "sin", "cos", "tan", "asin", "acos",
        "atan", "atan2", "ln", "log", "exp", "deg", "rad", "point", "vector",
    ]

    init() {}

    enum Execution: Equatable {
        case skipped
        case value(name: String?, value: Value)
        /// The line is a graph; sampling it is the Engine's job, since the
        /// default domain depends on lines that have not run yet.
        case graph(GraphSpec)
    }

    /// Runs a statement; definitions mutate the environment.
    mutating func run(_ stmt: Statement) throws -> Execution {
        switch stmt {
        case .blank, .comment:
            return .skipped
        case .definition(let name, let isPoint, let isVec, let expr, let domain):
            guard !Self.reservedNames.contains(name) else {
                throw EvalError("'\(name)' is reserved")
            }
            let free = freeAxisVariables(in: expr)
            guard free.isEmpty else {
                return .graph(try graphSpec(name: name, isPoint: isPoint, isVec: isVec,
                                            expr: expr, free: free, domain: domain))
            }
            if let clause = domain.first {
                throw EvalError("'\(clause.name)' is not a free variable here, so there is nothing to graph — remove the domain, or the earlier line that defines \(clause.name)")
            }
            var value = try eval(expr)
            if isPoint {
                value = .point(try value.asPosition("point \(name)"))
            }
            if strictNotation {
                try checkNotation(name: name, isVec: isVec, isPoint: isPoint, value: value)
            }
            graphs.remove(name)
            env[name] = value
            return .value(name: name, value: value)
        case .expression(let expr):
            return .value(name: nil, value: try eval(expr))
        }
    }

    /// Runs a statement; definitions mutate the environment.
    /// Returns nil for blank/comment lines. A graph line has no value.
    mutating func execute(_ stmt: Statement) throws -> (name: String?, value: Value)? {
        switch try run(stmt) {
        case .skipped: return nil
        case .value(let name, let value): return (name, value)
        case .graph(let spec): throw EvalError("\(spec.dependent) = … is a graph, not a value")
        }
    }

    // MARK: - Graphs

    /// Axis names the expression mentions that nothing above has defined,
    /// in axis order. Empty for every line that evaluated before graphing
    /// existed, so those lines run exactly as they always did.
    func freeAxisVariables(in expr: Expr) -> [String] {
        var found: Set<String> = []
        func walk(_ e: Expr) {
            switch e {
            case .number:
                break
            case .ident(let n):
                if Self.axisNames.contains(n), env[n] == nil { found.insert(n) }
            case .call(_, let parts), .vecLiteral(let parts), .pointLiteral(let parts):
                parts.forEach(walk)
            case .polar(let a, let b), .binary(_, let a, let b):
                walk(a)
                walk(b)
            case .magnitude(let a), .member(let a, _), .unaryMinus(let a):
                walk(a)
            }
        }
        walk(expr)
        return Self.axisNames.filter(found.contains)
    }

    private mutating func graphSpec(name: String, isPoint: Bool, isVec: Bool, expr: Expr,
                                    free: [String], domain: [DomainClause]) throws -> GraphSpec {
        guard Self.axisNames.contains(name) else {
            throw EvalError("'\(free[0])' is not defined — to graph an expression in \(free[0]), put the axis it maps to on the left: y = … or z = …")
        }
        guard !free.contains(name) else {
            throw EvalError("\(name) = … can't depend on \(name) itself — pick another axis for the left side")
        }
        if isPoint { throw EvalError("point \(name) = … can't be a graph — drop the point keyword") }
        if isVec { throw EvalError("\\vec \(name) = … can't be a graph — a curve is not a vector, drop the \\vec") }

        var explicit: [String: ClosedRange<Double>] = [:]
        for clause in domain {
            guard free.contains(clause.name) else {
                throw EvalError("'\(clause.name)' is not a graph variable here — this line graphs over \(free.joined(separator: " and "))")
            }
            guard explicit[clause.name] == nil else {
                throw EvalError("\(clause.name) has two domains")
            }
            let lo = try eval(clause.lo).asScalar("the lower bound of \(clause.name)")
            let hi = try eval(clause.hi).asScalar("the upper bound of \(clause.name)")
            guard lo.isFinite, hi.isFinite, lo < hi else {
                throw EvalError("the domain of \(clause.name) needs lo < hi, got [\(Fmt.num(lo)), \(Fmt.num(hi))]")
            }
            explicit[clause.name] = lo...hi
        }
        env[name] = nil
        graphs.insert(name)
        return GraphSpec(dependent: name, expr: expr, free: free, explicit: explicit)
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

        case .pointLiteral(let parts):
            let comps = try parts.map { try eval($0).asScalar("point coordinate") }
            return .point(Vec3(comps[0], comps[1], comps.count == 3 ? comps[2] : 0))

        case .polar(let magE, let angE):
            let m = try eval(magE).asScalar("magnitude before ∠")
            let a = try eval(angE).asScalar("angle after ∠")
            // Trig, not Foundation: m ∠ 90 must be straight up with an x of
            // exactly 0, not 6.1232e-17 · m.
            return .vector(Vec3(m * Trig.cos(a), m * Trig.sin(a), 0), anchor: nil)

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
            // Missing \vec is no longer an error — the app applies the
            // notation automatically (arrow, or hat for unit magnitude).
            // Phrased as !(… <= …) so a NaN or infinite magnitude fails the
            // check: every comparison against NaN is false.
            if isHat, !(abs(v.length - 1) <= 1e-6) {
                throw EvalError("\(name) must be a unit vector, but |\(name)| = \(Fmt.num(v.length)) — wrap the value in unit(…)")
            }
        case .scalar:
            if isHat { throw EvalError("\(name) must be a unit vector, but got a number") }
            if isVec { throw EvalError("\\vec \(name) must be a vector, but got a number") }
        case .point:
            if isHat { throw EvalError("\(name) must be a unit vector, not a point") }
            if isVec, !isPoint {
                throw EvalError("\\vec \(name) must be a vector — parentheses (x, y, z) make a point; use ⟨x, y, z⟩ for a vector")
            }
        }
    }

    // MARK: - Identifier resolution

    private func resolve(_ name: String) throws -> Value {
        if let v = env[name] { return v }
        if graphs.contains(name) {
            throw EvalError("'\(name)' is a graph here, not a number — a curve can't be used in arithmetic")
        }
        if let v = Self.builtinConstants[name] { return v }
        if let v = try autoPositionVector(name) { return v }
        if Self.functionNames.contains(name.lowercased()) {
            throw EvalError("'\(name)' is a function — call it like \(name)(…)")
        }
        // The app hats unit vectors automatically, so a defined `u` is
        // DISPLAYED as û — typing û back must find it (if truly unit).
        let base = name.decomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{0302}", with: "")
            .precomposedStringWithCanonicalMapping
        if base != name, let v = env[base] {
            if case .vector(let vec, _) = v, abs(vec.length - 1) <= 1e-6 { return v }
            throw EvalError("'\(name)' is the unit-vector form of \(base), but \(base) is not a unit vector")
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
        var anyEndpointKnown = false
        for cut in 1..<rest.count {
            let a = endpointPosition(String(rest.prefix(cut)))
            let b = endpointPosition(String(rest.dropFirst(cut)))
            if a != nil || b != nil { anyEndpointKnown = true }
            guard let pa = a, let pb = b else { continue }
            candidates.append((pa, pb))
        }
        guard !candidates.isEmpty else {
            // Nothing on either side of any split names a place, so this is an
            // ordinary undefined name that happens to start r_ — a reaction
            // force called R_max should not be told to "define points m, a, x".
            guard anyEndpointKnown else { return nil }
            throw EvalError("to use \(name), define points \(rest.map(String.init).joined(separator: " and ")) first")
        }
        guard candidates.count == 1 else {
            throw EvalError("\(name) is ambiguous — multiple point splits match")
        }
        let (a, b) = candidates[0]
        return .vector(b - a, anchor: a)
    }

    /// A name usable as an endpoint of r_AB: any defined non-scalar, plus the
    /// builtin `origin`. Only `origin` is taken from the builtins — i, j and k
    /// are directions rather than places, and r_ij is not a position vector.
    private func endpointPosition(_ name: String) -> Vec3? {
        let value: Value
        if let defined = env[name] { value = defined }
        else if name == "origin" { value = .point(.zero) }
        else { return nil }
        guard !value.isScalar else { return nil }
        return try? value.asPosition("r_")
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
            // pow(-8, 1/3) is NaN, not -2 — real powers of a negative base
            // need a whole exponent. Say that instead of printing NaN.
            guard a >= 0 || b == b.rounded() else {
                // Parenthesised: bare -8^0.3333 re-parses as -(8^0.3333), a
                // valid expression and not the one being refused. An error in
                // a teaching tool has to model notation the tool accepts.
                throw EvalError("a negative base needs a whole exponent — (\(Fmt.num(a)))^\(Fmt.num(b)) is undefined")
            }
            // 0^-1 IS 1/0. `/` has named that "division by zero" since the
            // start; written as an exponent the same question printed ∞.
            guard !(a == 0 && b < 0) else { throw EvalError("division by zero") }
            return .scalar(Foundation.pow(a, b))
        }
    }

    /// normalized() answers nil for two different mistakes — the zero vector
    /// and a vector with a NaN or infinite component — and every caller used
    /// to blame the first. `unit(<1e400, 0, 0>)` read "can't take the unit of
    /// a zero vector", which sends the reader hunting in the wrong place.
    private func direction(of v: Vec3, _ complaint: String) throws -> Vec3 {
        guard v.isFinite else {
            throw EvalError("\(complaint) \(Fmt.vector(v)) — it has no direction")
        }
        guard let u = v.normalized else { throw EvalError("\(complaint) a zero vector") }
        return u
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
            let u = try direction(of: v, "can't take the unit of")
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
            let av = try direction(of: try vec(0), "can't measure the angle of")
            let bv = try direction(of: try vec(1), "can't measure the angle of")
            guard let radians = av.angle(to: bv) else {
                throw EvalError("angle(…) needs nonzero vectors")
            }
            return .scalar(radians * 180 / .pi)

        case "proj":   // vector projection of a onto b
            try arity(2)
            let a = try vec(0), b = try vec(1)
            // (a·b̂)b̂ rather than (a·b / b·b)b: b·b underflows to zero for
            // perfectly ordinary small vectors, so proj(<1,0,0>, <1e-20,0,0>)
            // raised "can't project onto a zero vector" while comp(…) on the
            // same pair answered 1. Both now accept exactly what unit() does.
            let ub = try direction(of: b, "can't project onto")
            return .vector(a.dot(ub) * ub, anchor: nil)

        case "comp":   // scalar component of a along b
            try arity(2)
            let a = try vec(0), b = try vec(1)
            let ub = try direction(of: b, "can't project onto")
            return .scalar(a.dot(ub))

        case "triple":   // a · (b × c)
            try arity(3)
            return .scalar(try vec(0).dot(try vec(1).cross(try vec(2))))

        case "moment":
            if args.count == 2 {                       // M = r × F
                return .vector(try vec(0).cross(try vec(1)), anchor: nil)
            }
            // moment(axis, r, F): scalar about an axis. Spell out both forms —
            // "takes 3 arguments" is wrong when moment(r, F) is also valid.
            guard args.count == 3 else {
                throw EvalError("moment(…) takes moment(r, F) or moment(axis, r, F)")
            }
            let ua = try direction(of: try vec(0), "the moment axis can't be")
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

        // Degree-based and exact on the quadrant multiples — see Trig.
        case "sin": try arity(1); return .scalar(Trig.sin(try num(0)))
        case "cos": try arity(1); return .scalar(Trig.cos(try num(0)))
        case "tan":
            try arity(1)
            let t = try num(0)
            guard let value = Trig.tan(t) else {
                throw EvalError("tan(\(Fmt.num(t))°) is undefined — the tangent is vertical there")
            }
            return .scalar(value)

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

        case "point":   // vector → point at those coordinates (points pass through)
            try arity(1)
            return .point(try args[0].asPosition("point(…)"))

        case "vector":  // point → its position vector from the origin (vectors pass through)
            try arity(1)
            switch args[0] {
            case .vector: return args[0]
            case .point(let p): return .vector(p, anchor: nil)
            case .scalar: throw EvalError("vector(…) needs a point or vector, got a number")
            }

        default:
            throw EvalError("unknown function '\(rawName)'")
        }
    }
}

private extension Value {
    var isScalar: Bool { if case .scalar = self { return true }; return false }
}
