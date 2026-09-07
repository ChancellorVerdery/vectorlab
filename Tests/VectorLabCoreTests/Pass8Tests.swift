import Foundation
import Testing
@testable import VectorLabCore

/// Pass 8. Two bugs on the notation surface — the layer that rewrites what the
/// user typed — plus regression pins for the spellings that already worked.
///
/// The theme: `MathPrint` is documented as "display-only … never fed back into
/// the parser", but `RichEntryField` writes `applyScripts` back into the text
/// binding on every keystroke and `pretty` back on space and Return. The raw
/// string IS the rewriter's output, so a rewrite that changes what a line means
/// is a wrong answer the user never typed.
@Suite struct Pass8Tests {

    private func result(_ line: String) -> LineOutcome {
        Engine.evaluate([line], strictNotation: false)[0]
    }

    /// What the entry field actually ends up holding: applyScripts runs after
    /// every single keystroke, so the fixed point of typing is what gets parsed.
    private func typed(_ line: String) -> String {
        var s = ""
        for ch in line {
            s.append(ch)
            s = MathPrint.applyScripts(s)
        }
        return s
    }

    // MARK: - Bug 1 — a fractional exponent was superscripted into a syntax error

    /// `2^3.5` becomes `2³.5` the moment the 3 is typed, and `2³.5` lexes as
    /// `2 ^ 3` followed by a stray `.5`. The user's own line stops parsing.
    @Test func fractionalExponentsSurviveTheNotationRewriter() {
        for line in ["2^0.5", "2^3.5", "2^-1.5", "5^1.5", "10^-0.5", "9^0.5"] {
            let want = result(line)
            #expect(want.errorMessage == nil, "\(line) should evaluate before any rewriting")
            for (label, rewritten) in [("applyScripts", MathPrint.applyScripts(line)),
                                       ("pretty", MathPrint.pretty(line)),
                                       ("typed", typed(line))] {
                let got = result(rewritten)
                #expect(got.errorMessage == nil,
                        "\(label)(\(line)) = \(rewritten) — \(got.errorMessage ?? "")")
                #expect(got.resultText == want.resultText,
                        "\(label)(\(line)) = \(rewritten)")
            }
        }
    }

    /// The values themselves, so the fix has to preserve the arithmetic and not
    /// merely stop erroring.
    @Test func fractionalPowersPrintTheRightNumber() {
        #expect(result(typed("2^0.5")).resultText == "1.4142")
        #expect(result(typed("2^3.5")).resultText == "11.3137")
        #expect(result(typed("2^-1.5")).resultText == "0.3536")
        #expect(result(typed("9^0.5")).resultText == "3")
    }

    /// PIN (passes pre-fix): whole and negative-whole exponents must still
    /// typeset. The fix must not buy correctness by disabling superscripts.
    @Test func wholeExponentsStillBecomeSuperscripts() {
        #expect(MathPrint.applyScripts("2^3") == "2³")
        #expect(MathPrint.applyScripts("2^-3") == "2⁻³")
        #expect(MathPrint.applyScripts("2^10") == "2¹⁰")
        #expect(MathPrint.applyScripts("x^2") == "x²")
        #expect(MathPrint.applyScripts("mag(a)^2") == "mag(a)²")
        // A second ^ after a superscript run is left alone: never 2³².
        #expect(MathPrint.applyScripts("2^3^2") == "2³^2")
        #expect(typed("2^3") == "2³")
        #expect(typed("2^-3") == "2⁻³")
        #expect(result("2³").resultText == "8")
        #expect(result("2⁻³").resultText == "0.125")
    }

    /// PIN (passes pre-fix): subscripts are a separate rule and must not move.
    @Test func subscriptsAreUnaffected() {
        #expect(MathPrint.applyScripts("F_1") == "F₁")
        #expect(MathPrint.applyScripts("x_12") == "x₁₂")
        #expect(MathPrint.applyScripts("r_AB") == "r_AB")
        #expect(typed("F_1") == "F₁")
    }

    // MARK: - Bug 2 — \vec{F} = … and \vec(F) = … did not parse at all

    /// `\hat` has accepted `\hat u`, `\hat(u)` and `\hat{u}` since foldHats was
    /// written, the lexer maps `{}` to parens precisely so "LaTeX braces act as
    /// parens", and MathPrint has a rule whose only job is rewriting
    /// `\vec{F}` — but the parser only ever handled the bare `\vec F`. The
    /// wrapped forms parsed the name as a parenthesised expression, which left
    /// the `=` as trailing input: "unexpected trailing input near 'equals'".
    @Test func wrappedVecDefinitionsParse() {
        for line in ["\\vec F = <1,2,3>", "\\vec(F) = <1,2,3>", "\\vec{F} = <1,2,3>",
                     "\\vector{F} = <1,2,3>", "\\overrightarrow{F} = <1,2,3>"] {
            let got = result(line)
            #expect(got.errorMessage == nil, "\(line) — \(got.errorMessage ?? "")")
            #expect(got.resultText == "<1, 2, 3>   |v| = 3.7417", "\(line)")
        }
    }

    /// The wrapped form must carry the \vec MARK too, not just parse — that is
    /// the whole reason to type it.
    @Test func wrappedVecStillCountsAsAVectorMark() {
        let strict = { (line: String) in Engine.evaluate([line], strictNotation: true)[0] }
        for line in ["\\vec F = 5", "\\vec(F) = 5", "\\vec{F} = 5"] {
            #expect(strict(line).errorMessage?.contains("must be a vector") == true,
                    "\(line) — \(strict(line).errorMessage ?? "no error")")
        }
        // And a wrapped vec definition of a real vector is accepted in strict mode.
        #expect(strict("\\vec{F} = <1,2,3>").errorMessage == nil)
    }

    /// The name survives, so downstream lines can use it.
    @Test func aWrappedVecDefinitionActuallyBindsTheName() {
        let out = Engine.evaluate(["\\vec{F} = <3,4,0>", "mag(F)"], strictNotation: false)
        #expect(out[0].errorMessage == nil)
        #expect(out[1].resultText == "5")
    }

    /// PIN (passes pre-fix): \hat already accepted all three spellings, and the
    /// fix must not disturb it — it is the model the \vec fix copies.
    @Test func hatAlreadyAcceptsAllThreeSpellings() {
        for line in ["\\hat u = unit(<1,2,3>)", "\\hat(u) = unit(<1,2,3>)",
                     "\\hat{u} = unit(<1,2,3>)"] {
            let got = Engine.evaluate([line], strictNotation: true)[0]
            #expect(got.errorMessage == nil, "\(line) — \(got.errorMessage ?? "")")
        }
    }

    /// PIN (passes pre-fix): parentheses must keep meaning grouping and points
    /// everywhere else. The fix looks at exactly one token shape.
    @Test func parenthesesKeepTheirOrdinaryMeanings() {
        #expect(result("(1 + 2) * 3").resultText == "9")
        #expect(result("(1, 2, 3)").resultText == "(1, 2, 3)")
        #expect(result("point P = (1, 2, 3)").resultText == "(1, 2, 3)")
        // A bare \vec in front of a parenthesised expression stays cosmetic.
        #expect(result("\\vec (1 + 2)").resultText == "3")
        #expect(result("\\vec(<1,2,3>)").resultText == "<1, 2, 3>   |v| = 3.7417")
        // (F) with no \vec is still a grouped expression, not a definition.
        #expect(Engine.evaluate(["(F) = <1,2,3>"], strictNotation: false)[0].errorMessage != nil)
    }

    // MARK: - Bug 3 — the negative-base message models notation the tool rejects
    //          (pass-7 lead, recorded there and left open)

    /// `(-8)^(1/3)` complained about `-8^0.3333`, which re-parses as
    /// `-(8^0.3333)` — a perfectly valid expression, and not the one being
    /// refused. An error message in a teaching tool has to be re-typable.
    @Test func theNegativeBaseMessageKeepsItsParentheses() {
        let msg = result("(-8)^(1/3)").errorMessage ?? ""
        #expect(msg.contains("(-8)^0.3333"), "\(msg)")
        #expect(!msg.contains(" -8^"), "\(msg)")
        // The message's own expression must round-trip: re-evaluating the
        // notation it prints has to hit the SAME complaint, not succeed.
        #expect(result("(-8)^0.3333").errorMessage?.contains("negative base") == true)
    }

    // MARK: - Bug 4 — parse errors named tokens by their Swift case name

    /// "unexpected trailing input near 'equals'" and "unexpected 'rangle'" are
    /// the internal enum spellings leaking into the notebook. The user typed
    /// `=` and `>`; those are what the message has to say.
    @Test func parseErrorsNameTokensTheWayTheUserTypedThem() {
        for (line, symbol, forbidden) in [
            ("<1,2,3>>", ">", "rangle"),
            ("(1+2))", ")", "rparen"),
            ("1 + 2 =", "=", "equals"),
            ("1 + 2 ]", "]", "rbracket"),
        ] {
            let msg = result(line).errorMessage ?? ""
            #expect(msg.contains("'\(symbol)'"), "\(line) — \(msg)")
            #expect(!msg.contains(forbidden), "\(line) — \(msg)")
        }
    }

    /// PIN (passes pre-fix): the messages that already named things properly.
    @Test func errorMessagesThatWereAlreadyRightAreUnchanged() {
        #expect(result("<1,2>").errorMessage == nil)
        #expect(result("<1>").errorMessage == "vectors need 2 or 3 components")
        #expect(result("1 +").errorMessage == "unexpected end of input")
        #expect(result("<1,2,3").errorMessage == "expected '>'")
        #expect(result("100 200").errorMessage?.contains("'200'") == true)
        #expect(result("1 + foo").errorMessage == "'foo' is not defined")
    }
}
