import Foundation
import Testing
@testable import TrihedronCore

/// Pass 5. Every test here was written and run against the pass-4 tree before
/// its fix, so each claim below is a recorded failure rather than an assertion.
@Suite struct Pass5Tests {

    /// The headline defect: a force pointing straight up grew a sideways
    /// component. `m ∠ θ` builds `Vec3(m·cos θ, m·sin θ, 0)` through
    /// Foundation, which takes RADIANS — and no multiple of 90° except 0 has
    /// an exact radian representation, so `cos(90 · π/180)` is 6.1232e-17
    /// rather than 0. Pass 1–2's four-decimal rounding hid it; pass 3 gave Fmt
    /// scientific notation below 1e-4 (correctly — `mag()` must be able to
    /// print 5e-200) and the residue surfaced on the most common line in the
    /// whole app: `\vec F = 500 ∠ 90` printed `<3.0616e-14, 500, 0>`.
    @Test func polarVectorsOnTheAxesHaveNoOffAxisComponent() throws {
        #expect(try vector("100 @ 0")   == Vec3(100, 0, 0))
        #expect(try vector("100 @ 90")  == Vec3(0, 100, 0))
        #expect(try vector("100 @ 180") == Vec3(-100, 0, 0))
        #expect(try vector("100 @ 270") == Vec3(0, -100, 0))
        #expect(try vector("100 @ 360") == Vec3(100, 0, 0))
        #expect(try vector("100 @ -90") == Vec3(0, -100, 0))
        // Off-axis polar is unchanged: 3-4-5 to the usual precision.
        expectApprox(try vector("5 @ 53.13010235415598"), Vec3(3, 4, 0), tolerance: 1e-12)
    }

    /// The same residue reaches the notebook as printed text, which is what a
    /// student actually reads. Pre-fix this line ended `<3.0616e-14, 500, 0>`.
    @Test func aVerticalForcePrintsAsVertical() {
        let out = Engine.evaluate([#"\vec F = 500 @ 90"#])[0]
        #expect(out.resultText == "<0, 500, 0>   |v| = 500")
    }

    /// Summing an up force and a down force must leave nothing behind.
    /// Pre-fix: `<-6.1232e-15, 300, 0>`.
    @Test func resultantOfVerticalForcesHasNoHorizontalDrift() throws {
        #expect(try vector(#"\vec F = 500 @ 90"#,
                           #"\vec W = 200 @ 270"#,
                           "resultant(F, W)") == Vec3(0, 300, 0))
    }

    /// sin/cos/tan are degree-based in this app, so the quadrant multiples are
    /// the values users type most and they must be exact.
    @Test func degreeTrigIsExactAtQuadrantMultiples() throws {
        #expect(try scalar("sin(0)")    == 0)
        #expect(try scalar("sin(180)")  == 0)
        #expect(try scalar("sin(360)")  == 0)
        #expect(try scalar("sin(-180)") == 0)
        #expect(try scalar("cos(90)")   == 0)
        #expect(try scalar("cos(270)")  == 0)
        #expect(try scalar("cos(-90)")  == 0)
        #expect(try scalar("tan(180)")  == 0)
        #expect(try scalar("tan(0)")    == 0)
        // The ±1 points were already exact; pin them so the fix can't lose them.
        #expect(try scalar("sin(90)")   == 1)
        #expect(try scalar("sin(270)")  == -1)
        #expect(try scalar("cos(0)")    == 1)
        #expect(try scalar("cos(180)")  == -1)
        #expect(try scalar("sin(-90)")  == -1)
    }

    /// tan is undefined at the odd multiples of 90. Foundation answers
    /// 1.6331e16, which reads on screen as a real, enormous number — a student
    /// copying it into the next line gets nonsense with no warning.
    @Test func tangentIsUndefinedAtOddMultiplesOf90() {
        for line in ["tan(90)", "tan(-90)", "tan(270)", "tan(450)"] {
            #expect(throws: EvalError.self, "\(line) should be undefined") {
                _ = try scalar(line)
            }
        }
    }

    /// The fix must not move any value that was already right. Everything off
    /// the quadrant multiples goes through the identical Foundation call on
    /// the identical argument, so these are BIT-exact comparisons, not
    /// tolerances.
    @Test func ordinaryAnglesAreBitIdenticalToBefore() throws {
        for d in [1.0, 30, 37, 45, 59.5, 60, 123.456, -17.25, 359.9] {
            #expect(try scalar("sin(\(d))") == Foundation.sin(d * Double.pi / 180),
                    "sin(\(d)) moved")
            #expect(try scalar("cos(\(d))") == Foundation.cos(d * Double.pi / 180),
                    "cos(\(d)) moved")
            #expect(try scalar("tan(\(d))") == Foundation.tan(d * Double.pi / 180),
                    "tan(\(d)) moved")
        }
    }
}
