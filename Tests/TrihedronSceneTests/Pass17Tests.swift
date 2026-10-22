import AppKit
import SceneKit
import Testing
import TrihedronCore
@testable import TrihedronScene

/// Pass 17 — `SCNText.boundingBox` and the empty-box sentinel.
///
/// Pass 16 saw `boundingBox` hand back `(+inf, -inf)` — SceneKit's "this box is
/// empty" sentinel — for `A` and `r_AB` on a re-read, and finite numbers for the
/// same strings on another run. It flagged that as unestablished and immunised
/// the VERTICAL datum against it by computing that once in a `static let`.
///
/// The HORIZONTAL read in `makeLabel` was left alone, and it is the one that
/// matters: `pivotX = (minB.x + maxB.x) / 2`, which on the sentinel is
/// `(+inf + -inf) / 2` — NaN. A NaN pivot is not a mispositioned label, it is a
/// label with no position at all.
///
/// These tests establish, by measurement, three separate things: what the
/// sentinel IS, when it appears, and what the app does when it gets one.
@Suite struct Pass17Tests {

    // MARK: - Fixtures

    /// Rebuilt locally rather than reaching into `VectorSceneController`, which
    /// is what Pass15Tests does with the same two fonts. Kept identical to
    /// `attributedLabel` on purpose; `theTestFixtureMatchesTheApp` pins that.
    static func attributed(_ string: String) -> NSAttributedString {
        let base = NSFont.monospacedSystemFont(ofSize: 1, weight: .semibold)
        let small = NSFont.monospacedSystemFont(ofSize: 0.62, weight: .semibold)
        let result = NSMutableAttributedString()
        var idx = string.startIndex
        while idx < string.endIndex {
            if string[idx] == "_" {
                var j = string.index(after: idx)
                var run = ""
                while j < string.endIndex, string[j].isLetter || string[j].isNumber {
                    run.append(string[j]); j = string.index(after: j)
                }
                if !run.isEmpty {
                    result.append(NSAttributedString(string: run, attributes: [.font: small]))
                    idx = j; continue
                }
            }
            result.append(NSAttributedString(string: String(string[idx]), attributes: [.font: base]))
            idx = string.index(after: idx)
        }
        return result
    }

    static func scnText(_ s: String) -> SCNText {
        let t = SCNText(string: attributed(s), extrusionDepth: 0)
        t.flatness = 0.05
        return t
    }

    /// Pass 16's corpus plus the axis triad, which is where a height or width
    /// disagreement is visible to a user.
    static let corpus = ["F", "y", "g", "p", "j", "x", "u", "M_O", "\u{fb}", "\u{3b8}",
                         "T", "1", "W", "F_1", "A", "r_AB", "z", "n"]

    static func isFiniteBox(_ b: (min: SCNVector3, max: SCNVector3)) -> Bool {
        b.min.x.isFinite && b.max.x.isFinite && b.min.y.isFinite && b.max.y.isFinite
    }

    // MARK: - What the sentinel is, and that it is reachable

    /// SceneKit's empty box is `(+inf, -inf)` — the identity element for box
    /// union, not a measurement. It is NOT what an empty string produces: an
    /// empty SCNText measures an honest `(0, 0)`. Recorded because the empty
    /// string was the obvious suspect and it is innocent.
    @Test func anEmptyStringMeasuresZeroNotTheSentinel() {
        let (lo, hi) = Self.scnText("").boundingBox
        #expect(lo.x == 0 && hi.x == 0)
        #expect(lo.y == 0 && hi.y == 0)
    }

    /// The arithmetic `makeLabel` performed on the sentinel. No SceneKit
    /// involved — this is the whole reason the sentinel is not survivable.
    @Test func theSentinelTurnsThePivotIntoNaN() {
        let lo = CGFloat.infinity, hi = -CGFloat.infinity
        #expect(((lo + hi) / 2).isNaN)          // pivot x
        #expect((hi - lo) == -CGFloat.infinity) // label half-width
        // The arrow mark survives, because its span is clamped from below.
        #expect(max(CGFloat(0.34), hi - lo) == 0.34)
    }

    /// Which ordinary names read back as the sentinel, on a FIRST read, on one
    /// thread, immediately after construction — which is exactly what
    /// `makeLabel` does.
    ///
    /// Record-only, and deliberately so. Pass 16 saw `A` and `r_AB` come back
    /// `inf` on one run and `r_AB` come back finite on another, and warned that
    /// anything asserted about a re-read is flaky by construction. This prints
    /// the answer for the run you are looking at instead of pretending it is a
    /// constant. What is NOT in doubt is the consequence, which is asserted
    /// separately by `everyLabelInTheSceneHasAFinitePivot`.
    @Test func recordWhichNamesReadBackAsTheSentinel() {
        var counts: [String: Int] = [:]
        for _ in 0..<40 {
            for s in Self.corpus where !Self.isFiniteBox(Self.scnText(s).boundingBox) {
                counts[s, default: 0] += 1
            }
        }
        print("PASS17 sentinel first-reads out of 40: \(counts.sorted { $0.key < $1.key })")
        #expect(Self.corpus.count == 18)
    }

    /// Re-reading one object: does the answer settle, or keep changing?
    @Test func recordWhetherRepeatedReadsOfOneObjectAgree() {
        var unstable: [String] = []
        for s in Self.corpus {
            let t = Self.scnText(s)
            let first = t.boundingBox
            for _ in 0..<8 where t.boundingBox.min.x != first.min.x { unstable.append(s) }
        }
        print("PASS17 unstable on re-read: \(Set(unstable).sorted())")
        #expect(true)
    }

    /// WHICH STEP makes the box readable. This is the question pass 16 left
    /// open — it saw the sentinel on a re-read and could not say whether
    /// `makeLabel`'s own read is exposed.
    ///
    /// `makeLabel` does three things to an SCNText before it reads the box:
    /// sets `flatness`, assigns `materials`, and hands it to `SCNNode(geometry:)`.
    /// Each stage below is a FRESH text taken to that point and then read once.
    /// Whichever stage first comes back finite is the one that forces layout.
    @Test func recordWhichConstructionStepMakesTheBoxReadable() {
        func stage(_ name: String, _ prepare: (SCNText) -> Void) {
            var bad: [String] = []
            for s in Self.corpus {
                let t = Self.scnText(s)
                prepare(t)
                if !Self.isFiniteBox(t.boundingBox) { bad.append(s) }
            }
            print("PASS17 stage \(name): sentinel for \(bad)")
        }
        stage("bare") { _ in }
        stage("materials") { $0.materials = [SCNMaterial()] }
        stage("node") { _ = SCNNode(geometry: $0) }
        stage("materials+node") {
            $0.materials = [SCNMaterial()]
            _ = SCNNode(geometry: $0)
        }
        // And the order makeLabel actually uses, read twice: does a first read
        // that returns the sentinel poison the second?
        var recovered: [String] = []
        for s in Self.corpus {
            let t = Self.scnText(s)
            let first = Self.isFiniteBox(t.boundingBox)
            t.materials = [SCNMaterial()]
            _ = SCNNode(geometry: t)
            if !first && Self.isFiniteBox(t.boundingBox) { recovered.append(s) }
        }
        print("PASS17 sentinel then recovered after materials+node: \(recovered)")
        #expect(Self.corpus.count == 18)
    }

    // MARK: - The fallback measurement

    /// There is no concurrency test here, and the reason is itself a finding.
    ///
    /// The obvious hypothesis for an intermittent sentinel is a data race:
    /// SceneKit building geometry on two threads at once. That hypothesis
    /// cannot be written down. `SCNText` and `NSFont` are main-actor isolated
    /// and non-Sendable, so a `DispatchQueue.concurrentPerform` closure that
    /// constructs one does not compile — verbatim:
    ///
    ///     error: non-Sendable 'SCNText'-typed result can not be returned from
    ///     main actor-isolated static method 'scnText' to nonisolated context
    ///
    /// The same isolation covers `VectorSceneController`, so `makeLabel` only
    /// ever runs on the main actor. Whatever this is, it is not two threads
    /// racing on one geometry; the compiler will not let the app do that.


    /// If the ink box cannot be trusted, something else has to answer "how wide
    /// is this label". CoreText's typographic advance is the candidate the fix
    /// uses: it comes from the text system rather than SceneKit's geometry
    /// builder, so it cannot be the sentinel.
    ///
    /// It is not the same number. The advance is the monospace cell — every
    /// single-character name measures exactly 0.6182 — while the ink box is the
    /// glyph inside that cell. So the advance is always at least as wide, equal
    /// only for a glyph that fills its cell (`W` measures 1.0000 exactly), and
    /// up to 1.68x for a narrow one (`j`). That is why it is a fallback and not
    /// the measurement: it keeps a label finite and roughly centred, it does not
    /// reproduce the ink box.
    @Test func theTypographicAdvanceBoundsTheInkBox() {
        var ratios: [Double] = []
        for s in Self.corpus {
            let (lo, hi) = Self.scnText(s).boundingBox
            guard lo.x.isFinite, hi.x.isFinite else { continue }
            let ink = Double(hi.x) - Double(lo.x)
            let adv = Double(Self.attributed(s).size().width)
            ratios.append(adv / ink)
            print("PASS17 width: \(s)  ink=\(ink)  advance=\(adv)  ratio=\(adv / ink)")
        }
        #expect(!ratios.isEmpty)
        #expect(ratios.allSatisfy { $0 >= 1.0 && $0 < 2.0 },
                "advance/ink ratios: \(ratios.map { ($0 * 1e4).rounded() / 1e4 })")
    }

    // MARK: - The consequence, which IS asserted

    /// The pass's assertion. Every label the scene builds, for every name in the
    /// corpus, must have a finite pivot. A NaN pivot is not a mispositioned
    /// label; it is a node with no transform, and nothing downstream checks.
    ///
    /// Before this pass this failed for whichever names read back as the
    /// sentinel on the run — `A` and `r_AB` when it was recorded, both of which
    /// are ordinary names and one of which is in the app's own sample notebook.
    @Test func everyLabelInTheSceneHasAFinitePivot() {
        for name in Self.corpus {
            let c = VectorSceneController()
            c.update(items: [ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(3, 0, 0)), label: name),
                colorIndex: 0)],
                arcs: [], showAxes: true, showGrid: false)
            var seen = 0
            func walk(_ n: SCNNode) {
                if n.geometry is SCNText {
                    seen += 1
                    #expect(n.pivot.m41.isFinite, "\(name): pivot x is \(n.pivot.m41)")
                    #expect(n.pivot.m42.isFinite, "\(name): pivot y is \(n.pivot.m42)")
                    for child in n.childNodes {
                        #expect(child.position.x.isFinite, "\(name): mark x is \(child.position.x)")
                        #expect(child.position.y.isFinite, "\(name): mark y is \(child.position.y)")
                    }
                }
                n.childNodes.forEach(walk)
            }
            walk(c.scene.rootNode)
            #expect(seen > 0, "\(name): the scene held no label at all")
        }
    }

    /// And the guard must not move anything. Wherever the ink box IS readable,
    /// the pivot has to be its centre, bit for bit — the fallback is only for
    /// the case where there is no measurement to preserve.
    @Test func aReadableInkBoxStillDecidesThePivot() {
        var checked = 0
        for name in ["F", "y", "M_O", "W", "T"] {
            let c = VectorSceneController()
            c.update(items: [ColoredDrawable(
                drawable: Drawable(shape: .point(Vec3(0, 0, 0)), label: name), colorIndex: 0)],
                arcs: [], showAxes: false, showGrid: false)
            func walk(_ n: SCNNode) {
                if let t = n.geometry as? SCNText {
                    let (lo, hi) = t.boundingBox
                    if lo.x.isFinite, hi.x.isFinite, hi.x >= lo.x {
                        checked += 1
                        #expect(n.pivot.m41 == (lo.x + hi.x) / 2,
                                "\(name): pivot \(n.pivot.m41) vs ink centre \((lo.x + hi.x) / 2)")
                    }
                }
                n.childNodes.forEach(walk)
            }
            walk(c.scene.rootNode)
        }
        #expect(checked > 0)
    }

    // MARK: - Can the app produce an empty label at all?

    /// `Engine.shortLabel` trims a line, strips notation prefixes, and returns
    /// whatever is left — including "" — as a non-nil label. Whether a line can
    /// be BOTH consumed entirely by the prefix stripping AND still parse to a
    /// drawable is the question; this attempts the ones that could.
    @Test func recordWhetherAnyLineProducesAnEmptyLabel() {
        let lines = ["\\vec", "\\vector", "\\vec\\hat", "\\vector\\vec",
                     "\\vector\\vec\\hat", "vec ", "\\vec ", "  \\vec\\hat  ",
                     "\\vec\\hat u", "\\vec u", "vec u", "\\hat u", "u"]
        var empties: [String] = []
        for line in lines {
            for outcome in Engine.evaluate([line]) where outcome.drawable?.label == "" {
                empties.append(line)
            }
        }
        print("PASS17 empty labels from Engine: \(empties)")
        #expect(empties.isEmpty, "these lines produced an empty label: \(empties)")
    }
}
