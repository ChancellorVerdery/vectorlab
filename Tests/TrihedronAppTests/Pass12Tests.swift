import Foundation
import Testing
import TrihedronCore
@testable import Trihedron

/// Pass 12. Takes pass 11's handoff: "`liveRender` itself is still untested —
/// the two guards and the round trip. Middle-of-line editing is the specific
/// unknown."
///
/// `keystrokeRewrite` (extracted this pass) is the whole decision including
/// the guards, so the guards can finally be asserted rather than read. The
/// guards skip every edit that is not an append, which means a middle-of-line
/// edit leaves the line PARTLY RENDERED and PARTLY RAW — glyphs where the
/// user typed at the end, backslash notation where they went back and edited.
///
/// That mixed string is an input distribution no pass has ever fuzzed. Passes
/// 10 and 11 fuzzed raw notation lines and append-typed lines; both are
/// homogeneous. `pretty` and `applyScripts` are the functions that then have
/// to swallow the mixture, on the Return that commits the line.
@MainActor
@Suite struct Pass12Tests {

    // MARK: - The typing model, now running the SHIPPED guards too

    /// Types `target` one character at a time through `keystrokeRewrite` —
    /// the real decision, guards included. Pass 11's model called
    /// `spaceCompletion`/`applyScripts` directly and so could not see them.
    static func typeOut(_ target: String) -> String {
        var text = ""
        for c in target {
            let new = text + String(c)
            text = RichEntryField.keystrokeRewrite(old: text, new: new) ?? new
        }
        return text
    }

    /// `renderOrSubmit`: Return re-renders until the line is a fixed point of
    /// `pretty`, and only THEN commits. Returns nil if it never settles —
    /// which for the user means Return does nothing, forever.
    static func commit(_ s: String, limit: Int = 8) -> String? {
        var t = s
        for _ in 0..<limit {
            let p = MathPrint.pretty(t)
            if p == t { return t }
            t = p
        }
        return nil
    }

    /// A line the user typed the front of, then went back and edited: the
    /// prefix is live-rendered, the suffix is still raw notation.
    static func mixed(_ line: String, splitAt k: Int) -> String {
        let chars = Array(line)
        let k = max(0, min(k, chars.count))
        return typeOut(String(chars[0..<k])) + String(chars[k...])
    }

    // MARK: - The guards, asserted rather than read (pass 8-11 handoff)

    /// Only an append at the very end renders. Everything else is left to
    /// Return. Four passes have described this rule from the source; this
    /// runs it.
    @Test func onlyAnAppendAtTheEndIsEverRewritten() {
        // (old, new, must the text change?)
        let cases: [(String, String, Bool)] = [
            ("F", "F_1", false),          // two characters at once (a paste)
            ("F_", "F_1", true),          // the ordinary append: F_1 -> the glyph
            ("F_1", "F_", false),         // a delete
            ("_1", "F_1", false),         // inserted at the FRONT: not a prefix
            ("F1", "F_1", false),         // inserted in the MIDDLE: not a prefix
            ("F_1", "F_1", false),        // no change at all
        ]
        for (old, new, shouldRewrite) in cases {
            let out = RichEntryField.keystrokeRewrite(old: old, new: new)
            #expect((out != nil) == shouldRewrite,
                    Comment(rawValue: "keystrokeRewrite(old: \(old.debugDescription), "
                        + "new: \(new.debugDescription)) = \(String(describing: out)); "
                        + "expected \(shouldRewrite ? "a rewrite" : "nil")"))
        }
    }

    /// A comment is never rewritten, at either end of the line.
    @Test func commentsAreLeftAlone() {
        for (old, new) in [("# F_", "# F_1"), ("// x^", "// x^2"), ("  # \\theta", "  # \\theta ")] {
            #expect(RichEntryField.keystrokeRewrite(old: old, new: new) == nil,
                    "keystrokeRewrite rewrote the comment \(new.debugDescription)")
        }
    }

    /// The extraction moved no behaviour. Both stages are pinned, because
    /// they are different: live typing does NOT form the hat. `\hat` is only
    /// folded by `pretty`, and live typing reaches `pretty` only inside
    /// `spaceCompletion` — which, since pass 11, deliberately puts the space
    /// back when the command is still pending. So `3*\hat ` stays `3·\hat `
    /// on screen while the user types the name, and the hat forms on Return.
    /// Pass 11's recorded table is the COMMITTED column.
    @Test func pass11TypedOutputIsUnchanged() {
        // (line, on screen while typing, after Return)
        let cases = [
            ("\\vec F = 3*\\hat u",     "\\vec F = 3·\\hat u",    "\\vec F = 3·û"),
            ("\\vec F = 2*pi*\\hat u",  "\\vec F = 2·π·\\hat u",  "\\vec F = 2·π·û"),
            ("T = 50@30 + \\hat u",     "T = 50∠30 + \\hat u",    "T = 50∠30 + û"),
            // the space DID complete the command here, so it is swallowed live
            ("\\hat u = unit(<3,4,0>)", "û= unit(<3,4,0>)",       "û= unit(<3,4,0>)"),
            ("\\vec a = <1,2,3>",       "\\vec a = <1,2,3>",      "\\vec a = <1,2,3>"),
        ]
        for (line, typed, committed) in cases {
            let t = Self.typeOut(line).precomposedStringWithCanonicalMapping
            #expect(t == typed.precomposedStringWithCanonicalMapping,
                    Comment(rawValue: "typeOut(\(line.debugDescription)) = \(t.debugDescription), "
                        + "want \(typed.debugDescription)"))
            let c = (Self.commit(t) ?? t).precomposedStringWithCanonicalMapping
            #expect(c == committed.precomposedStringWithCanonicalMapping,
                    Comment(rawValue: "committed \(line.debugDescription) = \(c.debugDescription), "
                        + "want \(committed.debugDescription)"))
        }
    }

    // MARK: - Middle-of-line editing: the half-rendered line

    struct LCG {
        var s: UInt64
        mutating func next() -> UInt64 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return s >> 11
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    static let alphabet = ["a", "b", "F", "r", "u", "x", "pi", "e", "2", "3", "10", "0.5",
                           "_1", "_2", "_AB", "^2", "^3", "^-1", "^0.5", "+", "-", "*", "/",
                           "(", ")", "<", ">", ",", "=", " ", ".", "|", "@",
                           "\\vec ", "\\hat ", "unit", "mag", "dot", "cross", "angle", "sin", "cos"]

    static func fuzzLines(seed: UInt64, count: Int) -> [String] {
        var rng = LCG(s: seed)
        var out: [String] = []
        for _ in 0..<count {
            let n = 1 + rng.int(6)
            var line = ""
            for _ in 0..<n { line += alphabet[rng.int(alphabet.count)] }
            out.append(line)
        }
        return out
    }

    /// Every split point of every fuzz line, as the half-rendered string the
    /// editor would actually be holding.
    static func mixedCorpus(seed: UInt64, count: Int) -> [(line: String, k: Int, mixed: String)] {
        var out: [(String, Int, String)] = []
        for line in fuzzLines(seed: seed, count: count) {
            for k in Set([1, line.count / 2, max(0, line.count - 1)]).sorted() {
                out.append((line, k, mixed(line, splitAt: k)))
            }
        }
        return out
    }

    /// A half-rendered line must still COMMIT. `renderOrSubmit` only calls
    /// `onCommit` when `pretty(text) == text`; until then every Return just
    /// re-renders. If `pretty` had no fixed point on a mixed line, Return
    /// would do nothing and the user could not enter their line at all —
    /// there is no other way to commit. Pass 10 pinned this for raw lines
    /// only; a mixed line is a different input distribution.
    @Test func aHalfRenderedLineStillReachesAFixedPoint() {
        var stuck: [String] = []
        for c in Self.mixedCorpus(seed: 0xC0FFEE, count: 4000) where Self.commit(c.mixed) == nil {
            if stuck.count < 6 { stuck.append("split \(c.k) of \(c.line.debugDescription) -> \(c.mixed.debugDescription)") }
        }
        #expect(stuck.isEmpty,
                Comment(rawValue: "pretty never settles, so Return can never commit:\n"
                    + stuck.joined(separator: "\n")))
    }

    /// The property that matters: if the pasted line COMPUTES SOMETHING, then
    /// editing its middle must not change what it computes. Spelling may
    /// differ — the renderer is allowed to have got part of the way already —
    /// and an error may be respelled (bucketed separately below). A working
    /// answer may not move at all.
    @Test func editingTheMiddleNeverChangesAWorkingAnswer() {
        var diverged: [String] = []
        for c in Self.mixedCorpus(seed: 0x5EED12, count: 4000) {
            guard let pasted = Self.commit(c.line) else { continue }
            let b = Engine.evaluate([pasted])[0]
            guard b.errorMessage == nil else { continue }   // errors: see the bucket below
            guard let edited = Self.commit(c.mixed), edited != pasted else { continue }
            let a = Engine.evaluate([edited])[0]
            if a.errorMessage == nil && a.resultText == b.resultText { continue }
            if diverged.count < 8 {
                diverged.append("split \(c.k) of \(c.line.debugDescription): edited "
                    + "\(edited.debugDescription) -> \(a.errorMessage ?? a.resultText) | pasted "
                    + "\(pasted.debugDescription) -> \(b.resultText)")
            }
        }
        #expect(diverged.isEmpty,
                Comment(rawValue: "editing the middle changed a working answer:\n"
                    + diverged.joined(separator: "\n")))
    }

    /// The other half, bucketed and count-pinned rather than hidden: editing
    /// the middle can respell an ERROR. Both members of this bucket are the
    /// same shape —
    ///
    ///     pi\hat unit   pasted -> "piunit̂"  ('piuni' is not defined)
    ///                   edited -> "πunit̂"   ('πuni'  is not defined)
    ///
    /// — and the cause is rule ORDER inside `pretty`. The `\hat` rule runs
    /// first and DELETES the `\hat ` including its space, welding `pi` onto
    /// the name that followed it; the `pi` rule then correctly declines,
    /// because `pi` is now mid-name. Live typing reaches the `pi` rule
    /// earlier — at the space keystroke, while `\hat` is still pending — so
    /// it converts before the weld happens.
    ///
    /// Left alone deliberately. Both spellings are "not defined" errors on a
    /// name nobody would write (`pi\hat unit` has no operator between `pi`
    /// and the hat), no working line is affected — that is the test above,
    /// and it is clean — and every available fix is a guess at what
    /// `pi\hat u` was supposed to mean. Recorded so the next pass sees the
    /// shape; pinned so it cannot quietly grow into the working-line case.
    @Test func editingTheMiddleMayRespellAnErrorButTheSetIsPinned() {
        var respelled: [String] = []
        for c in Self.mixedCorpus(seed: 0x5EED12, count: 4000) {
            guard let pasted = Self.commit(c.line) else { continue }
            let b = Engine.evaluate([pasted])[0]
            guard b.errorMessage != nil else { continue }
            guard let edited = Self.commit(c.mixed), edited != pasted else { continue }
            let a = Engine.evaluate([edited])[0]
            if a.resultText == b.resultText && a.errorMessage == b.errorMessage { continue }
            respelled.append("\(c.line.debugDescription) split \(c.k): "
                + "\(a.errorMessage ?? a.resultText) | \(b.errorMessage ?? b.resultText)")
        }
        #expect(respelled.count == 2,
                Comment(rawValue: "error respellings: \(respelled.count), pinned at 2\n"
                    + respelled.joined(separator: "\n")))
    }
}
