import Foundation
import Testing
@testable import TrihedronCore

/// Pass 7. Same method as passes 1–6: every test here was written and run
/// against the pass-6 tree BEFORE its fix, so each claim is a recorded failure
/// rather than an assertion. The two pins say so where they apply.
@Suite struct Pass7Tests {

    /// Reference magnitude, computed the way `Vec3.length`'s fallback does it:
    /// reduce by the largest component, then square. Exact at every scale.
    private func reference(_ v: Vec3) -> Double {
        let m = v.maxAbsComponent
        guard m > 0, m.isFinite else { return m }
        let r = v / m
        return (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot() * m
    }

    /// THE HEADLINE. `Vec3.length` takes the fast path whenever the sum of
    /// squares is `isFinite && > 0`. Between roughly 1e-155 and 1e-162 that sum
    /// is SUBNORMAL: nonzero, finite, and carrying only a handful of bits. The
    /// guard passes and the answer is quietly wrong in digits the notebook
    /// prints. Below ~1e-162 the square flushes to zero, the guard fails, and
    /// the exact fallback runs — so the defect is a BAND, not a tail, which is
    /// why it survived the pass-1 rewrite that named both other ends.
    ///
    /// The bar is a few ULP of the reduced reference, not equality: in the
    /// normal range the naive sum and the reduced sum legitimately differ by
    /// one rounding, and passes 1–6 all held the line that those values must
    /// not move. What is not acceptable is 0.6%.
    @Test func magnitudeIsExactWhereTheSumOfSquaresIsSubnormal() {
        var offenders: [String] = []
        for e in stride(from: -140.0, through: -175.0, by: -1) {
            let s = Foundation.pow(10.0, e)
            let v = Vec3(3 * s, 4 * s, 0)
            let want = reference(v)
            let got = v.length
            if abs(got - want) > 2 * want.ulp {
                offenders.append("1e\(Int(e)): length \(got) != \(want), off by \(abs(got - want) / want)")
            }
        }
        #expect(offenders.isEmpty, "\(offenders.count) wrong magnitudes: \(offenders.prefix(4))")
    }

    /// The same defect as the user sees it. `<3e-162, 4e-162, 0>` has a
    /// magnitude of exactly 5e-162 and the notebook printed 4.9702e-162 —
    /// 0.6% out, in a tool whose whole job is to answer |v|.
    @Test func theNotebookPrintsTheRightMagnitudeForTinyVectors() {
        let out = Engine.evaluate(["\\vec v = <3e-162, 4e-162, 0>", "mag(v)"])
        #expect(out[0].resultText == "<3e-162, 4e-162, 0>   |v| = 5e-162",
                "line 1 printed \(out[0].resultText)")
        #expect(out[1].resultText == "5e-162", "mag(v) printed \(out[1].resultText)")
    }

    /// `dist` and `|…|` go through the same `length`, so they were wrong too.
    @Test func distanceIsExactAtTheSameScale() throws {
        let d = try scalar("point A = (0, 0, 0)", "point B = (3e-160, 4e-160, 0)", "dist(A, B)")
        #expect(d == 5e-160, "dist printed \(d)")
    }

    /// PIN, not a recorded failure: nothing in the ordinary range may move by a
    /// single bit. `==` against the naive expression, not a tolerance — the
    /// same line passes 1–6 all held.
    @Test func ordinaryMagnitudesAreBitIdenticalToBefore() {
        var moved = 0, checked = 0
        for x in stride(from: -50.0, through: 50.0, by: 0.7) {
            for y in stride(from: -30.0, through: 30.0, by: 1.3) {
                for zs in [0.0, 1.0, -7.25, 1e6, 1e-6] {
                    let v = Vec3(x, y, zs)
                    let naive = (x * x + y * y + zs * zs).squareRoot()
                    checked += 1
                    if v.length != naive { moved += 1 }
                }
            }
        }
        #expect(moved == 0, "\(moved)/\(checked) ordinary magnitudes changed")
    }

    /// `1/0` is a named error, but `0^-1` — the same division by zero, written
    /// with an exponent — printed ∞. One notebook, two answers to one question.
    @Test func zeroToANegativePowerIsDivisionByZeroToo() {
        let out = Engine.evaluate(["1/0", "0^-1", "0^-2", "0^-0.5"])
        for (i, line) in ["1/0", "0^-1", "0^-2", "0^-0.5"].enumerated() {
            #expect(out[i].errorMessage != nil,
                    "\(line) printed \(out[i].resultText) instead of erroring")
        }
    }

    /// Powers that are not division by zero must be untouched.
    @Test func ordinaryPowersStillWork() throws {
        #expect(try scalar("2^-1") == 0.5)
        #expect(try scalar("0^0") == 1)
        #expect(try scalar("0^2") == 0)
        #expect(try scalar("2^10") == 1024)
        #expect(try scalar("9^0.5") == 3)
    }

    /// `Engine.arc` re-evaluates the two argument expressions AFTER `execute`
    /// has already mutated the environment, so a self-redefining line reads the
    /// value it just wrote. `a = angle(a, b)` makes `a` a scalar, the re-read
    /// fails the vector guard, and the arc silently does not appear — for the
    /// one line that is literally an angle measurement. Flagged as a corner by
    /// pass 6; recorded as a failure here.
    @Test func aSelfRedefiningAngleLineStillDrawsItsArc() {
        let out = Engine.evaluate(["\\vec a = <1, 0, 0>",
                                   "\\vec b = <0, 1, 0>",
                                   "a = angle(a, b)"])
        #expect(out[2].errorMessage == nil, "line 3: \(out[2].errorMessage ?? "")")
        #expect(out[2].resultText == "90", "line 3 printed \(out[2].resultText)")
        #expect(out[2].arc != nil, "no arc drawn for an angle() line")
    }

    /// PIN, not a recorded failure: the ordinary angle line must keep its arc.
    @Test func anOrdinaryAngleLineStillDrawsItsArc() {
        let out = Engine.evaluate(["\\vec a = <1, 0, 0>",
                                   "\\vec b = <0, 1, 0>",
                                   "theta = angle(a, b)",
                                   "angle(a, b)"])
        #expect(out[2].arc?.degrees == 90)
        #expect(out[3].arc?.degrees == 90)
    }

    /// PIN for the pass-6 lead "nothing pins the inverse-trig exactness".
    /// asin/acos/atan/atan2/deg return degrees via `rad * 180 / .pi`, which
    /// pass 6 MEASURED to be exact at every cardinal point. If that conversion
    /// is ever reworked the exact 90s and 45s would go silently.
    @Test func inverseTrigIsExactAtTheCardinalPoints() throws {
        let cases: [(String, Double)] = [
            ("acos(1)", 0), ("acos(0)", 90), ("acos(-1)", 180),
            ("asin(0)", 0), ("asin(1)", 90), ("asin(-1)", -90),
            ("atan(0)", 0), ("atan(1)", 45), ("atan(-1)", -45),
            ("atan2(1, 0)", 90), ("atan2(0, -1)", 180), ("atan2(-1, 0)", -90),
            ("atan2(1, 1)", 45), ("deg(pi)", 180), ("deg(pi/2)", 90),
        ]
        for (line, want) in cases {
            let got = try scalar(line)
            #expect(got == want, "\(line) = \(got), wanted exactly \(want)")
        }
        // And it composes with pass 5's exact degree trig rather than being
        // defeated by it: the round trip through angle() stays exact.
        #expect(try scalar("cos(angle(<1,0,0>, <0,1,0>))") == 0)
        #expect(try scalar("sin(angle(<1,0,0>, <-1,0,0>))") == 0)
    }

    /// PIN for the pass-4/5/6 lead about the dead `case "π"` in the Lexer's
    /// punctuation switch: π must keep lexing as the constant however it gets
    /// there, so the dead branch can be removed without a behaviour change.
    @Test func piLexesAsTheConstantEveryWayItIsWritten() throws {
        #expect(try scalar("pi") == Double.pi)
        #expect(try scalar("π") == Double.pi)
        #expect(try scalar("\\pi") == Double.pi)
        #expect(try scalar("2π") == 2 * Double.pi)
    }
}
