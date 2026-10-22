import Foundation

/// Something the 3D scene can draw for a line.
public struct Drawable: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case arrow(tail: Vec3, vector: Vec3)
        case point(Vec3)
        /// A graphed function of one axis: polyline runs, already broken
        /// wherever the function was undefined or left the axis box.
        case curve(segments: [[Vec3]])
        /// A graphed function of two axes: a grid of sample points, row by
        /// row. nil is a hole (undefined, non-finite, or clipped) and no
        /// quad touching it is drawn.
        case surface(rows: [[Vec3?]])
    }
    public var shape: Shape
    public var label: String?

    public init(shape: Shape, label: String?) {
        self.shape = shape
        self.label = label
    }

    /// True for the graph shapes, which carry no arrowhead and no notation.
    public var isGraph: Bool {
        switch shape {
        case .curve, .surface: return true
        case .arrow, .point: return false
        }
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

/// How long the axes are, from what is drawn. One formula, shared by the
/// engine (which needs it to size a graph's default domain) and the scene
/// (which needs it to build the axes), so the two can never disagree about
/// where the box ends.
public enum AxisExtent {
    /// Axes are never shorter than this, whatever is drawn.
    public static let minimum = 5.0
    /// …and never longer: keeps Int(extent) and the grid loop safe for any
    /// input; beyond that content clips.
    public static let cap = 1000.0
    /// Vectors and points get 20% of breathing room past their reach.
    public static let margin = 1.2
    /// The seed for the largest-coordinate fold: below this nothing moves
    /// the axes off their minimum.
    public static let seed = 2.0

    /// SceneKit keeps node transforms as 32-bit floats, so any coordinate
    /// past Float.greatestFiniteMagnitude reads back as ∞ however good the
    /// Double was. Only geometry inside this bound is drawn, and only drawn
    /// geometry may grow the axes.
    public static let maxRenderable = Double(Float.greatestFiniteMagnitude)

    public static func isRenderable(_ v: Vec3) -> Bool {
        v.isFinite && v.maxAbsComponent <= maxRenderable
    }

    /// `maxCoord` is the largest coordinate of any vector or point and gets
    /// the margin; `graphReach` is the largest coordinate of any graph and
    /// does not. A graph that took the default domain is clipped to the box
    /// the vectors made, so its reach can never exceed that box and never
    /// grows it — no feedback. A graph with a written domain grows the axes
    /// to exactly its own reach, once.
    public static func extent(maxCoord: Double, graphReach: Double = 0) -> Double {
        min(cap, max(minimum, maxCoord * margin, graphReach))
    }
}

public enum Engine {
    /// Evaluates all lines top to bottom against a fresh environment.
    /// Never throws: bad lines produce .error outcomes and evaluation continues.
    /// strictNotation (the default) requires \vec marks on vector definitions
    /// and true unit magnitude for hatted names — the app's teaching mode.
    ///
    /// `drawnLines` names the lines whose geometry is actually shown (the
    /// notebook lets a line be hidden). Only those size the axes, and so the
    /// default domain of a graph. nil means every line is shown.
    public static func evaluate(_ lines: [String], strictNotation: Bool = true,
                                drawnLines: Set<Int>? = nil) -> [LineOutcome] {
        var evaluator = Evaluator()
        evaluator.strictNotation = strictNotation

        var outcomes = [LineOutcome?](repeating: nil, count: lines.count)
        /// Graphs that sample across the axis extent wait until every line
        /// has run, because a vector defined BELOW the graph still sizes
        /// the axes it spans. Each carries the environment its line saw.
        var deferred: [(index: Int, spec: GraphSpec, evaluator: Evaluator, label: String?)] = []
        var maxCoord = AxisExtent.seed
        var graphReach = 0.0
        func isDrawn(_ index: Int) -> Bool { drawnLines?.contains(index) ?? true }
        func fold(_ v: Vec3) {
            if AxisExtent.isRenderable(v) { maxCoord = max(maxCoord, v.maxAbsComponent) }
        }

        for (index, line) in lines.enumerated() {
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
                switch try evaluator.run(stmt) {
                case .skipped:
                    outcomes[index] = LineOutcome(
                        status: line.trimmingCharacters(in: .whitespaces).isEmpty ? .blank : .comment,
                        resultText: "", drawable: nil, arc: nil, decoration: nil)

                case .value(let name, let value):
                    let drawable = Self.drawable(for: value, name: name, sourceLine: line)
                    let arc = Self.arc(for: stmt, evaluator: before)
                    if isDrawn(index) {
                        switch drawable?.shape {
                        case .arrow(let tail, let vec)?:
                            fold(tail)
                            fold(tail + vec)
                        case .point(let p)?:
                            fold(p)
                        default:
                            break
                        }
                        // The scene folds arc origins too: an arc anchored
                        // further out than every arrow was drawn outside the axes.
                        if let arc { fold(arc.origin) }
                    }
                    outcomes[index] = LineOutcome(
                        status: .ok, resultText: Fmt.value(value), drawable: drawable,
                        arc: arc, decoration: Self.decoration(for: value, name: name))

                case .graph(let spec):
                    let label = Self.graphLabel(line)
                    if spec.isFullyExplicit {
                        // The domain is written down, so the graph can be
                        // sampled now — and its reach counts toward the axes.
                        // (extent is unused for a fully explicit graph: no
                        // default domain to size, nothing to clip.)
                        let out = try Grapher.sample(spec, evaluator: before, extent: AxisExtent.minimum,
                                                     label: label)
                        if isDrawn(index) { graphReach = max(graphReach, Self.reach(of: out.drawable)) }
                        outcomes[index] = LineOutcome(status: .ok, resultText: out.resultText,
                                                      drawable: out.drawable, arc: nil, decoration: nil)
                    } else {
                        deferred.append((index, spec, before, label))
                    }
                }
            } catch let err as EvalError {
                outcomes[index] = LineOutcome(status: .error(err.message), resultText: "", drawable: nil,
                                              arc: nil, decoration: nil)
            } catch {
                outcomes[index] = LineOutcome(status: .error("\(error)"), resultText: "", drawable: nil,
                                              arc: nil, decoration: nil)
            }
        }

        let extent = AxisExtent.extent(maxCoord: maxCoord, graphReach: graphReach)
        for item in deferred {
            do {
                let out = try Grapher.sample(item.spec, evaluator: item.evaluator, extent: extent,
                                             label: item.label)
                outcomes[item.index] = LineOutcome(status: .ok, resultText: out.resultText,
                                                   drawable: out.drawable, arc: nil, decoration: nil)
            } catch let err as EvalError {
                outcomes[item.index] = LineOutcome(status: .error(err.message), resultText: "",
                                                   drawable: nil, arc: nil, decoration: nil)
            } catch {
                outcomes[item.index] = LineOutcome(status: .error("\(error)"), resultText: "",
                                                   drawable: nil, arc: nil, decoration: nil)
            }
        }
        return outcomes.map { $0! }
    }

    /// The largest renderable coordinate a graph touches.
    private static func reach(of drawable: Drawable) -> Double {
        var reach = 0.0
        func fold(_ v: Vec3) {
            if AxisExtent.isRenderable(v) { reach = max(reach, v.maxAbsComponent) }
        }
        switch drawable.shape {
        case .curve(let segments): segments.forEach { $0.forEach(fold) }
        case .surface(let rows): rows.forEach { $0.forEach { if let v = $0 { fold(v) } } }
        case .arrow, .point: break
        }
        return reach
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

    /// A graph is labelled with its own equation — three curves on y would
    /// otherwise all read "y". The domain clause is dropped, and a long
    /// equation falls back to the axis name rather than a paragraph in 3D.
    private static func graphLabel(_ line: String) -> String? {
        let equation = line.split(separator: ",", maxSplits: 1).first.map(String.init) ?? line
        let t = equation.trimmingCharacters(in: .whitespaces)
        if t.count <= 18 { return t }
        return t.split(separator: "=").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Lines of the form angle(a, b) (bare or assigned) get an angle arc.
    private static func arc(for stmt: Statement, evaluator: Evaluator) -> ArcSpec? {
        let expr: Expr
        switch stmt {
        case .expression(let e): expr = e
        case .definition(_, _, _, let e, _): expr = e
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
