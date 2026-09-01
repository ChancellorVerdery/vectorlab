import Foundation
import Testing
@testable import VectorLabCore

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

    @Test func mixedTypeErrors() {
        #expect(throws: EvalError.self) { _ = try lastValue("<1,2,3> + 5") }
        #expect(throws: EvalError.self) { _ = try lastValue("<1,2,3> ^ 2") }
        #expect(throws: EvalError.self) { _ = try lastValue("5 × 3") }
        #expect(throws: EvalError.self) { _ = try lastValue("cos(i)") }
        #expect(throws: EvalError.self) { _ = try lastValue("dot(1, 2)") }
    }
}
