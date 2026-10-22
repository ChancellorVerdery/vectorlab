import Foundation
import Testing
@testable import TrihedronCore

/// Graphing: a definition whose right-hand side uses an unbound axis name
/// becomes a curve or a surface in the viewport instead of an error.
@Suite struct GraphingTests {
    private func last(_ lines: [String], drawnLines: Set<Int>? = nil) -> LineOutcome {
        Engine.evaluate(lines, drawnLines: drawnLines).last!
    }

    private func curve(_ lines: [String], drawnLines: Set<Int>? = nil,
                       sourceLocation: SourceLocation = #_sourceLocation) throws -> [[Vec3]] {
        let outcome = last(lines, drawnLines: drawnLines)
        guard case .curve(let segments)? = outcome.drawable?.shape else {
            Issue.record("expected a curve, got \(outcome)", sourceLocation: sourceLocation)
            throw EvalError("not a curve")
        }
        return segments
    }

    private func surface(_ lines: [String],
                         sourceLocation: SourceLocation = #_sourceLocation) throws -> [[Vec3?]] {
        let outcome = last(lines)
        guard case .surface(let rows)? = outcome.drawable?.shape else {
            Issue.record("expected a surface, got \(outcome)", sourceLocation: sourceLocation)
            throw EvalError("not a surface")
        }
        return rows
    }

    private func coordinate(_ v: Vec3, _ axis: Int) -> Double { [v.x, v.y, v.z][axis] }

    // MARK: - Planes

    /// All six left/right axis pairings: the third coordinate is 0, the
    /// independent axis runs across the default box, and the dependent
    /// coordinate is the function of the independent one.
    @Test func everyPlaneCombinationLiesInItsPlane() throws {
        let cases: [(line: String, independent: Int, dependent: Int, zero: Int, f: (Double) -> Double, plane: String)] = [
            ("y = x^2", 0, 1, 2, { $0 * $0 }, "xy"),
            ("x = y^2", 1, 0, 2, { $0 * $0 }, "xy"),
            ("z = x^3 - x", 0, 2, 1, { $0 * $0 * $0 - $0 }, "xz"),
            ("x = 2z", 2, 0, 1, { 2 * $0 }, "xz"),
            ("z = ln(y)", 1, 2, 0, { Foundation.log($0) }, "yz"),
            ("y = 2z", 2, 1, 0, { 2 * $0 }, "yz"),
        ]
        for c in cases {
            let outcome = last([c.line])
            #expect(outcome.status == .ok, "\(c.line): \(outcome.status)")
            #expect(outcome.resultText.hasPrefix("curve in \(c.plane)"), "\(c.line): \(outcome.resultText)")
            #expect(outcome.decoration == nil)
            #expect(outcome.arc == nil)
            let segments = try curve([c.line])
            let points = segments.flatMap { $0 }
            #expect(!points.isEmpty, Comment(rawValue: c.line))
            // Sampled points are exact; the two clipping crossings per run
            // sit on the chord between samples, ~1e-3 off the true curve.
            for p in points {
                #expect(coordinate(p, c.zero) == 0, "\(c.line): \(p) is off its plane")
                #expect(abs(c.f(coordinate(p, c.independent)) - coordinate(p, c.dependent)) < 5e-3,
                        "\(c.line): \(p) is not on the curve")
            }
            let sampled = segments.flatMap { $0.dropFirst().dropLast() }
            for p in sampled {
                #expect(abs(c.f(coordinate(p, c.independent)) - coordinate(p, c.dependent)) < 1e-9,
                        "\(c.line): \(p) is not on the curve")
            }
        }
    }

    @Test func aDefaultDomainCurveSpansTheAxes() throws {
        let points = try curve(["y = 0.1 * x"]).flatMap { $0 }
        #expect(points.first?.x == -5)
        #expect(points.last?.x == 5)
        #expect(points.count == 201)
        #expect(last(["y = 0.1 * x"]).resultText == "curve in xy, x in [-5, 5]")
    }

    // MARK: - Bound versus unbound

    @Test func aDefinedXIsJustANumber() {
        let outcomes = Engine.evaluate(["x = 3", "y = x^2"])
        #expect(outcomes[1].status == .ok)
        #expect(outcomes[1].resultText == "9")
        #expect(outcomes[1].drawable == nil)
    }

    @Test func aDefinedVectorXIsNotAGraphVariableEither() {
        let outcomes = Engine.evaluate(["\\vec x = <1, 2, 3>", "y = x^2"])
        #expect(outcomes[1].errorMessage?.contains("'^' needs numbers") == true)
    }

    @Test func aGraphNameCannotBeUsedInArithmeticBelow() {
        let outcomes = Engine.evaluate(["y = x^2", "y + 1"])
        #expect(outcomes[1].errorMessage?.contains("is a graph") == true)
    }

    @Test func redefiningAGraphNameAsANumberRestoresIt() {
        let outcomes = Engine.evaluate(["y = x^2", "y = 4", "y + 1"])
        #expect(outcomes[2].resultText == "5")
    }

    @Test func theOldYValueIsVisibleToAGraphOnY() throws {
        // Definitions read the environment BEFORE the line, so `y = y + x`
        // with y = 3 is the line y(x) = 3 + x, not self-dependence.
        let points = try curve(["y = 3", "y = y + x"]).flatMap { $0 }
        #expect(points.allSatisfy { abs($0.y - (3 + $0.x)) < 1e-9 })
    }

    // MARK: - Domain clause

    @Test func explicitDomainIsSampledExactlyAndNotClipped() throws {
        let points = try curve(["y = x^2, x in [-3, 3]"]).flatMap { $0 }
        #expect(points.first == Vec3(-3, 9, 0))
        #expect(points.last == Vec3(3, 9, 0))
        #expect(points.count == 201)
        #expect(last(["y = x^2, x in [-3, 3]"]).resultText == "curve in xy, x in [-3, 3]")
    }

    @Test func theElementSignParsesAsIn() throws {
        let a = try curve(["y = x^2, x ∈ [-3, 3]"])
        let b = try curve(["y = x^2, x in [-3, 3]"])
        #expect(a == b)
    }

    @Test func domainBoundsAreExpressionsInScope() throws {
        let points = try curve(["L = 2", "y = x, x in [-L, L]"]).flatMap { $0 }
        #expect(points.first?.x == -2)
        #expect(points.last?.x == 2)
    }

    @Test func domainClauseMistakesAreErrors() {
        #expect(last(["y = x^2, z in [0, 1]"]).errorMessage?.contains("not a graph variable") == true)
        #expect(last(["y = x^2, x in [3, -3]"]).errorMessage?.contains("lo < hi") == true)
        #expect(last(["y = x^2, x in [0, 1], x in [0, 2]"]).errorMessage?.contains("two domains") == true)
        #expect(last(["x^2, x in [0, 1]"]).errorMessage?.contains("needs a definition") == true)
        #expect(last(["x = 1", "y = x^2, x in [0, 1]"]).errorMessage?.contains("nothing to graph") == true)
        #expect(last(["y = x^2, x in 3"]).errorMessage?.contains("'['") == true)
        #expect(last(["y = x^2, 3"]).errorMessage?.contains("expected a domain") == true)
    }

    // MARK: - Axis extent

    @Test func theDefaultDomainFollowsTheVectorsWhereverTheyAre() throws {
        // A vector of reach 10 makes 12-unit axes; the graph spans them,
        // whether the vector is written above or below the graph.
        for lines in [["\\vec F = <10, 0, 0>", "y = 0.1 * x"], ["y = 0.1 * x", "\\vec F = <10, 0, 0>"]] {
            let outcomes = Engine.evaluate(lines)
            let graph = outcomes[lines[0].hasPrefix("y") ? 0 : 1]
            guard case .curve(let segments)? = graph.drawable?.shape else {
                Issue.record("no curve for \(lines)")
                continue
            }
            expectApprox(segments.first?.first?.x ?? 0, -12, tolerance: 1e-12)
            expectApprox(segments.last?.last?.x ?? 0, 12, tolerance: 1e-12)
            #expect(graph.resultText == "curve in xy, x in [-12, 12]")
        }
    }

    @Test func aHiddenLineDoesNotSizeTheDomain() throws {
        let lines = ["\\vec F = <10, 0, 0>", "y = 0.1 * x"]
        let shown = try curve(lines, drawnLines: [0, 1]).flatMap { $0 }
        let hidden = try curve(lines, drawnLines: [1]).flatMap { $0 }
        expectApprox(shown.first?.x ?? 0, -12, tolerance: 1e-12)
        #expect(hidden.first?.x == -5)
    }

    @Test func aDefaultDomainCurveIsClippedToTheBoxAndEndsOnIt() throws {
        let segments = try curve(["y = x^2"])
        let points = segments.flatMap { $0 }
        #expect(segments.count == 1)
        #expect(points.allSatisfy { abs($0.y) <= 5 + 1e-12 })
        // The run is extended to the exact crossing, not cut one sample short.
        #expect(points.first?.y == 5)
        #expect(points.last?.y == 5)
        // The crossing is interpolated on the chord between two samples.
        expectApprox(points.first!.x, -5.0.squareRoot(), tolerance: 1e-3)
    }

    @Test func aClippedCurveDoesNotGrowTheAxesButAnExplicitOneDoes() throws {
        // Two graphs: the clipped one reaches 5 and leaves the box at 5; the
        // explicit one reaches 9 and the box grows to exactly 9 — so the
        // clipped one, re-sampled against that box, now spans ±9.
        let outcomes = Engine.evaluate(["y = x^2", "y = x^2, x in [-3, 3]"])
        guard case .curve(let clipped)? = outcomes[0].drawable?.shape else { throw EvalError("no curve") }
        let points = clipped.flatMap { $0 }
        #expect(points.first?.y == 9)
        #expect(outcomes[0].resultText == "curve in xy, x in [-9, 9]")
        // And the extent formula itself: graphs fold without the margin.
        #expect(AxisExtent.extent(maxCoord: 2, graphReach: 5) == 5)
        #expect(AxisExtent.extent(maxCoord: 2, graphReach: 9) == 9)
        expectApprox(AxisExtent.extent(maxCoord: 10, graphReach: 9), 12, tolerance: 1e-12)
    }

    @Test func aCurveEntirelyOutsideTheBoxIsAnErrorThatSuggestsADomain() {
        #expect(last(["y = x + 100"]).errorMessage?.contains("give it a domain") == true)
    }

    // MARK: - Holes and non-finite values

    @Test func undefinedPointsBreakTheCurveInsteadOfSpiking() throws {
        // 1/x: the sample at exactly 0 divides by zero, and the neighbours
        // are clipped, so the curve is two runs with nothing across 0.
        let segments = try curve(["y = 1/x"])
        #expect(segments.count == 2)
        #expect(segments.flatMap { $0 }.allSatisfy { $0.isFinite && abs($0.y) <= 5 })
        #expect(segments[0].allSatisfy { $0.x < 0 })
        #expect(segments[1].allSatisfy { $0.x > 0 })
        #expect(last(["y = 1/x"]).resultText.contains("undefined on part of the domain"))
    }

    @Test func lnStartsWhereItIsDefined() throws {
        let points = try curve(["z = ln(y)"]).flatMap { $0 }
        #expect(points.allSatisfy { $0.y > 0 && $0.z.isFinite })
        #expect(last(["z = ln(y)"]).resultText.hasPrefix("curve in yz, y in [-5, 5] — undefined"))
    }

    @Test func aCurveThatIsNeverDefinedReportsTheExpressionsOwnError() {
        #expect(last(["y = sqrt(x), x in [-5, -1]"]).errorMessage == "sqrt of a negative number")
    }

    @Test func mixingInAVectorIsAnOrdinaryError() {
        let outcomes = Engine.evaluate(["\\vec F = <1, 2, 3>", "y = x + F"])
        #expect(outcomes[1].errorMessage?.contains("can't add") == true)
        #expect(outcomes[1].drawable == nil)
    }

    @Test func aVectorValuedGraphIsATypeError() {
        let outcomes = Engine.evaluate(["\\vec F = <1, 2, 3>", "y = x * F"])
        #expect(outcomes[1].errorMessage?.contains("must give a number") == true)
    }

    // MARK: - Left-hand side rules

    @Test func aNonAxisNameOnTheLeftGetsAHint() {
        let message = last(["f = x^2"]).errorMessage ?? ""
        #expect(message.contains("'x' is not defined"))
        #expect(message.contains("y = …"))
    }

    @Test func selfDependenceIsAnError() {
        #expect(last(["y = y^2"]).errorMessage?.contains("itself") == true)
        #expect(last(["z = x + z"]).errorMessage?.contains("itself") == true)
    }

    @Test func pointAndVecMarksRefuseToGraph() {
        #expect(last(["point y = x^2"]).errorMessage?.contains("can't be a graph") == true)
        #expect(last(["\\vec y = x^2"]).errorMessage?.contains("can't be a graph") == true)
    }

    // MARK: - Degrees

    @Test func trigStaysInDegreesSoDegGivesTheRadianWave() throws {
        let flat = try curve(["z = sin(x)"]).flatMap { $0 }
        let wave = try curve(["z = sin(deg(x))"]).flatMap { $0 }
        let atFive = flat.last!, waveAtFive = wave.last!
        #expect(atFive.x == 5)
        expectApprox(atFive.z, Foundation.sin(5 * .pi / 180), tolerance: 1e-12)
        expectApprox(waveAtFive.z, Foundation.sin(5), tolerance: 1e-12)
    }

    // MARK: - Surfaces

    @Test func aSurfaceIsA61By61GridOverTheDefaultBox() throws {
        let rows = try surface(["z = x^2 + y^2"])
        #expect(rows.count == 61)
        #expect(rows.allSatisfy { $0.count == 61 })
        #expect(rows[0][0] == nil, "the corner is at z = 50, outside the 5-unit box")
        #expect(rows[30][30] == Vec3(0, 0, 0))
        #expect(rows[30][36] == Vec3(0, 1, 1))
        #expect(rows[36][30] == Vec3(1, 0, 1))
        let defined = rows.flatMap { $0 }.compactMap { $0 }
        #expect(defined.allSatisfy { abs($0.z - ($0.x * $0.x + $0.y * $0.y)) < 1e-9 && $0.z <= 5 })
        #expect(last(["z = x^2 + y^2"]).resultText == "surface z(x, y), x in [-5, 5], y in [-5, 5]")
    }

    @Test func surfacesOverTheOtherPlanes() throws {
        let overXZ = try surface(["y = x * z"]).flatMap { $0 }.compactMap { $0 }
        #expect(overXZ.allSatisfy { abs($0.y - $0.x * $0.z) < 1e-9 })
        #expect(last(["y = x * z"]).resultText.hasPrefix("surface y(x, z)"))
        let overYZ = try surface(["x = y + z"]).flatMap { $0 }.compactMap { $0 }
        #expect(overYZ.allSatisfy { abs($0.x - ($0.y + $0.z)) < 1e-9 })
    }

    @Test func aPartlyExplicitSurfaceDefaultsTheOtherAxis() throws {
        let rows = try surface(["z = 0.1 * x * y, x in [0, 2]"])
        let defined = rows.flatMap { $0 }.compactMap { $0 }
        #expect(defined.allSatisfy { $0.x >= 0 && $0.x <= 2 && abs($0.y) <= 5 })
        #expect(rows[0][0]?.y == -5)
        expectApprox(rows[60][60] ?? .zero, Vec3(2, 5, 1), tolerance: 1e-12)
        #expect(last(["z = 0.1 * x * y, x in [0, 2]"]).resultText == "surface z(x, y), x in [0, 2], y in [-5, 5]")
    }

    @Test func surfaceHolesWhereUndefined() throws {
        let rows = try surface(["z = ln(x * y)"])
        // ln(x·y) exists only where x and y share a sign: two quadrants
        // defined, two holes, and the axes themselves (x·y = 0) undefined.
        #expect(rows[45][45] != nil)
        #expect(rows[15][15] != nil)
        #expect(rows[45][15] == nil)
        #expect(rows[30][45] == nil)
        #expect(last(["z = ln(x * y)"]).resultText.contains("undefined on part"))
    }

    // MARK: - Labels

    @Test func graphsAreLabelledWithTheirEquation() {
        #expect(last(["y = x^2"]).drawable?.label == "y = x^2")
        #expect(last(["y = x^2, x in [-3, 3]"]).drawable?.label == "y = x^2")
        #expect(last(["z = sin(deg(x)) * cos(deg(x)) + x"]).drawable?.label == "z")
    }

    // MARK: - Nothing else moved

    @Test func linesWithoutFreeAxisNamesEvaluateAsBefore() {
        let outcomes = Engine.evaluate(["\\vec a = <1, 2, 3>", "\\vec b = <0, 0, 1>", "angle(a, b)", "a.x + 2"])
        #expect(outcomes[2].arc != nil)
        #expect(outcomes[3].resultText == "3")
        #expect(outcomes[0].decoration == .vectorArrow)
    }

    @Test func executeStillWorksForValuesAndRefusesGraphs() throws {
        var evaluator = Evaluator()
        let value = try evaluator.execute(Parser.parseLine("a = 2 + 2"))
        #expect(value?.value == .scalar(4))
        #expect(throws: EvalError.self) { try evaluator.execute(Parser.parseLine("y = x^2")) }
    }
}
