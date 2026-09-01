import Foundation
import Testing
@testable import VectorLabCore

/// Full worked statics problems with hand-computed expected values.
@Suite struct StaticsTests {
    /// A 260 lb force acts along the cable from A(0,0,12) to B(4,-3,0).
    /// |r_AB| = √(16+9+144) = 13, so F = 20·(4,-3,-12) = (80,-60,-240).
    /// Moment about O of F applied at A: (0,0,12)×(80,-60,-240) = (720, 960, 0).
    @Test func cableForceProblem() throws {
        let lines = [
            "point O = (0, 0, 0)",
            "point A = (0, 0, 12)",
            "point B = (4, -3, 0)",
            "r_AB",
            "\\vec F = 260 * unit(r_AB)",
            "\\vec M_O = moment(r_OA, F)",
        ]
        let outcomes = Engine.evaluate(lines)
        #expect(outcomes.allSatisfy { $0.errorMessage == nil })

        expectApprox(try vector(lines[0], lines[1], lines[2], "r_AB"), Vec3(4, -3, -12))
        expectApprox(try scalar(lines[0], lines[1], lines[2], "|r_AB|"), 13)
        expectApprox(try vector(lines[0], lines[1], lines[2], lines[4], "F"),
                     Vec3(80, -60, -240), tolerance: 1e-9)
        expectApprox(try vector(lines[0], lines[1], lines[2], lines[4], "moment(r_OA, F)"),
                     Vec3(720, 960, 0), tolerance: 1e-9)
        // Angle F makes with the vertical: cos θ = −240/260 → 157.3801°
        expectApprox(try scalar(lines[0], lines[1], lines[2], lines[4], "angle(F, k)"),
                     157.38013505195957, tolerance: 1e-6)
    }

    /// 2D concurrent force equilibrium: three forces balance.
    @Test func concurrentForces2D() throws {
        expectApprox(
            try vector("F1 = 100∠30", "F2 = 100∠150", "F3 = <0, -100, 0>",
                       "R = resultant(F1, F2, F3)"),
            Vec3(0, 0, 0), tolerance: 1e-9)
    }

    /// Direction cosines of F = (60, 80, 240): |F| = 260... actually
    /// √(3600+6400+57600) = √67600 = 260. cos α = 60/260.
    @Test func directionCosines() throws {
        let setup = "F = <60, 80, 240>"
        expectApprox(try scalar(setup, "angle(F, i)"),
                     Foundation.acos(60.0 / 260.0) * 180 / .pi, tolerance: 1e-9)
        expectApprox(try scalar(setup, "F.x / |F|"), 60.0 / 260.0, tolerance: 1e-12)
    }

    /// Moment of a force about an axis (Hibbeler-style): F = (0, 0, 10) at
    /// point (2, 3, 0); moment about the x axis = x̂ · (r × F).
    /// r × F = (3·10 − 0, 0 − 2·10, 0) = (30, −20, 0) → about x: 30.
    @Test func momentAboutAxis() throws {
        expectApprox(try scalar("r = <2, 3, 0>", "F = <0, 0, 10>", "moment(i, r, F)"), 30)
        expectApprox(try vector("r = <2, 3, 0>", "F = <0, 0, 10>", "moment(r, F)"),
                     Vec3(30, -20, 0))
    }

    /// Projection of a force onto a member: F = (100, 200, -50) onto the
    /// member along u = (2, 2, 1)/3. comp = (200 + 400 − 50)/3 = 550/3.
    @Test func forceAlongMember() throws {
        let lines = ["F = <100, 200, -50>", "u = unit(<2, 2, 1>)"]
        expectApprox(try scalar(lines[0], lines[1], "comp(F, u)"), 550.0 / 3.0, tolerance: 1e-9)
        expectApprox(try vector(lines[0], lines[1], "proj(F, u)"),
                     (550.0 / 9.0) * Vec3(2, 2, 1), tolerance: 1e-9)
    }

    /// The whole sample workspace the app ships with must evaluate cleanly.
    @Test func sampleWorkspaceIsClean() throws {
        let lines = [
            "# Example: 260 lb force along cable AB",
            "point O = (0, 0, 0)",
            "point A = (0, 0, 12)",
            "point B = (4, -3, 0)",
            "r_AB",
            "\\vec F = 260 * unit(r_AB)",
            "\\vec M_O = moment(r_OA, F)",
            "angle(F, r_OA)",
            "",
            "# Try: \\vec a = <1,2,3>   \\hat u = unit(a)   a*û   cross(a, û)   \\vec T = 50∠30",
        ]
        let outcomes = Engine.evaluate(lines)
        #expect(outcomes.allSatisfy { $0.errorMessage == nil })
        // r_AB draws from A, not the origin
        if case .arrow(let tail, let vec)? = outcomes[4].drawable?.shape {
            expectApprox(tail, Vec3(0, 0, 12))
            expectApprox(vec, Vec3(4, -3, -12))
        } else {
            Issue.record("r_AB should be drawable as an arrow")
        }
        // angle(F, r_OA) produces an arc
        #expect(outcomes[7].arc != nil)
        expectApprox(outcomes[7].arc!.degrees, 157.38013505195957, tolerance: 1e-6)
    }
}
