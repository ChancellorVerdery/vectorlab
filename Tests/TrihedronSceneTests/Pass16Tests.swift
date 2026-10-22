import AppKit
import SceneKit
import Testing
import TrihedronCore
@testable import TrihedronScene

/// Pass 16 — where a label sits vertically.
///
/// `makeLabel` centred each label on the midpoint of its own SCNText ink box
/// and hung the arrow/hat mark off its own ink top. Both of those depend on
/// which glyphs the name contains, so two labels drawn at the same size on the
/// same anchor sat at different heights: a descender pulled the whole label
/// down, a subscript-only tail pushed the mark down. Fifteen passes measured
/// label WIDTHS and never once read a label's y.
///
/// These tests do not recompute the app's arithmetic. They build real scenes
/// through the public `update(...)` and read the scene graph back.
@Suite struct Pass16Tests {

    /// One label as the scene actually holds it.
    struct Placed {
        var name: String
        /// The vertical pivot: how far the text is pushed down from its own
        /// local origin. This is what makes the label sit on its anchor.
        var pivotY: Double
        /// Ink box of the laid-out text, for the record.
        var inkMinY: Double
        var inkMaxY: Double
        /// y of the mark pieces (bar/hat arms and arrow head), if any.
        var markY: [Double]

        /// What `makeLabel` used before this pass: the ink-box centre.
        var oldPivotY: Double { (inkMinY + inkMaxY) / 2 }
    }

    /// Every SCNText node in a scene built from `labels`, keyed by the string
    /// SCNText is actually holding.
    static func placed(pointLabels labels: [String]) -> [Placed] {
        let controller = VectorSceneController()
        controller.update(
            items: labels.enumerated().map { i, l in
                ColoredDrawable(
                    drawable: Drawable(shape: .point(Vec3(Double(i), 0, 0)), label: l),
                    colorIndex: 0)
            },
            arcs: [], showAxes: false, showGrid: false)
        return collect(controller.scene.rootNode)
    }

    /// Same, but as arrows, which are the drawables that carry a mark.
    /// Length 3 (not 1) so the mark is the full-width arrow rather than a hat.
    static func placed(arrowLabels labels: [String]) -> [Placed] {
        let controller = VectorSceneController()
        controller.update(
            items: labels.enumerated().map { i, l in
                ColoredDrawable(
                    drawable: Drawable(shape: .arrow(tail: Vec3(0, Double(i) * 8, 0),
                                                     vector: Vec3(3, 0, 0)),
                                       label: l),
                    colorIndex: 0)
            },
            arcs: [], showAxes: false, showGrid: false)
        return collect(controller.scene.rootNode)
    }

    static func collect(_ root: SCNNode) -> [Placed] {
        var out: [Placed] = []
        func walk(_ n: SCNNode) {
            if let text = n.geometry as? SCNText {
                let name = (text.string as? NSAttributedString)?.string
                    ?? (text.string as? String) ?? "?"
                let (lo, hi) = text.boundingBox
                out.append(Placed(
                    name: name,
                    pivotY: Double(n.pivot.m42),
                    inkMinY: Double(lo.y), inkMaxY: Double(hi.y),
                    markY: n.childNodes.compactMap { c in
                        (c.geometry is SCNBox || c.geometry is SCNPyramid)
                            ? Double(c.position.y) : nil
                    }))
            }
            n.childNodes.forEach(walk)
        }
        walk(root)
        return out
    }

    /// Names this app really draws. Deliberately mixes cap-only (`F`), full
    /// descenders (`y`, `j`, `g`, `p`), x-height-only (`x`, `u`), subscripted
    /// (`r_AB`, `M_O`, `F_1`), marked (`û`, `θ`) and digits.
    static let corpus = ["F", "y", "j", "g", "p", "x", "u", "T", "A", "1",
                         "r_AB", "M_O", "F_1", "\u{FB}", "\u{3B8}", "W"]

    // MARK: - The invariant

    @Test func everyLabelSitsAtOneHeightWhateverItsGlyphs() {
        let all = Self.placed(pointLabels: Self.corpus)
        // The axes node is built (hidden) even with showAxes: false, so its
        // three tick labels are in the graph too. They are labels like any
        // other and belong in this check, so assert coverage, not a count.
        // `attributedLabel` consumes the underscore and sizes the tail down, so
        // `r_AB` reaches SCNText as `rAB`. Compare against what is drawn.
        for name in Self.corpus {
            let drawn = name.replacingOccurrences(of: "_", with: "")
            #expect(all.contains { $0.name == drawn }, "\(name) never reached the scene")
        }
        guard let first = all.first else { return }
        for p in all {
            #expect(abs(p.pivotY - first.pivotY) < 1e-9,
                    "\(p.name) pivots at \(p.pivotY), \(first.name) at \(first.pivotY)")
        }
    }

    @Test func everyArrowMarkSitsAtOneHeightWhateverTheName() {
        let all = Self.placed(arrowLabels: Self.corpus)
        let ys = all.flatMap(\.markY)
        #expect(!ys.isEmpty)
        guard let first = ys.first else { return }
        for (p, y) in all.flatMap({ p in p.markY.map { (p, $0) } }) {
            #expect(abs(y - first) < 1e-9, "\(p.name)'s mark sits at \(y), expected \(first)")
        }
    }

    /// The axis ticks are the visible case: `x` has no descender and `y` does.
    @Test func theAxisLabelsAgreeWithEachOther() {
        let controller = VectorSceneController()
        controller.update(items: [], arcs: [], showAxes: true, showGrid: false)
        let axes = Self.collect(controller.scene.rootNode)
            .filter { ["x", "y", "z"].contains($0.name) }
        #expect(axes.count == 3, "expected three axis labels, got \(axes.map(\.name))")
        let pivots = Set(axes.map { ($0.pivotY * 1e9).rounded() })
        #expect(pivots.count == 1, "axis labels pivot at \(axes.map { ($0.name, $0.pivotY) })")
        // Measured under the ink-box rule this replaces: `x` and `z` centred at
        // 1.2674 and `y` — the one with a descender — at 1.1714, so the three
        // ticks of one axis triad sat across a 0.0960 band. Recorded here as a
        // number rather than asserted: `oldPivotY` re-reads SCNText's bounding
        // box, and that read is not always ready (see the pass-16 notes).

    }

    // MARK: - What must NOT have moved

    /// The datum is the ordinary case, not a new place. A lone capital's cap
    /// band IS its ink box, so `F` lands exactly where it always did.
    @Test func aLoneCapitalDoesNotMove() {
        guard let f = Self.placed(pointLabels: ["F"]).first else {
            Issue.record("no label built"); return
        }
        guard f.inkMinY.isFinite, f.inkMaxY.isFinite else {
            Issue.record("SCNText had no box to re-read for F"); return
        }
        #expect(f.pivotY == f.oldPivotY,
                "F pivots at \(f.pivotY), ink-box centre is \(f.oldPivotY)")
    }

    /// Horizontal placement is untouched by this pass: the x pivot is still
    /// the ink centre, so pass 14's mark arithmetic holds bit for bit.
    @Test func horizontalCentringIsUnchanged() {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(
                drawable: Drawable(shape: .point(.zero), label: "r_AB"), colorIndex: 0)],
            arcs: [], showAxes: false, showGrid: false)
        var checked = false
        func walk(_ n: SCNNode) {
            if let text = n.geometry as? SCNText {
                let (lo, hi) = text.boundingBox
                guard Double(lo.x).isFinite, Double(hi.x).isFinite else { return }
                #expect(abs(Double(n.pivot.m41) - Double(lo.x + hi.x) / 2) < 1e-9)
                checked = true
            }
            n.childNodes.forEach(walk)
        }
        walk(controller.scene.rootNode)
        #expect(checked)
    }

    // MARK: - The record

    /// A printer, not an assertion — the table the next pass should argue from.
    @Test func recordLabelVerticalPlacement() {
        let points = Self.placed(pointLabels: Self.corpus)
        let arrows = Self.placed(arrowLabels: Self.corpus)
        var markFor: [String: Double] = [:]
        for a in arrows { if let y = a.markY.first { markFor[a.name] = y } }
        print(String(format: "%-8@ %9@ %9@ %9@ %9@ %9@", "name" as NSString,
                     "inkMinY" as NSString, "inkMaxY" as NSString,
                     "oldPivot" as NSString, "newPivot" as NSString, "markY" as NSString))
        for p in points {
            print(String(format: "%-8@ %9.4f %9.4f %9.4f %9.4f %9.4f", p.name as NSString,
                         p.inkMinY, p.inkMaxY, p.oldPivotY, p.pivotY,
                         markFor[p.name] ?? Double.nan))
        }
        let old = points.map(\.oldPivotY)
        print(String(format: "old pivot spread %.4f -> new %.4f",
                     (old.max() ?? 0) - (old.min() ?? 0),
                     (points.map(\.pivotY).max() ?? 0) - (points.map(\.pivotY).min() ?? 0)))
    }
}
