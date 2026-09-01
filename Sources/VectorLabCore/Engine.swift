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

    public var errorMessage: String? {
        if case .error(let m) = status { return m }
        return nil
    }
}

public enum Engine {
    /// Evaluates all lines top to bottom against a fresh environment.
    /// Never throws: bad lines produce .error outcomes and evaluation continues.
    public static func evaluate(_ lines: [String]) -> [LineOutcome] {
        var evaluator = Evaluator()
        return lines.map { line in
            do {
                let stmt = try Parser.parseLine(line)
                guard let (name, value) = try evaluator.execute(stmt) else {
                    return LineOutcome(
                        status: line.trimmingCharacters(in: .whitespaces).isEmpty ? .blank : .comment,
                        resultText: "", drawable: nil, arc: nil)
                }
                let drawable = Self.drawable(for: value, name: name, sourceLine: line)
                let arc = Self.arc(for: stmt, evaluator: evaluator)
                return LineOutcome(status: .ok, resultText: Fmt.value(value), drawable: drawable, arc: arc)
            } catch let err as EvalError {
                return LineOutcome(status: .error(err.message), resultText: "", drawable: nil, arc: nil)
            } catch {
                return LineOutcome(status: .error("\(error)"), resultText: "", drawable: nil, arc: nil)
            }
        }
    }

    private static func drawable(for value: Value, name: String?, sourceLine: String) -> Drawable? {
        switch value {
        case .scalar:
            return nil
        case .vector(let v, let anchor):
            let label = name ?? shortLabel(sourceLine)
            return Drawable(shape: .arrow(tail: anchor ?? .zero, vector: v), label: label)
        case .point(let p):
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
        case .definition(_, _, let e): expr = e
        default: return nil
        }
        guard case .call(let fn, let args) = expr, fn.lowercased() == "angle", args.count == 2,
              case .vector(let a, let aAnchor)? = try? evaluator.eval(args[0]),
              case .vector(let b, let bAnchor)? = try? evaluator.eval(args[1]),
              let ua = a.normalized, let ub = b.normalized
        else { return nil }
        let deg = Foundation.acos(min(1, max(-1, ua.dot(ub)))) * 180 / .pi
        let origin = (aAnchor != nil && aAnchor == bAnchor) ? aAnchor! : .zero
        return ArcSpec(origin: origin, from: a, to: b, degrees: deg)
    }
}
