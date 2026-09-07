import Testing
import Foundation
@testable import VectorLabCore

/// Pass 9. Two items every earlier pass handed forward:
///   * `Fmt.num`'s fixed-point band loses almost all precision at its bottom
///     edge (measured and handed back by pass 8 as a decision).
///   * `1e` lexes as `1 * e` = 2.718 (open since pass 1; pass 7 recommended
///     the fix, pass 8 agreed, nobody made the call).
@Suite struct Pass9Tests {

    private func result(_ line: String) -> LineOutcome { Engine.evaluate([line])[0] }

    // MARK: - Fmt precision

    /// Pass 8's measurement, as a test. The fixed band is [1e-4, 1e15) with
    /// four decimal places, so a value just inside the bottom of it carries a
    /// single significant digit: 1.2345e-4 printed "0.0001", 19% wrong.
    @Test func smallNumbersInTheFixedBandKeepFourSignificantDigits() {
        let cases: [Double] = [
            0.0001234499999999999,
            0.0009876539999999993,
            0.0012344999999999988,
            0.009876539999999993,
            0.09876539999999993,
            0.1234499999999999,
            1.7453292519943296e-4,     // sin(0.01)
            -0.00034567,
            0.00010000000001,
        ]
        for v in cases {
            let s = Fmt.num(v)
            guard let back = Double(s) else {
                Issue.record("unreadable \(s) for \(v)"); continue
            }
            let rel = abs(back - v) / abs(v)
            #expect(rel < 5e-4, "\(v) -> \"\(s)\"  \(String(format: "%.3f", rel * 100))% wrong")
        }
    }

    /// The concrete notebook line. sin(0.01) = 1.7453e-4 printed "0.0002",
    /// while the SMALLER sin(0.005) printed 8.7266e-5 with five digits —
    /// the less extreme input got the worse answer.
    @Test func aSmallSinePrintsMoreThanOneDigit() {
        #expect(result("sin(0.01)").resultText == "0.0001745")
        #expect(result("sin(0.005)").resultText == "8.7266e-5")   // unchanged
    }

    /// PIN (passes pre-fix). The fix must not buy precision by moving values
    /// passes 1-8 all held must not move. Everything at |d| >= 0.1 is
    /// bit-identical to the old four-decimal expression.
    @Test func ordinaryNumbersAreBitIdenticalToBefore() {
        func old(_ d: Double) -> String {
            let rounded = (d * 10_000).rounded() / 10_000
            var s: String
            if rounded == rounded.rounded() { s = String(format: "%.0f", rounded) }
            else {
                s = String(format: "%.4f", rounded)
                while s.hasSuffix("0") { s.removeLast() }
                if s.hasSuffix(".") { s.removeLast() }
            }
            return s == "-0" ? "0" : s
        }
        var checked = 0
        for n in stride(from: -20_000, through: 20_000, by: 1) {
            for scaleUp in [1.0, 7.25, 1_000.0, 1e9] {
                let d = Double(n) / 137.0 * scaleUp
                let a = abs(d)
                // Bounded at 1e11: above that, four decimals runs past the
                // 15 digits a Double carries, which is bug 3 below.
                guard a >= 0.1, a < 1e11 else { continue }
                #expect(Fmt.num(d) == old(d), "\(d): \(Fmt.num(d)) vs \(old(d))")
                checked += 1
            }
        }
        #expect(checked > 100_000, "only \(checked) vectors checked")
        // The values pass 3 pinned character-for-character, restated.
        #expect(Fmt.num(0) == "0")
        #expect(Fmt.num(-0.0) == "0")
        #expect(Fmt.num(1.5) == "1.5")
        #expect(Fmt.num(0.0001) == "0.0001")
        #expect(Fmt.num(2.0 / 3.0) == "0.6667")
        #expect(Fmt.num(1234567.25) == "1234567.25")
        #expect(Fmt.num(1e14) == "100000000000000")
    }

    /// The scientific path either side of the cutoff is untouched, and the
    /// step across 1e-4 no longer LOSES digits going up.
    @Test func theBandBoundaryIsNoLongerADiscontinuity() {
        #expect(Fmt.num(9e-5) == "9e-5")
        #expect(Fmt.num(5e-200) == "5e-200")
        #expect(Fmt.num(1e305).count < 20)
        // Just above the cutoff must be at least as faithful as just below.
        for v in [1.23456e-4, 1.00001e-4, 9.9999e-4] {
            let rel = abs(Double(Fmt.num(v))! - v) / v
            #expect(rel < 5e-4, "\(v) -> \(Fmt.num(v))")
        }
    }

    /// Pass 3 moved to scientific notation at 1e15 because fixed point was
    /// printing the exact binary expansion — "digits the value does not
    /// carry". The cutoff was one notch too high: four decimals on a value
    /// near 1e14 is 19 significant digits, and the last four are residue.
    @Test func theTopOfTheFixedBandDoesNotPrintBinaryResidue() {
        #expect(Fmt.num(123456789012345.6) == "123456789012346")
        #expect(Fmt.num(99999999999999.98) == "100000000000000")
        for v in [123456789012345.6, 99999999999999.98, 1.5e13, 8.25e11] {
            let s = Fmt.num(v)
            let digits = s.filter { $0.isNumber }.count
            #expect(digits <= 15, "\(v) -> \"\(s)\" has \(digits) significant digits")
            #expect(abs(Double(s)! - v) / v < 5e-4, "\(v) -> \"\(s)\"")
        }
        // The boundary below which nothing moves.
        #expect(Fmt.num(12345678901.23456) == "12345678901.2346")
        #expect(Fmt.num(1234567.25) == "1234567.25")
    }

    // MARK: - Truncated exponent

    /// Open since pass 1. `\vec F = 1e` read 2.718 N and printed it as a
    /// confident answer; there is no signal anywhere that the exponent the
    /// user was typing never arrived.
    @Test func aTruncatedExponentIsAnError() {
        for line in ["1e", "2E", "\\vec F = 1e", "mag(<1e, 0, 0>)", "3.5e"] {
            let out = result(line)
            #expect(out.errorMessage != nil, "\(line) -> \(out.resultText)")
        }
        #expect(result("1e").errorMessage?.contains("truncated exponent") == true)
    }

    /// PIN (passes pre-fix). Real exponents, Euler's number written on its
    /// own, and implicit multiplication by a name that merely STARTS with e
    /// all keep working. Only a bare `e` after digits errors.
    @Test func realExponentsAndEulerStillWork() {
        #expect(result("1e6").resultText == "1000000")
        #expect(result("2e-3").resultText == "0.002")
        #expect(result("2e+3").resultText == "2000")
        #expect(result("1e400").errorMessage == nil)          // ∞ is a value, not a lex error
        #expect(result("e").resultText == "2.7183")
        #expect(result("2*e").resultText == "5.4366")
        #expect(Engine.evaluate(["energy = 3", "2energy"])[1].resultText == "6")
        #expect(Engine.evaluate(["e_1 = 4", "2e_1"])[1].resultText == "8")
    }
}
