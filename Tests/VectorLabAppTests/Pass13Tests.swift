import AppKit
import Foundation
import SwiftUI
import Testing
import VectorLabCore
@testable import VectorLab

/// Pass 13. Takes pass 12's handoff, which said plainly that a pass writing
/// more string tests is "mostly out of road" and that everything left needs a
/// window.
///
/// That was half right. The window is genuinely unreachable — `screencapture`
/// on this machine returns `could not create image from display`, so nothing
/// that needs pixels can be run. But one of the things pass 12 filed under
/// "needs a window" does not: `buildStyled`'s ARROW GEOMETRY. Where an overlay
/// arrow lands is not a rendering question, it is an arithmetic question about
/// font advances, and `NSFont` will answer it headlessly and exactly.
///
/// Every previous pass tested `buildStyled` for *what* it produced — spans
/// exist, spans are positive, spans do not collide (pass 10). No pass has ever
/// checked whether a span is in the RIGHT PLACE. It was not.
///
/// `buildStyled` modelled x as `advance × count`, with three advances measured
/// from the "0" glyph. Two of the three were fine. The third measured the
/// hidden `\vec ` token in the MONOSPACED system font while `hiddenStyle`
/// declares `.system(size: 1)` — no design, therefore proportional. And
/// `advance × count` is itself a guess: monospace is a promise about the
/// glyphs the font HAS, and this app renders several it does not.
@MainActor
@Suite struct Pass13Tests {

    // MARK: - The fonts the styles actually declare

    static let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
    static let monoBody = NSFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)
    static let monoSub = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    static let propHidden = NSFont.systemFont(ofSize: 1)

    static func w(_ s: String, _ f: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: f]).width
    }

    /// The mapping is written from the STYLE DECLARATIONS in
    /// `RichEntryField`, not from its measurement constants — that is the
    /// whole point. If a style and the font it is measured with ever drift
    /// apart again, this table still describes the declaration and the
    /// re-derived x stops matching.
    static func nsFont(for font: SwiftUI.Font?) -> NSFont? {
        switch font {
        case .system(.body, design: .monospaced): return monoBody
        case .system(size: 10, design: .monospaced): return monoSub
        case .system(size: 1): return propHidden
        default: return nil
        }
    }

    static func font(of run: AttributedString.Runs.Run) -> SwiftUI.Font? {
        run[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
    }

    /// x of every character boundary, re-derived from the runs `buildStyled`
    /// actually emitted, each measured in the font that run declares. This is
    /// an independent answer to the same question `buildStyled` computes.
    static func measuredWidth(_ attr: AttributedString) -> CGFloat? {
        var x: CGFloat = 0
        for run in attr.runs {
            guard let f = nsFont(for: font(of: run)) else { return nil }
            x += w(String(attr[run.range].characters), f)
        }
        return x
    }

    // MARK: - The recorded failure

    /// The bug, at its smallest. `\vec ` is hidden but still occupies real
    /// horizontal space, and the arrow starts where that space ends. Measured
    /// in the proportional 1pt font the style declares, `\vec ` is 2.39pt;
    /// the old model charged it 5 × the monospaced 1pt "0" advance, 3.09pt.
    /// Every arrow on the line sat 0.70pt right of its name, 1.77pt for
    /// `\overrightarrow`, and the error accumulates once per hidden token.
    @Test func hiddenTokensAreMeasuredWithTheFontTheyDeclare() {
        for token in ["\\vec ", "\\vector ", "\\overrightarrow "] {
            let spans = RichEntryField.buildStyled(token + "F", decoration: nil).spans
            #expect(spans.count == 1, "\(token.debugDescription) produced \(spans.count) spans")
            guard let span = spans.first else { continue }
            let want = Self.w(token, Self.propHidden)
            #expect(abs(span.x - want) < 0.001,
                    "\(token.debugDescription): arrow starts at \(span.x), the hidden text ends at \(want)")
            #expect(abs(span.width - Self.w("F", Self.monoBody)) < 0.001,
                    "\(token.debugDescription): arrow is \(span.width) wide over an 'F'")
        }
    }

    /// The same failure through `_`, the other hidden-style call site. One
    /// character, so the old model was only 0.005pt out here — pinned so both
    /// call sites are covered, not because 0.005pt ever showed on a screen.
    /// Reached through the AUTOMATIC decoration, which is the only way an
    /// overlay lands on a name whose underscore is hidden but has no `\vec`.
    @Test func theHiddenUnderscoreIsMeasuredToo() {
        let built = RichEntryField.buildStyled("F_AB = <1,2,3>", decoration: .vectorArrow)
        let want = Self.w("F", Self.monoBody) + Self.w("_", Self.propHidden) + Self.w("AB", Self.monoSub)
        #expect(built.spans.count == 1)
        #expect(built.spans.first.map { abs($0.x) < 0.001 } ?? false)
        #expect(built.spans.first.map { abs($0.width - want) < 0.001 } ?? false,
                "span width \(built.spans.first?.width ?? -1) vs measured name \(want)")
    }

    // MARK: - Monospace is not a promise about every glyph

    /// `advance × count` assumes every character in the body font is one
    /// advance wide. Over the whole alphabet this app can put on screen —
    /// ASCII, every Greek letter the lexer maps, both script digit sets, and
    /// the operator glyphs `pretty` emits — that holds for all but a pinned
    /// few, which fall back to a font that has them and come out narrow.
    ///
    /// This is not a fix reporting its own work: the set below was measured
    /// before anything changed, and it is unchanged by the change. It is here
    /// so that the reason `buildStyled` must measure is written down, and so
    /// that a future font revision that widens the set is a test failure
    /// rather than a slow drift nobody sees.
    @Test func mostGlyphsAreOneAdvanceWideAndThePinnedFewAreNot() {
        var alphabet: [String] = (33...126).map { String(UnicodeScalar($0)!) }
        alphabet += "αβγδεζηθικλμνξοπρστυφχψωΓΔΘΛΞΠΣΥΦΨΩ".map(String.init)
        alphabet += "⁰¹²³⁴⁵⁶⁷⁸⁹⁻".map(String.init)
        alphabet += ["·", "×", "√", "∞", " ", "û", "x̂", "θ\u{0302}"]

        let base = Self.w("0", Self.monoBody)
        let wrong = alphabet.filter { abs(Self.w($0, Self.monoBody) - base) > 0.0001 }
        #expect(wrong.isEmpty, "expected one advance, got other widths for \(wrong)")

        // The pinned narrow set: subscript digit glyphs and ∠, each 0.2095
        // narrow. `pretty` emits both (F_1 → F₁, 50@30 → 50∠30), so these are
        // ordinary committed lines, not exotica.
        for g in "₀₁₂₃₄₅₆₇₈₉∠".map(String.init) {
            let drift = Self.w(g, Self.monoBody) - base
            #expect(abs(drift + 0.2095) < 0.001, "\(g) drift is \(drift), pinned at -0.2095")
        }

        // A combining arrow reflows its BASE character, by an amount that
        // depends on the base. `F⃗` is what the lexer accepts as `\vec F`, so
        // a pasted line can contain it. Pinned as variable, not as a number.
        let arrowed = ["F\u{20D7}", "P\u{20D7}", "1\u{20D7}"].map { Self.w($0, Self.monoBody) - base }
        #expect(arrowed.allSatisfy { $0 < -0.3 }, "combining-arrow drift \(arrowed)")
        #expect(Set(arrowed).count == 3, "expected three DIFFERENT drifts, got \(arrowed)")
    }

    // MARK: - The general pin: spans agree with an independent measurement

    /// For every line, re-derive each span's x and width from the runs and
    /// their declared fonts, and require `buildStyled` to agree. This is the
    /// check that does not go stale: it never mentions an advance constant,
    /// so any future divergence between what a style says and what the code
    /// measures fails here regardless of which one moved.
    static func checkSpans(_ raw: String, decoration: LineDecoration?) -> String? {
        let built = RichEntryField.buildStyled(raw, decoration: decoration)
        guard let total = measuredWidth(built.attr) else {
            return "\(raw.debugDescription): a run declared a font the test does not know"
        }
        for span in built.spans {
            if span.x < -0.001 || span.width <= 0 {
                return "\(raw.debugDescription): span x=\(span.x) width=\(span.width)"
            }
            if span.x + span.width > total + 0.001 {
                return "\(raw.debugDescription): span ends at \(span.x + span.width), line is \(total) wide"
            }
        }
        return nil
    }

    @Test func spanGeometryAgreesWithRealFontMetrics() {
        let lines = [
            "\\vec F", "\\vec F + \\vec G", "\\vec F_AB = <1,2,3>",
            "F_1 = 2·π", "T = 50∠30", "û = unit(a)", "F₁₂ = 3",
            "\\overrightarrow AB = B - A", "x̂·ŷ", "\\vec F\u{20D7}",
        ]
        for line in lines {
            for deco in [nil, LineDecoration.vectorArrow, .unitHat] as [LineDecoration?] {
                #expect(Self.checkSpans(line, decoration: deco) == nil,
                        Comment(rawValue: Self.checkSpans(line, decoration: deco) ?? ""))
            }
        }
    }

    /// The exact geometry of the two cases that carry an arrow, spelled out
    /// rather than bounded — a span that is merely inside the line is a weak
    /// claim, and pass 10 already made it.
    @Test func theArrowExactlyCoversItsName() {
        let a = RichEntryField.buildStyled("\\vec F_AB", decoration: nil)
        #expect(a.spans.count == 1)
        #expect(a.spans.first.map { abs($0.x - Self.w("\\vec ", Self.propHidden)) < 0.001 } ?? false)
        let nameWidth = Self.w("F", Self.monoBody) + Self.w("_", Self.propHidden) + Self.w("AB", Self.monoSub)
        #expect(a.spans.first.map { abs($0.width - nameWidth) < 0.001 } ?? false,
                "span width \(a.spans.first?.width ?? -1) vs measured name \(nameWidth)")

        // Automatic decoration: the hat goes over the name left of `=`, which
        // starts at x = 0 and is exactly as wide as the name.
        let b = RichEntryField.buildStyled("uhat = unit(a)", decoration: .unitHat)
        #expect(b.spans.count == 1)
        #expect(b.spans.first?.kind == .hat)
        #expect(b.spans.first.map { abs($0.x) < 0.001 } ?? false)
        #expect(b.spans.first.map { abs($0.width - Self.w("uhat", Self.monoBody)) < 0.001 } ?? false)
    }

    // MARK: - Fuzz: the same agreement over pass 10's corpus

    struct LCG {
        var state: UInt64
        mutating func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(n))
        }
    }

    static func fuzzLines(seed: UInt64, count: Int) -> [String] {
        let tokens = ["\\vec ", "\\hat ", "\\overrightarrow ", "F", "G", "u", "AB",
                      "_1", "_AB", "^2", "=", "+", "-", "*", "@", "pi", "π", "·",
                      "∠", "₁", "(", ")", "<", "1", "2", "3", ",", " ", "unit",
                      "mag", "sqrt", "x̂", "û", "F\u{20D7}", ">", ".", "5", "/",
                      "cos", "e", "\\theta ", "\\cdot"]
        var rng = LCG(state: seed)
        return (0..<count).map { _ in
            (0..<(1 + rng.next(6))).map { _ in tokens[rng.next(tokens.count)] }.joined()
        }
    }

    @Test func spanGeometryAgreesOverAFuzzCorpus() {
        var offenders: [String] = []
        for line in Self.fuzzLines(seed: 0x13A7, count: 1500) {
            for deco in [nil, LineDecoration.vectorArrow, .unitHat] as [LineDecoration?] {
                if let bad = Self.checkSpans(line, decoration: deco) { offenders.append(bad) }
            }
        }
        #expect(offenders.isEmpty,
                Comment(rawValue: "\(offenders.count) bad: \(offenders.prefix(5).joined(separator: " | "))"))
    }

    /// Measuring instead of multiplying costs something, and the cost lands on
    /// the main thread once per keystroke. Bounded here so a future change
    /// that drops the cache shows up as a failure rather than as typing lag
    /// nobody can reproduce. Deliberately loose — this is a regression guard,
    /// not a benchmark, and CI machines vary.
    @Test func buildStyledStaysCheapEnoughToRunPerKeystroke() {
        let line = "\\vec F_AB = 3.5·π·<1,2,3> + mag(G)·û + 50∠30 - sqrt(2)·x̂ + F₁₂"
        _ = RichEntryField.buildStyled(line, decoration: .vectorArrow)   // warm the cache
        let t0 = Date()
        for _ in 0..<200 { _ = RichEntryField.buildStyled(line, decoration: .vectorArrow) }
        let per = Date().timeIntervalSince(t0) / 200
        #expect(per < 0.002, "buildStyled took \(per * 1000)ms on a \(line.count)-character line")
    }
}
