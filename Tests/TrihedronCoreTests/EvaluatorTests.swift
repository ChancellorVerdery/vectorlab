import Foundation
import Testing
@testable import TrihedronCore

@Suite struct EvaluatorTests {
    @Test func dotProductForms() throws {
        expectApprox(try scalar("a = <1,2,3>", "b = <4,-5,6>", "a * b"), 12)
        expectApprox(try scalar("a = <1,2,3>", "b = <4,-5,6>", "dot(a, b)"), 12)
        expectApprox(try scalar("a = <1,2,3>", "b = <4,-5,6>", "a · b"), 12)
    }

    @Test func crossProductForms() throws {
        expectApprox(try vector("cross(<1,2,3>, <4,5,6>)"), Vec3(-3, 6, -3))
        expectApprox(try vector("<1,2,3> × <4,5,6>"), Vec3(-3, 6, -3))
        expectApprox(try vector("i × j"), Vec3(0, 0, 1))       // right-handed
        expectApprox(try vector("j × k"), Vec3(1, 0, 0))
        expectApprox(try vector("k × i"), Vec3(0, 1, 0))
    }

    @Test func vectorArithmetic() throws {
        expectApprox(try vector("<1,2,3> + <4,5,6>"), Vec3(5, 7, 9))
        expectApprox(try vector("<4,5,6> - <1,2,3>"), Vec3(3, 3, 3))
        expectApprox(try vector("3 * <1,2,3>"), Vec3(3, 6, 9))
        expectApprox(try vector("<2,4,6> / 2"), Vec3(1, 2, 3))
        expectApprox(try vector("-<1,2,3>"), Vec3(-1, -2, -3))
    }

    @Test func magnitudeAndUnit() throws {
        expectApprox(try scalar("|<3,4,0>|"), 5)
        expectApprox(try scalar("mag(<2,3,6>)"), 7)
        expectApprox(try vector("unit(<3,4,0>)"), Vec3(0.6, 0.8, 0))
        expectApprox(try scalar("|unit(<12, -5, 84>)|"), 1, tolerance: 1e-12)
        #expect(throws: EvalError.self) { _ = try lastValue("unit(<0,0,0>)") }
    }

    @Test func angleFunction() throws {
        expectApprox(try scalar("angle(i, j)"), 90)
        expectApprox(try scalar("angle(<1,0,0>, <1,1,0>)"), 45, tolerance: 1e-9)
        expectApprox(try scalar("angle(i, -i)"), 180)
        expectApprox(try scalar("angle(<2,0,0>, <5,0,0>)"), 0)
    }

    @Test func projectionAndComponent() throws {
        expectApprox(try vector("proj(<3,4,0>, i)"), Vec3(3, 0, 0))
        expectApprox(try scalar("comp(<3,4,0>, i)"), 3)
        expectApprox(try vector("proj(<1,1,0>, <2,0,0>)"), Vec3(1, 0, 0))
        #expect(throws: EvalError.self) { _ = try lastValue("proj(i, <0,0,0>)") }
    }

    @Test func tripleProduct() throws {
        expectApprox(try scalar("triple(i, j, k)"), 1)
        expectApprox(try scalar("triple(<1,2,3>, <4,5,6>, <7,8,10>)"), -3)
    }

    @Test func momentFunction() throws {
        expectApprox(try vector("moment(<1,0,0>, <0,10,0>)"), Vec3(0, 0, 10))
        expectApprox(try scalar("moment(k, i, j)"), 1)     // axis form
        expectApprox(try scalar("moment(<0,0,5>, i, j)"), 1)   // axis normalized
    }

    @Test func resultantFunction() throws {
        expectApprox(try vector("resultant(<1,0,0>, <0,2,0>, <0,0,3>)"), Vec3(1, 2, 3))
        expectApprox(try vector("resultant(10∠0, 10∠90)"), Vec3(10, 10, 0), tolerance: 1e-9)
    }

    @Test func distanceFunction() throws {
        expectApprox(try scalar("point A = (1,1,1)", "point B = (4,5,1)", "dist(A, B)"), 5)
        expectApprox(try scalar("dist(<0,0,0>, <2,3,6>)"), 7)
    }

    @Test func pointArithmetic() throws {
        let moved = try lastValue("point A = (1,2,3)", "A + <1,1,1>")
        guard case .point(let p) = moved else {
            Issue.record("point + vector should stay a point")
            return
        }
        expectApprox(p, Vec3(2, 3, 4))

        let between = try lastValue("point A = (1,2,3)", "point B = (4,4,4)", "B - A")
        guard case .vector(let v, let anchor) = between else {
            Issue.record("point - point should be a vector")
            return
        }
        expectApprox(v, Vec3(3, 2, 1))
        #expect(anchor == Vec3(1, 2, 3))

        #expect(throws: EvalError.self) {
            _ = try lastValue("point A = (1,1,1)", "point B = (2,2,2)", "A + B")
        }
        #expect(throws: EvalError.self) {
            _ = try lastValue("point A = (1,1,1)", "point B = (2,2,2)", "A * B")
        }
    }

    @Test func pointVectorConversions() throws {
        let p = try lastValue("A = point(<1, 2, 3>)")
        guard case .point(let coords) = p else {
            Issue.record("point(vector) should make a point, got \(p)")
            return
        }
        expectApprox(coords, Vec3(1, 2, 3))

        expectApprox(try vector("A = (3, 4, 0)", "vector(A)"), Vec3(3, 4, 0))
        expectApprox(try vector("vector(<1, 1, 1>)"), Vec3(1, 1, 1))   // pass-through
        guard case .point = try lastValue("point((5, 6, 7))") else {
            Issue.record("point(point) should pass through")
            return
        }
        #expect(throws: EvalError.self) { _ = try lastValue("point(5)") }
        #expect(throws: EvalError.self) { _ = try lastValue("vector(5)") }

        // Conversions compose with strict notation.
        #expect(Engine.evaluate(["A = point(<1, 2, 3>)"])[0].errorMessage == nil)
        #expect(Engine.evaluate(["A = (1, 2, 3)", #"\vec a = vector(A)"#])
            .allSatisfy { $0.errorMessage == nil })
    }

    @Test func trigInDegrees() throws {
        expectApprox(try scalar("sin(30)"), 0.5, tolerance: 1e-12)
        expectApprox(try scalar("cos(60)"), 0.5, tolerance: 1e-12)
        expectApprox(try scalar("tan(45)"), 1, tolerance: 1e-12)
        expectApprox(try scalar("asin(0.5)"), 30, tolerance: 1e-9)
        expectApprox(try scalar("acos(0.5)"), 60, tolerance: 1e-9)
        expectApprox(try scalar("atan(1)"), 45, tolerance: 1e-9)
        expectApprox(try scalar("atan2(1, 1)"), 45, tolerance: 1e-9)
        expectApprox(try scalar("rad(180)"), Double.pi, tolerance: 1e-12)
        expectApprox(try scalar("deg(pi)"), 180, tolerance: 1e-12)
    }

    @Test func scalarMath() throws {
        expectApprox(try scalar("sqrt(2)^2"), 2, tolerance: 1e-12)
        expectApprox(try scalar("ln(e)"), 1, tolerance: 1e-12)
        expectApprox(try scalar("log(1000)"), 3, tolerance: 1e-12)
        expectApprox(try scalar("exp(0)"), 1)
        #expect(throws: EvalError.self) { _ = try lastValue("1 / 0") }
        #expect(throws: EvalError.self) { _ = try lastValue("sqrt(-1)") }
        #expect(throws: EvalError.self) { _ = try lastValue("asin(2)") }
    }

    @Test func anchorPropagation() throws {
        // F = 100*unit(r_AB) should stay anchored at A for drawing.
        let f = try lastValue("point A = (0,0,0)", "point B = (3,4,0)", "F = 100 * unit(r_AB)")
        guard case .vector(let v, let anchor) = f else {
            Issue.record("expected vector")
            return
        }
        expectApprox(v, Vec3(60, 80, 0), tolerance: 1e-9)
        #expect(anchor == Vec3(0, 0, 0))
    }

    @Test func vectorTimesVectorTimesVector() throws {
        // Left-assoc: (a · b) scales c.
        expectApprox(try vector("<1,0,0> * <2,0,0> * <0,1,0>"), Vec3(0, 2, 0))
    }

    /// |v| overflows to infinity once components pass ~1e154. unit() divided
    /// by that infinity and answered <0,0,0> — a non-unit "unit vector".
    @Test func unitVectorSurvivesExtremeMagnitudes() throws {
        expectApprox(try vector("unit(<1e200, 1e200, 0>)"),
                     Vec3(1, 1, 0) / (2.0).squareRoot(), tolerance: 1e-12)
        expectApprox(try scalar("|unit(<3e200, 4e200, 0>)|"), 1, tolerance: 1e-12)
        expectApprox(try vector("unit(<3e200, 4e200, 0>)"), Vec3(0.6, 0.8, 0), tolerance: 1e-12)
        // A non-finite component has no direction — an error, not NaN output.
        #expect(throws: EvalError.self) { _ = try lastValue("unit(<1e400, 0, 0>)") }
        // PASS 6 OVERTURNED THIS PIN. It fixed the top of the range and left
        // an absolute 1e-12 floor in place, which made unit() scale-dependent
        // and put it at odds with mag(). See Pass6Tests. The tiny vector now
        // normalizes like any other; only zero and non-finite have no
        // direction, and both are still pinned as errors just above.
        expectApprox(try vector("unit(<3e-200, 4e-200, 0>)"), Vec3(0.6, 0.8, 0), tolerance: 1e-15)
    }

    /// acos(a-hat . b-hat) loses about half its digits near 0 and 180 degrees,
    /// which is exactly where direction-cosine answers land.
    @Test func anglePrecisionNearZeroAndStraight() throws {
        expectApprox(try scalar("t = 1e-6", "angle(i, <cos(t), sin(t), 0>)"),
                     1e-6, tolerance: 1e-14)
        expectApprox(try scalar("t = 179.999999", "angle(i, <cos(t), sin(t), 0>)"),
                     179.999999, tolerance: 1e-12)
        // Overflowing magnitudes still have a well-defined angle (this read 90).
        expectApprox(try scalar("angle(<1e200, 1e200, 0>, <1e200, 0, 0>)"), 45, tolerance: 1e-12)
        // Exact endpoints stay exact.
        expectApprox(try scalar("angle(i, i)"), 0)
        expectApprox(try scalar("angle(i, -i)"), 180)
        #expect(throws: EvalError.self) { _ = try lastValue("angle(<0,0,0>, i)") }
    }

    /// pow(-8, 1/3) is NaN, not -2. Saying so beats printing NaN.
    @Test func negativeBaseNeedsWholeExponent() throws {
        expectApprox(try scalar("(-2)^3"), -8)
        expectApprox(try scalar("(-2)^2"), 4)
        expectApprox(try scalar("2^0.5"), (2.0).squareRoot(), tolerance: 1e-12)
        #expect(throws: EvalError.self) { _ = try lastValue("(-8)^(1/3)") }
    }

    /// Every NaN comparison is false, so a `> tolerance` unit check waves a
    /// NaN-magnitude vector through as a legitimate unit vector.
    @Test func hattedNameRejectsNonFiniteMagnitude() {
        let nan = Engine.evaluate([#"\hat u = <1e400, 0, 0> - <1e400, 0, 0>"#])
        #expect(nan[0].errorMessage != nil, "NaN magnitude accepted as a unit vector")
        let inf = Engine.evaluate([#"\hat u = <1e400, 0, 0>"#])
        #expect(inf[0].errorMessage != nil, "infinite magnitude accepted as a unit vector")
    }

    /// The arc the viewport draws and the number angle(...) prints come from
    /// one formula, so a reader can never see two different angles at once.
    @Test func arcDegreesMatchAngleFunction() throws {
        let lines = [#"\vec a = <1e200, 1e200, 0>"#, #"\vec b = <1e200, 0, 0>"#, "angle(a, b)"]
        let outcomes = Engine.evaluate(lines)
        #expect(outcomes.allSatisfy { $0.errorMessage == nil })
        guard let arc = outcomes[2].arc else {
            Issue.record("angle(a, b) should produce an arc")
            return
        }
        expectApprox(arc.degrees, try scalar(lines[0], lines[1], "angle(a, b)"), tolerance: 1e-12)
        expectApprox(arc.degrees, 45, tolerance: 1e-12)
    }

    /// length squares its components, so it overflows to infinity past ~1e154
    /// and underflows to zero below ~1e-162. Both are silent wrong answers on
    /// a plain magnitude question. Ratios keep the checks scale-free.
    @Test func magnitudeSurvivesOverflowAndUnderflow() throws {
        expectApprox(try scalar("mag(<1e200, 1e200, 0>) / 1e200"), (2.0).squareRoot(), tolerance: 1e-12)
        expectApprox(try scalar("mag(<3e-200, 4e-200, 0>) / 1e-200"), 5, tolerance: 1e-12)
        expectApprox(try scalar("|<3e200, 4e200, 0>| / 1e200"), 5, tolerance: 1e-12)
        expectApprox(try scalar("abs(<3e-200, 4e-200, 0>) / 1e-200"), 5, tolerance: 1e-12)
        expectApprox(try scalar("dist((0,0,0), (3e200, 4e200, 0)) / 1e200"), 5, tolerance: 1e-12)
        // Ordinary magnitudes must not shift by even one bit.
        let exact = try scalar("mag(<2,3,6>)")
        #expect(exact == 7.0)
        #expect(Vec3(0, 0, 0).length == 0)
        // And the notebook line stops reading half-broken: finite components
        // next to |v| = infinity.
        let shown = Engine.evaluate([#"\vec a = <1e200, 1e200, 0>"#])[0].resultText
        #expect(!shown.contains("\u{221E}"), "printed \(shown)")
    }

    /// proj divided by b.dot(b), which OVERFLOWS to infinity once |b| passes
    /// ~1e154 — so a.dot(b)/inf is 0 and proj returned the zero vector with no
    /// error at all, while comp(...) on the same pair answered correctly.
    /// (The small end was never the problem: both already cut off at |b| > 1e-12
    /// — pass 6 removed that floor from both together, so they still agree.)
    @Test func projectionAgreesWithComponentOnHugeVectors() throws {
        expectApprox(try vector("proj(<1,0,0>, <1e200,0,0>)"), Vec3(1, 0, 0), tolerance: 1e-12)
        expectApprox(try scalar("comp(<1,0,0>, <1e200,0,0>)"), 1, tolerance: 1e-12)
        expectApprox(try vector("proj(<3,4,0>, <1e200,0,0>)"), Vec3(3, 0, 0), tolerance: 1e-12)
        expectApprox(try vector("proj(<3,4,0>, <3e200,4e200,0>)"), Vec3(3, 4, 0), tolerance: 1e-12)
        // proj and comp must accept and reject exactly the same second argument.
        #expect(throws: EvalError.self) { _ = try lastValue("proj(i, <0,0,0>)") }
        #expect(throws: EvalError.self) { _ = try lastValue("comp(i, <0,0,0>)") }
        // PASS 6 OVERTURNED THESE TWO. A small b is a perfectly good direction;
        // what matters is that proj and comp still agree, so they are now
        // pinned as agreeing successes rather than as agreeing errors.
        expectApprox(try vector("proj(i, <1e-20,0,0>)"), Vec3(1, 0, 0), tolerance: 1e-15)
        expectApprox(try scalar("comp(i, <1e-20,0,0>)"), 1, tolerance: 1e-15)
    }

    /// Parser.expression recurses once per nesting level with no limit, so a
    /// pasted line with a few thousand parens overflowed the stack and took
    /// the whole app down. It must be an error message instead.
    @Test func deepNestingErrorsInsteadOfCrashing() throws {
        let deep = String(repeating: "(", count: 5000) + "1" + String(repeating: ")", count: 5000)
        #expect(throws: EvalError.self) { _ = try Parser.parseLine(deep) }
        // A long unary run recurses through unary(), not through parens.
        #expect(throws: EvalError.self) { _ = try Parser.parseLine(String(repeating: "-", count: 5000) + "1") }
        // Nesting a human would actually type still parses and evaluates.
        let ok = String(repeating: "(", count: 30) + "2+3" + String(repeating: ")", count: 30)
        expectApprox(try scalar(ok), 5)
    }

    /// Any undefined name starting r_ / R_ was reported as a missing set of
    /// points, so a reaction force named R_max asked the reader to "define
    /// points m and a and x first".
    @Test func undefinedUnderscoreNameReadsAsUndefined() throws {
        let message = { (line: String) -> String in
            Engine.evaluate([line])[0].errorMessage ?? ""
        }
        #expect(message("R_max").contains("not defined"), "got: \(message("R_max"))")
        #expect(!message("R_max").contains("define points"), "got: \(message("R_max"))")
        // But when one endpoint IS a defined point, the helpful message stays.
        let partial = Engine.evaluate(["point A = (1,2,3)", "r_AB"])[1].errorMessage ?? ""
        #expect(partial.contains("define points"), "got: \(partial)")
    }

    /// `origin` is a builtin point, but autoPositionVector only consulted the
    /// user environment, so r_originA could not resolve against it.
    @Test func originResolvesAsAPositionVectorEndpoint() throws {
        expectApprox(try vector("point A = (1, 2, 3)", "r_originA"), Vec3(1, 2, 3))
        expectApprox(try vector("point A = (1, 2, 3)", "r_Aorigin"), Vec3(-1, -2, -3))
        // Basis vectors are directions, not places: r_ij is still undefined.
        #expect(throws: EvalError.self) { _ = try lastValue("r_ij") }
    }

    @Test func mixedTypeErrors() {
        #expect(throws: EvalError.self) { _ = try lastValue("<1,2,3> + 5") }
        #expect(throws: EvalError.self) { _ = try lastValue("<1,2,3> ^ 2") }
        #expect(throws: EvalError.self) { _ = try lastValue("5 × 3") }
        #expect(throws: EvalError.self) { _ = try lastValue("cos(i)") }
        #expect(throws: EvalError.self) { _ = try lastValue("dot(1, 2)") }
    }
}
