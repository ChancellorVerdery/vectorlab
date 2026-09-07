import Foundation

/// Something the 3D scene can draw for a line.
public struct Drawable: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case arrow(tail: Vec3, vector: Vec3)
        case point(Vec3)
    }
    public var shape: Shape
    public var label: String?

    public init(shape: Shape, label: String?) {
        self.shape = shape
        self.label = label
    }
}

/// An angle arc between two vectors, drawn when a line computes angle(a, b).
public struct ArcSpec: Equatable, Sendable {
    public var origin: Vec3
    public var from: Vec3
    public var to: Vec3
    public var degrees: Double

    public init(origin: Vec3, from: Vec3, to: Vec3, degrees: Double) {
        self.origin = origin
        self.from = from
        self.to = to
        self.degrees = degrees
    }
}

/// Notation the app draws over a defined name, derived from its VALUE:
/// arrow for vectors, hat for unit vectors. Updates automatically when
/// upstream variables change the value.
public enum LineDecoration: Equatable, Sendable {
    case vectorArrow
    case unitHat
}

public struct LineOutcome: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case blank
        case comment
        case ok
        case error(String)
    }
    public var status: Status
    public var resultText: String
    public var drawable: Drawable?
    public var arc: ArcSpec?
    public var decoration: LineDecoration?

    public var errorMessage: String? {
        if case .error(let m) = status { return m }
        return nil
    }
}

public enum Engine {
    /// Evaluates all lines top to bottom against a fresh environment.
    /// Never throws: bad lines produce .error outcomes and evaluation continues.
    /// strictNotation (the default) requires \vec marks on vector definitions
    /// and true unit magnitude for hatted names — the app's teaching mode.
    public static func evaluate(_ lines: [String], strictNotation: Bool = true) -> [LineOutcome] {
        var evaluator = Evaluator()
        evaluator.strictNotation = strictNotation
        return lines.map { line in
            do {
                let stmt = try Parser.parseLine(line)
                // Evaluator is a struct, so this is a cheap snapshot of the
                // environment BEFORE the line runs. arc(for:) re-evaluates the
                // two arguments, and doing that against the post-execute
                // environment made a self-redefining line read the value it had
                // just written: `a = angle(a, b)` turns `a` into a scalar, the
                // vector guard fails, and the arc silently vanished from the one
                // line that is literally an angle measurement.
                let before = evaluator
                guard let (name, value) = try evaluator.execute(stmt) else {
                    return LineOutcome(
                        status: line.trimmingCharacters(in: .whitespaces).isEmpty ? .blank : .comment,
                        resultText: "", drawable: nil, arc: nil, decoration: nil)
                }
                let drawable = Self.drawable(for: value, name: name, sourceLine: line)
                let arc = Self.arc(for: stmt, evaluator: before)
                return LineOutcome(status: .ok, resultText: Fmt.value(value), drawable: drawable,
                                   arc: arc, decoration: Self.decoration(for: value, name: name))
            } catch let err as EvalError {
                return LineOutcome(status: .error(err.message), resultText: "", drawable: nil,
                                   arc: nil, decoration: nil)
            } catch {
                return LineOutcome(status: .error("\(error)"), resultText: "", drawable: nil,
                                   arc: nil, decoration: nil)
            }
        }
    }

    /// Definitions get notation derived from their value. Explicitly hatted
    /// names (û) already wear their notation in the glyph — skip those.
    private static func decoration(for value: Value, name: String?) -> LineDecoration? {
        guard let name, case .vector(let v, _) = value else { return nil }
        let isHattedName = name.decomposedStringWithCanonicalMapping.unicodeScalars
            .contains { $0.value == 0x0302 }
        guard !isHattedName else { return nil }
        return abs(v.length - 1) <= 1e-6 ? .unitHat : .vectorArrow
    }

    private static func drawable(for value: Value, name: String?, sourceLine: String) -> Drawable? {
        switch value {
        case .scalar:
            return nil
        case .vector(let v, let anchor):
            let tail = anchor ?? .zero
            // Overflowed values still show as text (∞) but are never drawn.
            guard v.isFinite, tail.isFinite else { return nil }
            let label = name ?? shortLabel(sourceLine)
            return Drawable(shape: .arrow(tail: tail, vector: v), label: label)
        case .point(let p):
            guard p.isFinite else { return nil }
            return Drawable(shape: .point(p), label: name ?? shortLabel(sourceLine))
        }
    }

    private static func shortLabel(_ line: String) -> String? {
        var t = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["\\vector", "\\vec", "\\hat", "\\overrightarrow", "vec "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return t.count <= 18 ? t : nil
    }

    /// Lines of the form angle(a, b) (bare or assigned) get an angle arc.
    private static func arc(for stmt: Statement, evaluator: Evaluator) -> ArcSpec? {
        let expr: Expr
        switch stmt {
        case .expression(let e): expr = e
        case .definition(_, _, _, let e): expr = e
        default: return nil
        }
        guard case .call(let fn, let args) = expr, fn.lowercased() == "angle", args.count == 2,
              case .vector(let a, let aAnchor)? = try? evaluator.eval(args[0]),
              case .vector(let b, let bAnchor)? = try? evaluator.eval(args[1]),
              let radians = a.angle(to: b)
        else { return nil }
        let deg = radians * 180 / .pi
        let origin = (aAnchor != nil && aAnchor == bAnchor) ? aAnchor! : .zero
        // drawable(for:) already refuses to draw non-finite geometry; arcs were
        // the one shape that did not, so an overflowed anchor reached the scene.
        guard origin.isFinite, a.isFinite, b.isFinite, deg.isFinite else { return nil }
        return ArcSpec(origin: origin, from: a, to: b, degrees: deg)
    }
}
