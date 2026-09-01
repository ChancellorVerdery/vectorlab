import Foundation
import Testing
@testable import VectorLabCore

@Suite struct NotationTests {
    @Test func angleBracketVector() throws {
        expectApprox(try vector("a = <1, 2, 3>", "a"), Vec3(1, 2, 3))
    }

    @Test func latexVecKeyword() throws {
        expectApprox(try vector(#"\vec a = <1, 2, 3>"#, "a"), Vec3(1, 2, 3))
        expectApprox(try vector(#"\vector b = [4, 5, 6]"#, "b"), Vec3(4, 5, 6))
        expectApprox(try vector(#"\hat u = unit(<3, 4, 0>)"#, "û"), Vec3(0.6, 0.8, 0))
    }

    @Test func hatIsADistinctVariable() throws {
        expectApprox(try scalar("u = <9, 9, 9>", #"\hat u = i"#, "u.x"), 9)
        expectApprox(try scalar("u = <9, 9, 9>", #"\hat u = i"#, "û.x"), 1)
        expectApprox(try scalar("û = j", #"\hat u · j"#), 1)   // typed û ≡ \hat u
    }

    @Test func hatParenAndBraceForms() throws {
        let expected = Vec3(3.0.squareRoot() / 2, 0.5, 0)
        expectApprox(try vector("theta = 30", #"\hat(u) = cos(theta)i + sin(theta)j"#, "û"),
                     expected, tolerance: 1e-12)
        expectApprox(try vector("theta = 30", #"\hat{u} = cos(theta)i + sin(theta)j"#, "û"),
                     expected, tolerance: 1e-12)
        // The exact line from user feedback, spaces and all:
        let outcomes = Engine.evaluate(["theta = 30", #"\hat(u)= cos(theta)i + sin(theta)j"#, "|û|"])
        #expect(outcomes.allSatisfy { $0.errorMessage == nil })
    }

    @Test func implicitMultiplyAfterCloseParen() throws {
        expectApprox(try vector("theta = 30", "F = cos(theta)i + sin(theta)j"),
                     Vec3(3.0.squareRoot() / 2, 0.5, 0), tolerance: 1e-12)
        expectApprox(try scalar("(2)(3)"), 6)
        expectApprox(try scalar("mag(<3, 4, 0>)(2)"), 10)
    }

    @Test func strictNotationRequiresVectorMark() {
        // Plain names may not hold vectors — the decoration teaches notation.
        #expect(Engine.evaluate(["P = <1, 2, 3>"])[0].errorMessage?.contains("\\vec") == true)
        #expect(Engine.evaluate(["vec P = <1, 2, 3>"])[0].errorMessage == nil)
        #expect(Engine.evaluate([#"\vec P = <1, 2, 3>"#])[0].errorMessage == nil)
        #expect(Engine.evaluate(["P\u{20D7} = <1, 2, 3>"])[0].errorMessage == nil)   // typed arrow
        #expect(Engine.evaluate(["m = 5"])[0].errorMessage == nil)                   // scalars plain
        #expect(Engine.evaluate(["point A = (1, 2, 3)"])[0].errorMessage == nil)
        #expect(Engine.evaluate([#"\vec x = 5"#])[0].errorMessage != nil)            // marked but scalar
        #expect(Engine.evaluate(["P = <1, 2, 3>"], strictNotation: false)[0].errorMessage == nil)
    }

    @Test func strictHatRequiresUnitMagnitude() {
        // The exact case from user feedback: |<0.5, 0.5>| ≠ 1 must be rejected.
        #expect(Engine.evaluate([#"\hat u = <0.5, 0.5>"#])[0].errorMessage?.contains("unit vector") == true)
        #expect(Engine.evaluate([#"\hat u = unit(<0.5, 0.5>)"#])[0].errorMessage == nil)
        #expect(Engine.evaluate([#"\hat u = i"#])[0].errorMessage == nil)
        #expect(Engine.evaluate([#"\hat u = 5"#])[0].errorMessage != nil)
    }

    /// Enter-to-render commits the pretty text as the real source, so every
    /// pretty form must evaluate identically to what the user typed.
    @Test func mathPrintRoundTripsThroughParser() {
        let corpus = [
            #"\vec a = <1, 2, 3>"#,
            #"\vec F = 260 * unit(<1, 2, 2>)"#,
            #"\vec T = 50 @ 30"#,
            #"\vec G = 3i + 4j - 5k"#,
            #"\hat u = unit(<3, 4, 0>)"#,
            "m = sqrt(16) + 2 pi",
            "d = <1, 2, 3> * <4, -5, 6>",
            #"\vec c = cross(i, j) × k"#,
            "theta = 30",
            "point A = (1, 2, 3)",
        ]
        let raw = Engine.evaluate(corpus)
        let pretty = Engine.evaluate(corpus.map(MathPrint.pretty))
        for (r, p) in zip(raw, pretty) {
            #expect(r.errorMessage == nil)
            #expect(r.resultText == p.resultText)
            #expect(r.drawable == p.drawable)
        }
    }

    @Test func mathPrintIsIdempotent() {
        for line in ["a = <1, 2, 3>", #"\hat u = 2 * unit(F) @ 30"#, "sqrt(2) pi"] {
            let once = MathPrint.pretty(line)
            #expect(MathPrint.pretty(once) == once)
        }
    }

    @Test func combiningArrowIsCosmetic() throws {
        // F⃗ (F + U+20D7) is the same variable as F, matching \vec F.
        expectApprox(try scalar("F\u{20D7} = <7, 0, 0>", "F.x"), 7)
        expectApprox(try scalar("F = <7, 0, 0>", "F\u{20D7}.x"), 7)
    }

    @Test func centerDotScalesLikeMultiply() throws {
        expectApprox(try vector("2 · <1, 2, 3>"), Vec3(2, 4, 6))
        expectApprox(try vector("<1, 2, 3> · 2"), Vec3(2, 4, 6))
        expectApprox(try vector("F = 260 · unit(<3, 4, 12>)"), Vec3(60, 80, 240), tolerance: 1e-9)
        expectApprox(try scalar("√(9)"), 3)
    }

    @Test func greekLetterCommands() throws {
        expectApprox(try scalar(#"\theta = 30"#, "θ"), 30)
        expectApprox(try scalar(#"\theta = 30"#, #"sin(\theta)"#), 0.5, tolerance: 1e-12)
        expectApprox(try scalar(#"\Omega = 5"#, "Ω"), 5)
        expectApprox(try scalar(#"2\pi"#), 2 * Double.pi, tolerance: 1e-12)
        expectApprox(try vector("λ = 4", #"\vec F = \lambda * i"#, "F"), Vec3(4, 0, 0))
    }

    @Test func mathPrintGreek() {
        #expect(MathPrint.pretty(#"\theta = 30"#) == "θ = 30")
        #expect(MathPrint.pretty(#"\alpha + \beta"#) == "α + β")
        #expect(MathPrint.pretty(#"\foo x"#) == #"\foo x"#)   // unknown commands untouched
    }

    @Test func mathPrintPretty() {
        #expect(MathPrint.pretty(#"\hat u = unit(F)"#) == "û = unit(F)")
        #expect(MathPrint.pretty(#"\hat(u) = 2"#) == "û = 2")
        #expect(MathPrint.pretty(#"\vec F = 3i + 4j"#).hasPrefix("F\u{20D7}"))
        #expect(MathPrint.pretty("a = <1, 2, 3>") == "a = ⟨1, 2, 3⟩")
        #expect(MathPrint.pretty("a * b") == "a · b")
        #expect(MathPrint.pretty("2 pi") == "2 π")
        #expect(MathPrint.pretty("point A = (0, 0, 0)") == "point A = (0, 0, 0)")
    }

    @Test func latexAngleBrackets() throws {
        expectApprox(try vector(#"a = \langle 1, 2, 3 \rangle"#, "a"), Vec3(1, 2, 3))
        expectApprox(try vector("b = ⟨4, 5, 6⟩", "b"), Vec3(4, 5, 6))
    }

    @Test func parenTupleIsAPointBracketsAreVector() throws {
        let v = try lastValue("A = (1, 2, 3)")
        guard case .point(let p) = v else {
            Issue.record("(…) should make a point, got \(v)")
            return
        }
        expectApprox(p, Vec3(1, 2, 3))
        expectApprox(try vector("b = [1, 2, 3]", "b"), Vec3(1, 2, 3))

        // From user feedback: a plain-named paren tuple is a point — legal
        // under strict notation with no \vec mark.
        let outcomes = Engine.evaluate(["θ = 30", "M = (cos(θ), sin(θ))"])
        #expect(outcomes.allSatisfy { $0.errorMessage == nil })
        // And parens can never satisfy a \vec mark.
        #expect(Engine.evaluate([#"\vec a = (1, 2, 3)"#])[0].errorMessage != nil)
    }

    @Test func twoDVectorsGetZeroZ() throws {
        expectApprox(try vector("a = <3, 4>", "a"), Vec3(3, 4, 0))
        expectApprox(try scalar("|<3, 4>|"), 5)
    }

    @Test func componentIJKForm() throws {
        expectApprox(try vector("F = 3i + 4j - 5k"), Vec3(3, 4, -5))
        expectApprox(try vector("G = 2i - j"), Vec3(2, -1, 0))
        expectApprox(try vector("H = -k"), Vec3(0, 0, -1))
    }

    @Test func polarForm() throws {
        expectApprox(try vector("T = 10∠60"), Vec3(5, 5 * 3.0.squareRoot(), 0), tolerance: 1e-9)
        expectApprox(try vector("T = 10 @ 60"), Vec3(5, 5 * 3.0.squareRoot(), 0), tolerance: 1e-9)
        expectApprox(try vector("T = 5∠36.8698976458°"), Vec3(4, 3, 0), tolerance: 1e-9)
    }

    @Test func latexOperators() throws {
        expectApprox(try scalar(#"<1,2,3> \cdot <4,-5,6>"#), 12)
        expectApprox(try vector(#"<1,0,0> \times <0,1,0>"#), Vec3(0, 0, 1))
        expectApprox(try scalar("<1,2,3> · <4,-5,6>"), 12)
        expectApprox(try vector("<1,2,3> × <4,5,6>"), Vec3(-3, 6, -3))
    }

    @Test func pointDefinition() throws {
        let v = try lastValue("point A = (1, 2, 3)", "A")
        guard case .point(let p) = v else {
            Issue.record("expected point, got \(v)")
            return
        }
        expectApprox(p, Vec3(1, 2, 3))
    }

    @Test func autoPositionVector() throws {
        let v = try lastValue("point A = (0, 0, 4)", "point B = (2, 3, 0)", "r_AB")
        guard case .vector(let vec, let anchor) = v else {
            Issue.record("expected vector")
            return
        }
        expectApprox(vec, Vec3(2, 3, -4))
        #expect(anchor == Vec3(0, 0, 4))   // drawn from A
    }

    @Test func autoPositionVectorNeedsPoints() {
        #expect(throws: EvalError.self) {
            _ = try lastValue("r_AB")
        }
    }

    @Test func ambiguousAutoPositionVector() throws {
        #expect(throws: EvalError.self) {
            _ = try lastValue(
                "point A = (0,0,0)", "point BC = (1,1,1)",
                "point AB = (2,2,2)", "point C = (3,3,3)",
                "r_ABC")
        }
    }

    @Test func implicitMultiplication() throws {
        expectApprox(try scalar("2(3 + 1)"), 8)
        expectApprox(try scalar("x = 5", "2x"), 10)
        expectApprox(try vector("2<1, 2, 3>"), Vec3(2, 4, 6))
    }

    @Test func precedence() throws {
        expectApprox(try scalar("2 + 3 * 4"), 14)
        expectApprox(try scalar("2^3^2"), 512)      // right-assoc
        expectApprox(try scalar("-3^2"), -9)        // unary minus binds looser than ^
        expectApprox(try scalar("2^-1"), 0.5)
    }

    @Test func degreeSignIsCosmetic() throws {
        expectApprox(try scalar("theta = 30°", "theta"), 30)
        expectApprox(try scalar("cos(60°)"), 0.5, tolerance: 1e-12)
    }

    @Test func memberAccess() throws {
        expectApprox(try scalar("F = <80, -60, -240>", "F.x"), 80)
        expectApprox(try scalar("F = <80, -60, -240>", "F.z"), -240)
        expectApprox(try scalar("point A = (1, 2, 3)", "A.y"), 2)
    }

    @Test func commentsAndBlanks() throws {
        let outcomes = Engine.evaluate(["# hello", "", "vec a = <1,1,1>"])
        #expect(outcomes[0].status == .comment)
        #expect(outcomes[1].status == .blank)
        #expect(outcomes[2].status == .ok)
    }

    @Test func errorsDoNotStopEvaluation() throws {
        let outcomes = Engine.evaluate(["vec a = <1,2,3>", "garbage )( here", "a * a"])
        #expect(outcomes[1].errorMessage != nil)
        #expect(outcomes[2].status == .ok)
        #expect(outcomes[2].resultText == "14")
    }

    @Test func reservedNamesRejected() {
        for line in ["i = <1,1,1>", "pi = 3", "k = 2j"] {
            #expect(throws: EvalError.self) { _ = try lastValue(line) }
        }
    }

    @Test func redefinitionAllowed() throws {
        expectApprox(try scalar("a = 1", "a = 2", "a"), 2)
    }

    @Test func malformedNumbersError() {
        // Review finding: these used to silently lex as 0 with status ok.
        let outcomes = Engine.evaluate(["1.2.3", "a = 1..5", "3²", "x = ½"])
        #expect(outcomes.allSatisfy { $0.errorMessage != nil })
    }

    @Test func missingCommaOrOperatorErrors() {
        // Review finding: number-number adjacency used to silently multiply.
        let outcomes = Engine.evaluate(["<1 2, 3>", "100 200", "F = 2 3i"])
        #expect(outcomes.allSatisfy { $0.errorMessage != nil })
    }

    @Test func polarAngleImplicitFactor() throws {
        // Review finding: 10∠2theta used to parse as (10∠2)*theta.
        expectApprox(try vector("theta = 30", "T = 10∠2theta"),
                     Vec3(5, 5 * 3.0.squareRoot(), 0), tolerance: 1e-9)
    }

    @Test func nonFiniteValuesAreNotDrawable() {
        let outcomes = Engine.evaluate(["<1e308, 0, 0> * 10"])
        #expect(outcomes[0].errorMessage == nil)
        #expect(outcomes[0].drawable == nil)
    }

    @Test func hugeFiniteNumbersFormatWithoutInf() throws {
        let s = Fmt.num(1e305)
        #expect(!s.contains("inf"))
        #expect(s.first?.isNumber == true && s.count > 300)   // full digit string
        expectApprox(try scalar("10^305"), 1e305, tolerance: 1e290)
    }

    @Test func junkNeverCrashes() {
        let junk = ["<<<", "|||", "a ==== b", "\\frac{1}{2}", ")(", "1 +", "<1,2,3,4>",
                    "point = 3", "@@", "^", "...", "a.w", "5∠", "|1", "(1,2,3,4,5)"]
        let outcomes = Engine.evaluate(junk)
        #expect(outcomes.allSatisfy { $0.errorMessage != nil })
    }
}
