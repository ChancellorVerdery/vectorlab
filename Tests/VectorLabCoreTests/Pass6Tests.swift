import Foundation
import Testing
@testable import VectorLabCore

/// Pass 6. Every test here was written and run against the pass-5 tree before
/// its fix, so each claim below is a recorded failure rather than an assertion.
///
/// Subject: the disagreement passes 2, 3, 4 and 5 each flagged and each left
/// alone — `mag(<3e-200, 4e-200, 0>)` answers 5e-200 while `unit()` of that
/// same vector calls it zero.
@Suite struct Pass6Tests {

    /// THE HEADLINE. `unit()` is supposed to answer a direction, and direction
    /// is scale-free: <3e-11, 4e-11, 0> and <3e-13, 4e-13, 0> point the same
    /// way. Vec3.normalized rejected the second one and accepted the first,
    /// purely because of an ABSOLUTE 1e-12 cutoff in a tool that has no unit
    /// system. The user picking metres rather than kilometres changes whether
    /// their vector is deemed to have a direction at all.
    @Test func unitIsScaleInvariant() throws {
        let want = Vec3(0.6, 0.8, 0)
        for line in ["unit(<3e-11, 4e-11, 0>)",
                     "unit(<3e-13, 4e-13, 0>)",
                     "unit(<3e-200, 4e-200, 0>)",
                     "unit(<3, 4, 0>)",
                     "unit(<3e200, 4e200, 0>)"] {
            let u = try vector(line)
            expectApprox(u, want, tolerance: 1e-15)
        }
    }

    /// The disagreement stated directly: if mag(v) reports a length, unit(v)
    /// must not call v zero. Pre-fix these two lines of one notebook session
    /// contradicted each other on screen.
    @Test func magAndUnitAgreeAboutWhetherAVectorHasALength() {
        let out = Engine.evaluate(["mag(<3e-200, 4e-200, 0>)",
                                   "unit(<3e-200, 4e-200, 0>)"])
        #expect(out[0].resultText != "0", "mag printed \(out[0].resultText)")
        #expect(out[1].errorMessage == nil,
                "mag said \(out[0].resultText) but unit said: \(out[1].errorMessage ?? "")")
    }

    /// proj and comp were locked to the same cutoff by pass 2, so they carried
    /// the same scale dependence: a projection onto a small-but-perfectly-good
    /// direction was refused.
    @Test func projAndCompAcceptAnyDirectionUnitAccepts() throws {
        expectApprox(try scalar("comp(<1,0,0>, <1e-20, 0, 0>)"), 1, tolerance: 1e-15)
        expectApprox(try vector("proj(<1,0,0>, <1e-20, 0, 0>)"), Vec3(1, 0, 0), tolerance: 1e-15)
        expectApprox(try scalar("angle(<3e-200, 4e-200, 0>, <1e-200, 0, 0>)"),
                     53.13010235415598, tolerance: 1e-12)
    }

    /// Down to the smallest subnormal the reduction still produces a true unit
    /// vector — so there is no numerical range the cutoff was protecting.
    @Test func evenSubnormalVectorsNormalizeExactly() throws {
        for line in ["unit(<3e-310, 4e-310, 0>)", "unit(<3e-320, 4e-320, 0>)"] {
            expectApprox(try vector(line), Vec3(0.6, 0.8, 0), tolerance: 1e-3)
            expectApprox(try scalar("|\(line)|"), 1, tolerance: 1e-15)
        }
        expectApprox(try vector("unit(<5e-324, 0, 0>)"), Vec3(1, 0, 0), tolerance: 1e-15)
    }

    /// What is still refused, and it is exactly two things: the true zero
    /// vector, and a vector with no finite direction. Pass 3's two distinct
    /// error messages must both survive.
    @Test func onlyZeroAndNonFiniteVectorsHaveNoDirection() {
        func message(_ line: String) -> String { Engine.evaluate([line])[0].errorMessage ?? "" }
        #expect(message("unit(<0, 0, 0>)").contains("zero"))
        #expect(message("proj(i, <0, 0, 0>)").contains("zero"))
        let inf = message("unit(<1e400, 0, 0>)")
        #expect(!inf.isEmpty && !inf.contains("zero"), "got: \(inf)")
    }

    /// REGRESSION PIN, not a recorded failure — this one passes pre-fix and
    /// must keep passing. Removing the cutoff must not perturb a single bit of
    /// any vector that already had a direction. Passes 1–5 all held this line.
    @Test func ordinaryUnitVectorsAreBitIdenticalToBefore() {
        var checked = 0
        for a in stride(from: -9.0, through: 9.0, by: 0.37) {
            for b in stride(from: -9.0, through: 9.0, by: 0.53) {
                for c in stride(from: -5.0, through: 5.0, by: 0.71) {
                    let v = Vec3(a, b, c)
                    let m = v.maxAbsComponent
                    guard m > 0 else { continue }
                    // The pass-5 expression, reproduced here verbatim.
                    let r = v / m
                    guard r.length * m > 1e-12 else { continue }
                    let before = r / r.length
                    guard let after = v.normalized else {
                        Issue.record("\(Fmt.vector(v)) lost its direction")
                        continue
                    }
                    checked += 1
                    #expect(after.x == before.x && after.y == before.y && after.z == before.z,
                            "\(Fmt.vector(v)): \(Fmt.vector(before)) -> \(Fmt.vector(after))")
                }
            }
        }
        #expect(checked > 20_000, "only checked \(checked)")
    }
}
