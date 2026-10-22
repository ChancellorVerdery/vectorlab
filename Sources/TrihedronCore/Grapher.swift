import Foundation

/// A definition whose right-hand side mentions an axis name — x, y or z —
/// that nothing above it has defined. `y = x^2` with no `x` in scope is not
/// a mistake, it is a function of x, and the name on the left says which
/// axis it is a function INTO: `y = x^2` lies in the xy plane, `z = sin(x)`
/// in xz, `z = x^2 + y^2` is a surface over the xy plane.
struct GraphSpec: Equatable {
    /// The dependent axis: the name on the left of `=`.
    var dependent: String
    var expr: Expr
    /// The free axis names on the right, in axis order (x before y before z).
    /// One means a curve, two a surface.
    var free: [String]
    /// Explicit `name in [lo, hi]` ranges, already evaluated. A free variable
    /// missing from here samples across the axis extent instead.
    var explicit: [String: ClosedRange<Double>]

    var isSurface: Bool { free.count == 2 }
    /// Every free variable has a written range, so the graph can be sampled
    /// before the axis extent is known — and its values may grow the axes.
    var isFullyExplicit: Bool { free.allSatisfy { explicit[$0] != nil } }
}

/// Turns a GraphSpec into a Drawable by evaluating the expression at a grid
/// of sample points. Pure: the Evaluator it is handed is the environment the
/// line was written in, and nothing here touches the scene.
enum Grapher {
    /// 200 intervals along a curve, 60 × 60 across a surface. Both were
    /// chosen by eye against the notebook's re-evaluate-on-every-keystroke
    /// budget: 3,721 tree walks of `x^2 + y^2` cost a few milliseconds.
    static let curveSamples = 200
    static let surfaceSamples = 60

    struct Output: Equatable {
        var drawable: Drawable
        var resultText: String
    }

    /// `extent` is the axis half-length, used as the default domain AND as
    /// the clipping box for graphs that took that default: a curve that spans
    /// the axes because they are 5 units long should not itself demand axes
    /// 25 units long. Explicit-domain graphs are never clipped — the user
    /// asked for that range and the axes grow to hold it.
    static func sample(_ spec: GraphSpec, evaluator: Evaluator, extent: Double,
                       label: String?) throws -> Output {
        var sampler = evaluator
        let defaultDomain = -extent...extent
        let clip = !spec.isFullyExplicit
        let axisIndex: (String) -> Int = { ["x": 0, "y": 1, "z": 2][$0]! }
        let dep = axisIndex(spec.dependent)

        func place(_ coords: [Double]) -> Vec3 { Vec3(coords[0], coords[1], coords[2]) }

        /// One evaluation with the free variables bound. nil is a hole —
        /// the expression threw (ln of a negative, 1/0) or came back
        /// non-finite. A non-number is a type error for the whole graph.
        var firstError: EvalError?
        var holes = 0
        func value(at bindings: [(String, Double)]) throws -> Double? {
            for (name, t) in bindings { sampler.env[name] = .scalar(t) }
            let result: Value
            do {
                result = try sampler.eval(spec.expr)
            } catch let err as EvalError {
                if firstError == nil { firstError = err }
                holes += 1
                return nil
            }
            guard case .scalar(let v) = result else {
                throw EvalError("\(spec.dependent) = … must give a number at each point, but gives \(result.typeName) — a graph can't be made of vectors")
            }
            if v.isFinite { return v }
            holes += 1
            return nil
        }

        func domainText(_ name: String, _ r: ClosedRange<Double>) -> String {
            "\(name) in [\(Fmt.num(r.lowerBound)), \(Fmt.num(r.upperBound))]"
        }

        if spec.isSurface {
            let (u, w) = (spec.free[0], spec.free[1])
            let ru = spec.explicit[u] ?? defaultDomain
            let rw = spec.explicit[w] ?? defaultDomain
            let n = surfaceSamples
            var rows: [[Vec3?]] = []
            rows.reserveCapacity(n + 1)
            for i in 0...n {
                let a = ru.lowerBound + (ru.upperBound - ru.lowerBound) * Double(i) / Double(n)
                var row: [Vec3?] = []
                row.reserveCapacity(n + 1)
                for j in 0...n {
                    let b = rw.lowerBound + (rw.upperBound - rw.lowerBound) * Double(j) / Double(n)
                    guard let v = try value(at: [(u, a), (w, b)]), !(clip && abs(v) > extent) else {
                        row.append(nil)
                        continue
                    }
                    var coords = [0.0, 0.0, 0.0]
                    coords[axisIndex(u)] = a
                    coords[axisIndex(w)] = b
                    coords[dep] = v
                    row.append(place(coords))
                }
                rows.append(row)
            }
            let total = (n + 1) * (n + 1)
            if holes == total, let firstError { throw firstError }
            guard rows.contains(where: { $0.contains { $0 != nil } }) else {
                throw EvalError(clip
                    ? "\(spec.dependent) = … stays outside the axes over \(domainText(u, ru)), \(domainText(w, rw)) — give it a domain, like \(u) in [-1, 1]"
                    : "\(spec.dependent) = … is never defined over \(domainText(u, ru)), \(domainText(w, rw))")
            }
            var text = "surface \(spec.dependent)(\(u), \(w)), \(domainText(u, ru)), \(domainText(w, rw))"
            if holes > 0 { text += " — undefined on part of the domain" }
            return Output(drawable: Drawable(shape: .surface(rows: rows), label: label), resultText: text)
        }

        // Curve. Consecutive finite in-box samples join into one polyline;
        // a hole or a clipped sample ends the run. When the curve leaves or
        // enters the box between two samples, the run is extended to the
        // exact crossing so a clipped parabola ends ON the axis limit rather
        // than one sample short of it.
        let u = spec.free[0]
        let range = spec.explicit[u] ?? defaultDomain
        let n = curveSamples
        var segments: [[Vec3]] = []
        var current: [Vec3] = []
        var previous: (t: Double, v: Double)?

        func point(_ t: Double, _ v: Double) -> Vec3 {
            var coords = [0.0, 0.0, 0.0]
            coords[axisIndex(u)] = t
            coords[dep] = v
            return place(coords)
        }
        func flush() {
            if current.count >= 2 { segments.append(current) }
            current = []
        }

        for i in 0...n {
            let t = range.lowerBound + (range.upperBound - range.lowerBound) * Double(i) / Double(n)
            guard let v = try value(at: [(u, t)]) else {
                flush()
                previous = nil
                continue
            }
            let inside = !clip || abs(v) <= extent
            if clip, let (pt, pv) = previous, (abs(pv) <= extent) != inside {
                let outsideValue = inside ? pv : v
                let bound = outsideValue > extent ? extent : -extent
                let s = (bound - pv) / (v - pv)
                let crossing = point(pt + s * (t - pt), bound)
                if inside {
                    flush()
                    current = [crossing]
                } else {
                    current.append(crossing)
                    flush()
                }
            }
            if inside { current.append(point(t, v)) }
            previous = (t, v)
        }
        flush()

        if holes == n + 1, let firstError { throw firstError }
        guard !segments.isEmpty else {
            throw EvalError(clip
                ? "\(spec.dependent) = … stays outside the axes over \(domainText(u, range)) — give it a domain, like \(u) in [-1, 1]"
                : "\(spec.dependent) = … is never defined over \(domainText(u, range))")
        }
        let plane = [spec.free[0], spec.dependent].sorted().joined()
        var text = "curve in \(plane), \(domainText(u, range))"
        if holes > 0 { text += " — undefined on part of the domain" }
        return Output(drawable: Drawable(shape: .curve(segments: segments), label: label), resultText: text)
    }
}
