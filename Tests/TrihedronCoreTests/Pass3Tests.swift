import Foundation
import Testing
@testable import TrihedronCore

/// Pass 3. Each test here was written and run against the pass-2 tree before
/// the corresponding fix, so every claim below is a recorded failure.
@Suite struct Pass3Tests {

    /// Pass 2 added a depth counter in unary() on the stated ground that
    /// "every recursive path in the grammar passes through it". One does not:
    /// primary() handles a stray \vec by calling ITSELF. Bare `vec` lexes as
    /// the same token, so a pasted run of a few thousand recurses with no
    /// bound and takes the process down instead of erroring.
    @Test func repeatedVecKeywordErrorsInsteadOfCrashing() throws {
        #expect(throws: EvalError.self) {
            _ = try Parser.parseLine(String(repeating: "vec ", count: 5000) + "1")
        }
        #expect(throws: EvalError.self) {
            _ = try Parser.parseLine(String(repeating: #"\vec "#, count: 5000) + "1")
        }
        // A handful of stray marks is still cosmetic and still evaluates.
        expectApprox(try scalar("vec vec 2 + 3"), 5)
        expectApprox(try vector(#"\vec \vec <1,2,3>"#), Vec3(1, 2, 3))
    }

    /// Fmt.num rounds to 4 decimals through a fixed-point path, so every
    /// nonzero value below 5e-5 printed as "0" — including exactly the tiny
    /// magnitudes pass 2 taught mag() to compute correctly. The same path
    /// prints a 200-digit wall at the other end.
    @Test func numbersOutsideTheFixedPointBandPrintReadably() {
        for v in [5e-200, 1e-5, 2.5e-7, -3e-120, 1.4142135623730951e200, 1e305, -1e21] {
            let s = Fmt.num(v)
            guard let back = Double(s) else {
                Issue.record("Fmt.num(\(v)) = \(s) does not read back as a number")
                continue
            }
            #expect(abs(back - v) <= abs(v) * 1e-4, "printed \(s) for \(v)")
            #expect(s.count <= 16, "printed \(s.count) characters for \(v): \(s)")
        }
    }

    /// The ordinary band must not move by a character.
    @Test func ordinaryNumbersFormatExactlyAsBefore() {
        #expect(Fmt.num(0) == "0")
        #expect(Fmt.num(-0.0) == "0")
        #expect(Fmt.num(7) == "7")
        #expect(Fmt.num(-7) == "-7")
        #expect(Fmt.num(1.5) == "1.5")
        #expect(Fmt.num(0.0001) == "0.0001")
        #expect(Fmt.num(1234567.25) == "1234567.25")
        #expect(Fmt.num(2.0 / 3.0) == "0.6667")
        #expect(Fmt.num(1e14) == "100000000000000")
    }

    /// Pass 2 taught mag() to answer 5e-200 instead of 0; the notebook still
    /// printed "0", so the fix was invisible where it mattered.
    @Test func tinyMagnitudePrintsAsNonZero() {
        let shown = Engine.evaluate(["mag(<3e-200, 4e-200, 0>)"])[0].resultText
        #expect(shown != "0", "printed \(shown)")
        guard let back = Double(shown) else {
            Issue.record("unreadable result text \(shown)")
            return
        }
        #expect(abs(back - 5e-200) <= 5e-204, "printed \(shown)")
    }

    /// unit()/proj()/comp() reject a vector with a NaN or infinite component
    /// by way of normalized() returning nil, and then blame "a zero vector".
    /// It is not zero, and the reader is sent hunting for the wrong mistake.
    @Test func nonFiniteVectorIsNotReportedAsZero() {
        func message(_ line: String) -> String { Engine.evaluate([line])[0].errorMessage ?? "" }
        for line in ["unit(<1e400, 0, 0>)",
                     "proj(i, <1e400, 0, 0>)",
                     "comp(i, <5, 1e400 - 1e400, 0>)"] {
            let m = message(line)
            #expect(!m.isEmpty, "\(line) should be an error")
            #expect(!m.contains("zero"), "\(line) got: \(m)")
        }
        // The genuine zero vector still says zero.
        #expect(message("unit(<0,0,0>)").contains("zero"))
        #expect(message("proj(i, <0,0,0>)").contains("zero"))
    }
}
