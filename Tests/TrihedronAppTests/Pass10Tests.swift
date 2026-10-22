import Foundation
import Testing
import TrihedronCore
@testable import Trihedron

/// Pass 10. Two jobs.
///
/// 1. The bug: `MathPrint.pretty` is not a fixed point, which breaks the
///    two-Return contract `RichEntryField.renderOrSubmit` documents.
/// 2. The handoff passes 8 and 9 both left open: `RichEntryField.buildStyled`
///    was the largest untested surface in the repo. The pins below are its
///    first tests — they pass pre-fix and exist to hold it still.
@MainActor
@Suite struct Pass10Tests {

    // MARK: - Bug 1: pretty is not a fixed point

    /// `renderOrSubmit` only commits when `pretty(text) == text`; otherwise it
    /// rewrites and refocuses. So a non-idempotent rule costs the user a Return.
    static func returnsNeededToCommit(_ line: String, limit: Int = 8) -> Int {
        var text = line
        for n in 1...limit {
            let p = MathPrint.pretty(text)
            if p == text { return n }   // this Return commits
            text = p                     // this Return only rendered
        }
        return limit + 1
    }

    @Test func prettyIsAFixedPoint() {
        // A script glyph made by applyScripts is not a \b word character, so it
        // opens a word boundary that lets \bpi\b fire only on the NEXT pass.
        for line in ["x^2pi", "2^2pi", "r_1pi", "u^21pi", "pi_0pi"] {
            let once = MathPrint.pretty(line)
            #expect(MathPrint.pretty(once) == once,
                    "pretty(\(line.debugDescription)) = \(once.debugDescription) is not stable")
        }
    }

    @Test func aLineCommitsAfterAtMostTwoReturns() {
        for line in ["x^2pi", "2^2pi", "r_1pi"] {
            #expect(Self.returnsNeededToCommit(line) <= 2,
                    "\(line.debugDescription) needed \(Self.returnsNeededToCommit(line)) Returns")
        }
    }

    /// Bug 2, found by the pin below. `*` becomes U+00B7 MIDDLE DOT BEFORE
    /// `pi` is converted, and U+00B7 is UAX #29 MidLetter: between two letters
    /// it does NOT open a word boundary. So `\b` sees "pi<dot>r" as one word
    /// and pi never renders -- permanently, not just for one extra pass.
    @Test func piRendersNextToAMultiplyDot() {
        #expect(MathPrint.pretty("pi*r^2") == "\u{03C0}\u{00B7}r\u{00B2}")
        #expect(MathPrint.pretty("r*pi") == "r\u{00B7}\u{03C0}")
        #expect(MathPrint.pretty("pi*d") == "\u{03C0}\u{00B7}d")
        #expect(MathPrint.pretty("a*pi*b") == "a\u{00B7}\u{03C0}\u{00B7}b")
    }

    /// Pin: the values pass 9 and earlier hold must not move.
    @Test func ordinaryPrettyOutputIsUnchanged() {
        let pins: [(String, String)] = [
            ("pi", "π"), ("2*pi", "2·π"), ("pi*r^2", "π·r²"), ("sin(pi/4)", "sin(π/4)"),
            ("\\hat u", "û"), ("\\vec{F} = <1,2,3>", "\\vec F = <1,2,3>"),
            ("\\theta = 30", "θ = 30"), ("a \\cdot b", "a · b"), ("a \\times b", "a × b"),
            ("F_1", "F₁"), ("x^2", "x²"), ("2^3.5", "2^3.5"), ("2^3", "2³"),
            ("sqrt(2)", "√(2)"), ("50@30", "50∠30"), ("spin", "spin"), ("2pi", "2pi"),
        ]
        for (input, want) in pins {
            #expect(MathPrint.pretty(input) == want,
                    "pretty(\(input.debugDescription)) = \(MathPrint.pretty(input).debugDescription)")
        }
    }

    // MARK: - Pins: buildStyled (first tests this function has ever had)

    static let corpus: [String] = [
        "\\vec F = <1,2,3>", "\\vec F", "\\vec ", "\\vec", "\\vector F = <1,2,3>",
        "\\overrightarrow F = <1,2,3>", "\\vec{F} = <1,2,3>", "\\vec  F = <1,2,3>",
        "F_AB = <1,2,3>", "\\vec F_AB = <1,2,3>", "r_AB", "F₁ = <1,2,3>", "x² = 4",
        "û = <1,0,0>", "\\hat u = <1,0,0>", "A = (1,2,3)", "θ = 30", "# c", "// n",
        "", " ", "=", "a = b = c", "\\vec F + \\vec G", "2^3", "a·b", "mag(F)",
    ]

    /// The characters of the styled line are written straight back into the
    /// text binding by `syncFromRich`, and pass 8 proved that string is then
    /// parsed. Dropping or reordering one character silently edits the user.
    @Test func buildStyledNeverChangesTheUsersText() {
        for raw in Self.corpus {
            for deco in [LineDecoration?.none, .some(.vectorArrow), .some(.unitHat)] {
                let back = String(RichEntryField.buildStyled(raw, decoration: deco).attr.characters)
                #expect(back == raw, "buildStyled altered \(raw.debugDescription) -> \(back.debugDescription)")
            }
        }
    }

    /// An explicit `\vec NAME` hides the command and arrows the name, so the
    /// span must start at or after the hidden run and have real width.
    @Test func explicitVecArrowsItsName() {
        for raw in ["\\vec F", "\\vector F = <1,2,3>", "\\overrightarrow F = <1,2,3>"] {
            let spans = RichEntryField.buildStyled(raw, decoration: nil).spans
            #expect(spans.count == 1, "\(raw.debugDescription) produced \(spans.count) spans")
            #expect(spans.first.map { $0.width > 0 } ?? false)
        }
        // Two marks on one line get two separate arrows.
        #expect(RichEntryField.buildStyled("\\vec F + \\vec G", decoration: nil).spans.count == 2)
        // A \vec with no name yet stays visible and gets no arrow.
        #expect(RichEntryField.buildStyled("\\vec ", decoration: nil).spans.isEmpty)
        #expect(RichEntryField.buildStyled("\\vec", decoration: nil).spans.isEmpty)
    }

    /// The engine-derived decoration draws over the DEFINED name — the last
    /// name run before the first `=` — and replaces any explicit arrow there.
    @Test func decorationLandsOnTheDefinedName() {
        for raw in ["\\vec F = <1,2,3>", "F_AB = <1,2,3>", "F₁ = <1,2,3>", "A = (1,2,3)"] {
            for (deco, want) in [(LineDecoration.unitHat, RichEntryField.ArrowSpan.Kind.hat),
                                 (.vectorArrow, .arrow)] {
                let spans = RichEntryField.buildStyled(raw, decoration: deco).spans
                #expect(spans.count == 1, "\(raw.debugDescription) produced \(spans.count) spans")
                #expect(spans.first?.kind == want)
                #expect(spans.first.map { $0.x >= 0 && $0.width > 0 } ?? false)
            }
        }
        // A line with no `=` defines nothing, so nothing is auto-decorated.
        #expect(RichEntryField.buildStyled("mag(F)", decoration: .vectorArrow).spans.isEmpty)
        // ForEach keys spans by x; two spans sharing one would drop a row.
        for raw in Self.corpus {
            let xs = RichEntryField.buildStyled(raw, decoration: .vectorArrow).spans.map(\.id)
            #expect(Set(xs).count == xs.count, "duplicate span ids in \(raw.debugDescription)")
        }
    }

    /// Neither rewriter may break a line that already worked, or silently
    /// change its answer. Measured over a fuzz corpus in the pass-10 probe;
    /// these are the cases worth keeping in the suite.
    @Test func rewritersNeverBreakAWorkingLine() {
        let working = [
            "<1,2,3>", "1 + 2", "2*3", "mag(<3,4,0>)", "a = <1,2,3>", "2^3", "F_1 = 5",
            "pi", "2*pi", "sqrt(4)", "(1,2,3)", "50@30", "x^2", "2^0.5", "sin(30)",
        ]
        for line in working {
            let base = Engine.evaluate([line], strictNotation: false)[0]
            guard base.errorMessage == nil else { continue }
            for out in [MathPrint.applyScripts(line), MathPrint.pretty(line)] {
                let after = Engine.evaluate([out], strictNotation: false)[0]
                #expect(after.errorMessage == nil,
                        "\(line.debugDescription) -> \(out.debugDescription) broke: \(after.errorMessage ?? "")")
                #expect(after.resultText == base.resultText,
                        "\(line.debugDescription) -> \(out.debugDescription) changed \(base.resultText) to \(after.resultText)")
            }
        }
    }

    // MARK: - Fuzz. These are how both bugs above were found.

    /// Deterministic LCG so any failure is reproducible from its seed.
    struct RNG {
        var s: UInt64
        mutating func next(_ n: Int) -> Int {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Int((s >> 33) % UInt64(n))
        }
    }

    /// Drawn from the app's own notation surface.
    static let alphabet: [String] = [
        "\\vec", "\\hat", "\\vector", "\\overrightarrow", "\\theta", "\\alpha", "\\cdot",
        "\\times", "\\langle", "\\rangle", "pi", "sqrt(", "*", "@", "^", "_", ".", "-",
        "1", "2", "0", "F", "u", "a", "x", " ", "(", ")", "{", "}", "<", ">", ",", "=",
        "\u{00B2}", "\u{00B3}", "\u{2081}", "\u{00B7}", "\u{221A}", "\u{03C0}", "\u{03B8}", "\u{00FB}",
    ]

    static func fuzzLines(seed: UInt64, count: Int) -> [String] {
        var rng = RNG(s: seed)
        var seen = Set<String>()
        for _ in 0..<count {
            let n = 1 + rng.next(6)
            var line = ""
            for _ in 0..<n { line += Self.alphabet[rng.next(Self.alphabet.count)] }
            seen.insert(line)
        }
        return Array(seen)
    }

    /// `renderOrSubmit` commits only at a fixed point, so a rule that needs a
    /// second pass costs a Return. This is the general form of bugs 1 and 2.
    @Test func prettyIsAFixedPointOverAFuzzCorpus() {
        var offenders: [String] = []
        for line in Self.fuzzLines(seed: 20261007, count: 40_000) {
            let p1 = MathPrint.pretty(line)
            if MathPrint.pretty(p1) != p1, offenders.count < 5 { offenders.append(line) }
        }
        #expect(offenders.isEmpty, "pretty is not stable on \(offenders.map(\.debugDescription))")
    }

    @Test func applyScriptsIsAFixedPointOverAFuzzCorpus() {
        var offenders: [String] = []
        for line in Self.fuzzLines(seed: 99887766, count: 40_000) {
            let a1 = MathPrint.applyScripts(line)
            if MathPrint.applyScripts(a1) != a1, offenders.count < 5 { offenders.append(line) }
        }
        #expect(offenders.isEmpty, "applyScripts is not stable on \(offenders.map(\.debugDescription))")
    }

    /// buildStyled must never edit the user's text (see the corpus pin above).
    @Test func buildStyledIsLosslessOverAFuzzCorpus() {
        var offenders: [String] = []
        for line in Self.fuzzLines(seed: 13572468, count: 40_000) {
            for deco in [LineDecoration?.none, .some(.vectorArrow), .some(.unitHat)] {
                let back = String(RichEntryField.buildStyled(line, decoration: deco).attr.characters)
                if back != line, offenders.count < 5 { offenders.append(line) }
            }
        }
        #expect(offenders.isEmpty, "buildStyled altered \(offenders.map(\.debugDescription))")
    }

    /// The strongest property this pass established: rewriting a line that
    /// already evaluates never breaks it and never changes its answer.
    @Test func neitherRewriterBreaksAWorkingLineOverAFuzzCorpus() {
        var offenders: [String] = []
        for line in Self.fuzzLines(seed: 5150, count: 40_000) {
            let base = Engine.evaluate([line], strictNotation: false)[0]
            guard base.errorMessage == nil else { continue }
            for out in [MathPrint.applyScripts(line), MathPrint.pretty(line)] where out != line {
                let after = Engine.evaluate([out], strictNotation: false)[0]
                if (after.errorMessage != nil || after.resultText != base.resultText),
                   offenders.count < 5 {
                    offenders.append("\(line.debugDescription) -> \(out.debugDescription)")
                }
            }
        }
        #expect(offenders.isEmpty, "rewriting changed a working line: \(offenders)")
    }
}
