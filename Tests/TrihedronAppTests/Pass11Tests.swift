import Foundation
import Testing
import TrihedronCore
@testable import Trihedron

/// Pass 11. Takes the lead passes 8, 9 and 10 all left open: `liveRender` and
/// `renderOrSubmit` were never tested *as the app runs them*, only as models of
/// the string functions they call. Testing the real decision found a bug that
/// no test of `pretty` or `applyScripts` alone could see — it lives in the glue.
@MainActor
@Suite struct Pass11Tests {

    // MARK: - The typing model, running the SHIPPED decision functions

    /// Types `target` one character at a time exactly as `RichEntryField`
    /// does: `spaceCompletion` on a space, `applyScripts` otherwise.
    /// This calls the app's own code, not a copy of it.
    static func typeOut(_ target: String) -> String {
        var text = ""
        for c in target {
            let new = text + String(c)
            let trimmed = new.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { text = new; continue }
            if new.hasSuffix(" ") {
                text = RichEntryField.spaceCompletion(new) ?? new
            } else {
                text = MathPrint.applyScripts(new)
            }
        }
        return text
    }

    /// Returns after the line settles, as `renderOrSubmit` does.
    static func commit(_ s: String) -> String {
        var t = s
        for _ in 0..<8 {
            let p = MathPrint.pretty(t)
            if p == t { return t }
            t = p
        }
        return t
    }

    static func typeAndCommit(_ s: String) -> String { commit(typeOut(s)) }

    // MARK: - Bug: a space is swallowed by a rewrite it did not cause

    /// `spaceCompletion` swallows the typed space whenever `pretty(body)`
    /// differs from `body` — but that is only correct when the difference IS
    /// the trailing `\command` being completed. Any unrelated rewrite earlier
    /// on the line (`*`→`·`, `pi`→`π`, `@`→`∠`) also eats the space, and the
    /// next keystroke then glues onto the still-incomplete command.
    @Test func aSpaceIsKeptWhenItDidNotCompleteTheCommand() {
        // Each: (typed so far incl. the space, what must survive)
        let cases = [
            ("3*\\hat ",        "\\hat "),   // 3·\hat  — * rewrote, \hat did not complete
            ("pi\\hat ",        "\\hat "),
            ("50@30 \\vec ",    "\\vec "),
            ("a*b\\vec ",       "\\vec "),
        ]
        for (typed, mustEndWith) in cases {
            let out = RichEntryField.spaceCompletion(typed) ?? typed
            #expect(out.hasSuffix(mustEndWith),
                    "spaceCompletion(\(typed.debugDescription)) = \(out.debugDescription) ate the space")
        }
    }

    /// The end-to-end shape of it, on an ordinary statics line: three times a
    /// unit vector. Typed left to right, the line stops parsing.
    @Test func anOrdinaryLineSurvivesBeingTyped() {
        let lines = [
            "\\vec F = 3*\\hat u",
            "\\vec F = 2*pi*\\hat u",
            "T = 50@30 + \\hat u",
        ]
        for line in lines {
            let typed = Self.typeAndCommit(line)
            #expect(!typed.contains("\\hatu") && !typed.contains("\\vecu"),
                    "typing \(line.debugDescription) produced \(typed.debugDescription)")
            let out = Engine.evaluate([typed])[0]
            let pasted = Engine.evaluate([Self.commit(line)])[0]
            #expect(out.errorMessage == pasted.errorMessage,
                    Comment(rawValue: "typed \(typed.debugDescription) -> \(out.errorMessage ?? "ok"); "
                        + "pasted -> \(pasted.errorMessage ?? "ok")"))
        }
    }

    /// The property behind both: typing a line character by character must
    /// reach the same ANSWER as pasting it whole. Spelling may differ (the
    /// incremental renderer is allowed to get somewhere sooner); the answer
    /// may not. Deterministic LCG, so a failure is reproducible. 6000 lines here;
    /// the same property was swept over 40,000 out-of-suite (see NIGHT-NOTES pass 11).
    @Test func typingALineAgreesWithPastingIt() {
        struct LCG {
            var s: UInt64
            mutating func next() -> UInt64 {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return s >> 11
            }
            mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        }
        let alphabet = ["a", "b", "F", "r", "u", "x", "pi", "e", "2", "3", "10", "0.5",
                        "_1", "_2", "_AB", "^2", "^3", "^-1", "^0.5", "+", "-", "*", "/",
                        "(", ")", "<", ">", ",", "=", " ", ".", "|", "@",
                        "\\vec ", "\\hat ", "unit", "mag", "dot", "cross", "angle", "sin", "cos"]
        var rng = LCG(s: 0x11A55)
        var diverged: [String] = []
        var knownHatPlacement = 0
        for _ in 0..<6000 {
            let n = 1 + rng.int(6)
            var line = ""
            for _ in 0..<n { line += alphabet[rng.int(alphabet.count)] }
            let typed = Self.typeAndCommit(line)
            let pasted = Self.commit(line)
            if typed == pasted { continue }
            let a = Engine.evaluate([typed])[0]
            let b = Engine.evaluate([pasted])[0]
            if a.resultText == b.resultText && a.errorMessage == b.errorMessage { continue }
            // KNOWN, NOT FIXED (pass 11 lead): `\hat` on a MULTI-LETTER name has
            // no agreed placement. `MathPrint.pretty` puts the combining hat on
            // the last character of the name; `Parser.foldHats` puts it on the
            // first ("\hat u_1 is u\u{0302}_1, not u_1\u{0302}"). When `applyScripts` has already
            // turned `_2` into a subscript glyph, the two disagree about where
            // the name even ENDS, so typed and pasted hat different letters:
            //   \vec \hat mag_2rmag  ->  typed \vec mag\u{0302}\u{2082}rmag, pasted \vec mag\u{2082}rmag\u{0302}
            // Both are "not defined" errors on a name nobody would write; the
            // fix is a placement decision, not a bug fix. Bucketed, not hidden:
            // the count is pinned below so it cannot quietly grow.
            if line.contains("\\hat") && line.contains("_") {
                knownHatPlacement += 1
                continue
            }
            if diverged.count < 6 {
                diverged.append("\(line.debugDescription): typed \(typed.debugDescription) -> "
                    + "\(a.errorMessage ?? a.resultText) | pasted \(pasted.debugDescription) -> "
                    + "\(b.errorMessage ?? b.resultText)")
            }
        }
        #expect(diverged.isEmpty,
                Comment(rawValue: "typing diverges from pasting:\n" + diverged.joined(separator: "\n")))
        #expect(knownHatPlacement == 1,
                Comment(rawValue: "known hat-placement divergences: \(knownHatPlacement), pinned at 1"))
    }

    // MARK: - Bug 2: the hat lands on a superscript digit

    /// `pretty`'s \hat rules capture the name as `[\p{L}_][\p{L}\p{N}_]*`.
    /// `\p{N}` is every Unicode number, which includes the superscript and
    /// subscript glyphs `applyScripts` makes — so `\hat u` followed by `^2`
    /// hats the EXPONENT: a combining circumflex on a superscript two. That is
    /// not a character the lexer will take, and the line dies on "unexpected
    /// character". Same root cause as pass 10's `pi` bug: a Unicode-general
    /// character class where the lexer uses an ASCII one.
    @Test func theHatGoesOnTheNameNotItsExponent() {
        let cases = [
            ("\\hat u\u{00B2}",             "\u{00FB}\u{00B2}"),
            ("\\hat u\u{2081}",             "\u{00FB}\u{2081}"),
            ("\\hat unit\u{00B3}F",         "unit\u{0302}\u{00B3}F"),
            ("\\hat F\u{2081}\u{2080}",     "F\u{0302}\u{2081}\u{2080}"),
        ]
        for (input, expected) in cases {
            let out = MathPrint.pretty(input).precomposedStringWithCanonicalMapping
            #expect(out == expected.precomposedStringWithCanonicalMapping,
                    Comment(rawValue: "pretty(\(input.debugDescription)) = \(out.debugDescription), "
                        + "want \(expected.debugDescription)"))
        }
    }

    /// The consequence: the line stops lexing at all. This asserts only that
    /// it LEXES — what `u\u{0302}^2` then means is the evaluator's business.
    @Test func aHattedNameWithAnExponentStillLexes() {
        let out = Engine.evaluate(["\\hat u = <1,0,0>", MathPrint.pretty("\\hat u\u{00B2}")])
        #expect(out[1].errorMessage?.contains("unexpected character") != true,
                Comment(rawValue: "second line: \(out[1].errorMessage ?? out[1].resultText)"))
    }

    // MARK: - Pins (must pass BEFORE the fix as well as after)

    /// The behaviour the space rule exists for: a completed \command eats the
    /// space that completed it. This is what must NOT regress.
    @Test func aCompletedCommandStillSwallowsItsSpace() {
        let cases = [
            ("\\hat u ",   "û"),
            ("\\theta ",   "θ"),
            ("\\hat(a) ",  "â"),
            ("x + \\hat u ", "x + û"),
        ]
        for (typed, expected) in cases {
            let out = RichEntryField.spaceCompletion(typed) ?? typed
            #expect(out == expected,
                    "spaceCompletion(\(typed.debugDescription)) = \(out.debugDescription), want \(expected.debugDescription)")
        }
    }

    /// A space with no trailing \command is never touched at all.
    @Test func anOrdinarySpaceIsNeverRewritten() {
        for typed in ["2*3 ", "a + b ", "\\vec F = <1,2,3> ", "pi ", ""] {
            #expect(RichEntryField.spaceCompletion(typed) == nil,
                    "spaceCompletion(\(typed.debugDescription)) should be nil")
        }
    }

    /// Pass 10's fixed point still holds, and comments are still left alone.
    @Test func pass10PinsStillHold() {
        #expect(MathPrint.pretty("pi*r^2") == "π·r²")
        for line in ["x^2pi", "2^2pi", "r_1pi", "pi_0pi"] {
            let once = MathPrint.pretty(line)
            #expect(MathPrint.pretty(once) == once)
        }
    }
}
