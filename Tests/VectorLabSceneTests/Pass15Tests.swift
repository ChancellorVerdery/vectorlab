import AppKit
import SceneKit
import Testing
import VectorLabCore
@testable import VectorLabScene

/// Pass 15 — the subscript metrics in `attributedLabel`, which pass 14 named as
/// the last unmeasured constants in the label path.
///
/// `_AB` in a name was documented as typesetting "smaller, LOWERED, no
/// underscore" and carried `.baselineOffset: -0.22` to do the lowering. The
/// lowering never happened: SCNText puts every run of an attributed string on
/// one baseline. Nothing had ever asked, because nothing headless had ever
/// measured a label's y extent — passes 6 and 11 asked only that labels exist.
///
/// These tests go through the public `update(items:arcs:showAxes:showGrid:)`
/// and read the built SCNText, except `baselineOffsetIsStillANoOpInSCNText`,
/// which builds its own SCNText so that it pins SceneKit's behaviour rather
/// than the app's use of it.
@Suite struct Pass15Tests {

    struct Box {
        var minX: Double, maxX: Double, minY: Double, maxY: Double
        var width: Double { maxX - minX }
        var height: Double { maxY - minY }
    }

    /// The bounding box of the SCNText built for `label`, straight out of the
    /// scene graph. Nothing here recomputes the app's arithmetic.
    static func box(for label: String) -> Box? {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(3, 0, 0)), label: label),
                colorIndex: 0)],
            arcs: [], showAxes: false, showGrid: false)
        var found: Box?
        func walk(_ n: SCNNode) {
            if let text = n.geometry as? SCNText, found == nil {
                let (lo, hi) = text.boundingBox
                found = Box(minX: Double(lo.x), maxX: Double(hi.x),
                            minY: Double(lo.y), maxY: Double(hi.y))
            }
            n.childNodes.forEach(walk)
        }
        walk(controller.scene.rootNode)
        return found
    }

    static func rawBox(_ s: NSAttributedString) -> Box {
        let t = SCNText(string: s, extrusionDepth: 0)
        t.flatness = 0.05
        let (lo, hi) = t.boundingBox
        return Box(minX: Double(lo.x), maxX: Double(hi.x), minY: Double(lo.y), maxY: Double(hi.y))
    }

    // MARK: - What the subscript path actually does

    /// The underscore is consumed, not drawn. A literal `_` is the one glyph in
    /// a name that reaches well below the baseline, so it is its own detector:
    /// `F_` sinks the box to y 0.8356 and `F_1` must not.
    @Test func theUnderscoreIsNotRendered() {
        guard let sub = Self.box(for: "F_1"), let literal = Self.box(for: "F_"),
              let plain = Self.box(for: "F") else { Issue.record("no label built"); return }
        #expect(literal.minY < plain.minY - 0.1,
                "control: a drawn underscore should sink the box, got \(literal.minY) vs \(plain.minY)")
        #expect(abs(sub.minY - plain.minY) < 1e-6,
                "F_1 sits at \(sub.minY), F at \(plain.minY) — an underscore is being drawn")
        #expect(sub.width < literal.width,
                "F_1 (\(sub.width)) should be narrower than F_ (\(literal.width))")
    }

    /// The subscript run is smaller than base text, and by roughly the declared
    /// 0.62 — measured as the width the run ADDS, against the width a full-size
    /// character adds. Neither side is computed from the constant.
    @Test func theSubscriptRunIsSmallerThanBaseText() {
        guard let plain = Self.box(for: "F"), let full = Self.box(for: "F1"),
              let sub = Self.box(for: "F_1") else { Issue.record("no label built"); return }
        let fullAdd = full.width - plain.width
        let subAdd = sub.width - plain.width
        #expect(subAdd > 0, "the subscript added no width at all")
        #expect(subAdd < fullAdd,
                "subscript added \(subAdd), a full-size character adds \(fullAdd)")
        #expect(abs(subAdd / fullAdd - 0.62) < 0.1,
                "subscript/base width ratio is \(subAdd / fullAdd), declared 0.62")
    }

    // MARK: - The pin: SCNText cannot lower a run

    /// `.baselineOffset` was in this code for its whole life and never moved a
    /// glyph. Neither does CoreText's own key, nor CTSuperscript, nor a
    /// translating font matrix — all four measured identical here.
    ///
    /// **If this test ever fails, that is good news, not a regression:** it
    /// means SceneKit gained run-relative vertical placement, and
    /// `attributedLabel` can be given a real lowered subscript. Read the box
    /// numbers in the failure message before changing anything.
    @Test func baselineOffsetIsStillANoOpInSCNText() {
        let base = NSFont.monospacedSystemFont(ofSize: 1, weight: .semibold)
        let small = NSFont.monospacedSystemFont(ofSize: 0.62, weight: .semibold)
        func combo(_ attrs: [NSAttributedString.Key: Any]) -> Box {
            let a = NSMutableAttributedString(string: "F", attributes: [.font: base])
            var at = attrs
            if at[.font] == nil { at[.font] = small }
            a.append(NSAttributedString(string: "1", attributes: at))
            return Self.rawBox(a)
        }
        let control = combo([:])
        let ctKey = NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)
        let candidates: [(String, [NSAttributedString.Key: Any])] = [
            ("NSBaselineOffset -0.22", [.baselineOffset: -0.22]),
            ("NSBaselineOffset -0.50", [.baselineOffset: -0.50]),
            ("CTBaselineOffset -0.22", [ctKey: -0.22]),
            ("CTBaselineOffset -0.50", [ctKey: -0.50]),
            ("CTSuperscript -1", [.superscript: -1]),
        ]
        for (name, attrs) in candidates {
            let got = combo(attrs)
            #expect(abs(got.minY - control.minY) < 1e-9 && abs(got.maxY - control.maxY) < 1e-9,
                    "\(name) MOVED the run: y=[\(got.minY),\(got.maxY)] vs control [\(control.minY),\(control.maxY)] — SCNText may now support lowered runs")
        }
    }

    /// A font matrix carrying a translation is the other documented way to
    /// lower CoreText glyphs. It is also inert here.
    @Test func aTranslatingFontMatrixIsAlsoANoOp() {
        let base = NSFont.monospacedSystemFont(ofSize: 1, weight: .semibold)
        let proto = NSFont.monospacedSystemFont(ofSize: 0.62, weight: .semibold)
        func lowered(_ drop: CGFloat) -> NSFont {
            var m = AffineTransform(scaleByX: 0.62, byY: 0.62)
            m.append(AffineTransform(translationByX: 0, byY: -drop))
            let d = proto.fontDescriptor.addingAttributes([.matrix: m as NSAffineTransform])
            return NSFont(descriptor: d, size: 0) ?? proto
        }
        func boxWith(_ f: NSFont) -> Box {
            let a = NSMutableAttributedString(string: "F", attributes: [.font: base])
            a.append(NSAttributedString(string: "1", attributes: [.font: f]))
            return Self.rawBox(a)
        }
        let control = boxWith(lowered(0))
        for drop in [0.1, 0.22, 0.3] as [CGFloat] {
            let got = boxWith(lowered(drop))
            #expect(abs(got.minY - control.minY) < 1e-9,
                    "matrix drop \(drop) moved the run to \(got.minY) from \(control.minY)")
        }
    }

    // MARK: - Why 0.62 stays

    /// The font's own designed subscript digit is the only external reference
    /// for how big a subscript should be, and it also sits on the baseline —
    /// which is why the missing lowering never showed. `F_1` and `F₁`, the two
    /// spellings of the same name that this app can both produce (`applyScripts`
    /// rewrites the entry text, a workspace loaded from disk is not rewritten),
    /// must therefore land in the same vertical band.
    @Test func theTwoSpellingsOfASubscriptedNameShareABaseline() {
        guard let underscore = Self.box(for: "F_1"), let unicode = Self.box(for: "F\u{2081}")
        else { Issue.record("no label built"); return }
        #expect(abs(underscore.minY - unicode.minY) < 0.01,
                "F_1 bottom \(underscore.minY) vs F₁ bottom \(unicode.minY)")
        #expect(abs(underscore.maxY - unicode.maxY) < 0.01,
                "F_1 top \(underscore.maxY) vs F₁ top \(unicode.maxY)")
    }

    /// Diagnostic: the numbers behind the decision to keep 0.62, printed rather
    /// than argued. `₁` measured alone is the font's designed subscript.
    @Test func recordSubscriptMetricsAgainstTheFontsOwnSubscript() {
        let small = NSFont.monospacedSystemFont(ofSize: 0.62, weight: .semibold)
        let base = NSFont.monospacedSystemFont(ofSize: 1, weight: .semibold)
        let run = Self.rawBox(NSAttributedString(string: "1", attributes: [.font: small]))
        let glyph = Self.rawBox(NSAttributedString(string: "\u{2081}", attributes: [.font: base]))
        print(String(format: "SUB 0.62-run   w=%.4f h=%.4f y=[%.4f,%.4f]", run.width, run.height, run.minY, run.maxY))
        print(String(format: "SUB font-glyph w=%.4f h=%.4f y=[%.4f,%.4f]", glyph.width, glyph.height, glyph.minY, glyph.maxY))
        print(String(format: "SUB size that would match width=%.4f  height=%.4f",
                     0.62 * glyph.width / run.width, 0.62 * glyph.height / run.height))
        for label in ["F", "F1", "F_1", "F\u{2081}", "M_O", "r_AB", "N_1", "F_1_2", "F_"] {
            guard let b = Self.box(for: label) else { continue }
            print(String(format: "SUB %-8@ w=%.4f y=[%.4f,%.4f]", label, b.width, b.minY, b.maxY))
        }
    }
}
