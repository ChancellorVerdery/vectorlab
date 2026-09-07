import AppKit
import SceneKit
import Testing
import VectorLabCore
@testable import VectorLabScene

/// Pass 14 — the vector-arrow mark drawn over a label name.
///
/// `makeLabel` builds the mark from the SCNText bounding box: a bar plus a
/// pyramid head. Its bar is created with `max(0.2, width - 0.14)` but POSITIONED
/// as if the width were `width - 0.14`. The two agree only while the clamp is
/// inactive. Nothing in the suite ever asked where the bar actually lands, so
/// nothing noticed. These tests ask the scene graph, not the source.
@Suite struct Pass14Tests {

    /// The bar (SCNBox) and head (SCNPyramid) hanging off a label's SCNText node.
    struct Mark {
        var textMin: Double
        var textMax: Double
        var barCenter: Double
        var barWidth: Double
        var headCenter: Double
        var headWidth: Double

        var barLeft: Double { barCenter - barWidth / 2 }
        var barRight: Double { barCenter + barWidth / 2 }
        var headLeft: Double { headCenter - headWidth / 2 }
        var headRight: Double { headCenter + headWidth / 2 }
        var textCenter: Double { (textMin + textMax) / 2 }
        var textWidth: Double { textMax - textMin }
    }

    /// Builds one arrow with `label`, then reads the mark straight out of the
    /// scene graph. Nothing here recomputes the app's arithmetic.
    static func mark(for label: String, vector: Vec3 = Vec3(3, 0, 0)) -> Mark? {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: vector), label: label),
                colorIndex: 0)],
            arcs: [], showAxes: false, showGrid: false)

        var found: Mark?
        func walk(_ n: SCNNode) {
            if let text = n.geometry as? SCNText {
                var bar: (Double, Double)?
                var head: (Double, Double)?
                for c in n.childNodes {
                    if let b = c.geometry as? SCNBox {
                        bar = (Double(c.position.x), Double(b.width))
                    } else if let p = c.geometry as? SCNPyramid {
                        head = (Double(c.position.x), Double(p.width))
                    }
                }
                if let bar, let head {
                    let (lo, hi) = text.boundingBox
                    found = Mark(textMin: Double(lo.x), textMax: Double(hi.x),
                                 barCenter: bar.0, barWidth: bar.1,
                                 headCenter: head.0, headWidth: head.1)
                }
            }
            n.childNodes.forEach(walk)
        }
        walk(controller.scene.rootNode)
        return found
    }

    /// Labels that actually reach an arrow mark in this app: single names,
    /// subscripted names, and the short source lines `Engine.shortLabel` emits.
    static let corpus = [
        "l", "i", "j", "I", "t", "f", "r", "F", "M", "W", "1", ".", "'",
        "F_1", "M_O", "r_AB", "T", "v", "a", "N_1", "2i", "<1,2,3>", "F+G",
    ]

    /// The bar's right edge must be the head's left edge: they are one arrow.
    @Test func theBarMeetsTheHead() {
        for label in Self.corpus {
            guard let m = Self.mark(for: label) else { continue }
            #expect(abs(m.barRight - m.headLeft) < 1e-4,
                    "\(label): bar ends at \(m.barRight), head starts at \(m.headLeft), text width \(m.textWidth)")
        }
    }

    /// The whole mark must be centered over the name it marks.
    @Test func theMarkIsCenteredOnTheName() {
        for label in Self.corpus {
            guard let m = Self.mark(for: label) else { continue }
            let markCenter = (m.barLeft + m.headRight) / 2
            #expect(abs(markCenter - m.textCenter) < 1e-4,
                    "\(label): mark centered at \(markCenter), name at \(m.textCenter), text width \(m.textWidth)")
        }
    }

    /// The mark can never be narrower than its own head.
    @Test func theMarkIsNeverNarrowerThanItsHead() {
        for label in Self.corpus {
            guard let m = Self.mark(for: label) else { continue }
            #expect(m.headRight - m.barLeft >= m.headWidth - 1e-9,
                    "\(label): whole mark spans \(m.headRight - m.barLeft), head alone is \(m.headWidth)")
        }
    }

    /// Diagnostic: prints every corpus label's measured text width, so which
    /// labels trip the 0.2 clamp is recorded rather than assumed.
    @Test func recordMeasuredLabelWidths() {
        for label in Self.corpus {
            guard let m = Self.mark(for: label) else {
                print("WIDTH \(label): no mark")
                continue
            }
            print(String(format: "WIDTH %@ textWidth=%.6f barWidth=%.6f barCenter=%.6f headCenter=%.6f clamped=%@",
                         label, m.textWidth, m.barWidth, m.barCenter, m.headCenter,
                         (m.textWidth - 0.14) < 0.2 ? "YES" : "no"))
        }
    }

    // MARK: - The unit-vector hat

    /// One arm of the ^ drawn over a unit vector's name.
    struct HatArm {
        var centerX: Double
        var y: Double
        var angle: Double
        var halfLength: Double

        /// Endpoint at local +x, rotated about the arm's own centre.
        var plusEnd: (x: Double, y: Double) {
            (centerX + halfLength * cos(angle), y + halfLength * sin(angle))
        }
        var minusEnd: (x: Double, y: Double) {
            (centerX - halfLength * cos(angle), y - halfLength * sin(angle))
        }
    }

    /// A vector of length exactly 1 gets `.hat`, so this reads the two arms
    /// of the ^ straight out of the scene graph.
    static func hatArms(for label: String) -> [HatArm]? {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(1, 0, 0)), label: label),
                colorIndex: 0)],
            arcs: [], showAxes: false, showGrid: false)

        var found: [HatArm]?
        func walk(_ n: SCNNode) {
            if n.geometry is SCNText {
                var arms: [HatArm] = []
                for c in n.childNodes {
                    if let b = c.geometry as? SCNBox {
                        arms.append(HatArm(centerX: Double(c.position.x), y: Double(c.position.y),
                                           angle: Double(c.eulerAngles.z), halfLength: Double(b.width) / 2))
                    }
                }
                if arms.count == 2 { found = arms }
            }
            n.childNodes.forEach(walk)
        }
        walk(controller.scene.rootNode)
        return found
    }

    /// A hat is a ^. The two arms meet in the MIDDLE, and that meeting point
    /// is the highest part of the mark — that is what makes it a caret rather
    /// than a check or a v. Every unit vector in the app wears this mark, and
    /// no pass has ever asked which way up it is.
    @Test func theUnitHatPointsUp() {
        guard let arms = Self.hatArms(for: "u") else {
            Issue.record("no hat mark was built for a unit vector")
            return
        }
        let left = arms.min(by: { $0.centerX < $1.centerX })!
        let right = arms.max(by: { $0.centerX < $1.centerX })!

        // Inner = the endpoint nearer the other arm; outer = the far one.
        let leftInner = left.plusEnd, leftOuter = left.minusEnd
        let rightInner = right.minusEnd, rightOuter = right.plusEnd

        let li: Double = leftInner.y, lo: Double = leftOuter.y
        let ri: Double = rightInner.y, ro: Double = rightOuter.y
        #expect(li > lo + 1e-6, "left arm falls toward the centre: inner y \(li), outer y \(lo)")
        #expect(ri > ro + 1e-6, "right arm falls toward the centre: inner y \(ri), outer y \(ro)")
    }

    /// The two arms must actually meet: a ^ is one stroke bent in the middle,
    /// not two floating dashes.
    @Test func theHatArmsMeetAtTheApex() {
        guard let arms = Self.hatArms(for: "u") else {
            Issue.record("no hat mark was built for a unit vector")
            return
        }
        let left = arms.min(by: { $0.centerX < $1.centerX })!
        let right = arms.max(by: { $0.centerX < $1.centerX })!
        let li: Double = left.plusEnd.y, ri: Double = right.minusEnd.y
        #expect(abs(li - ri) < 0.05, "arm ends do not meet: left inner y \(li), right inner y \(ri)")
    }

    /// The hat is centred over the name, like the arrow mark is.
    @Test func theHatIsCentredOnTheName() {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(1, 0, 0)), label: "u"),
                colorIndex: 0)],
            arcs: [], showAxes: false, showGrid: false)
        var checked = false
        func walk(_ n: SCNNode) {
            if let text = n.geometry as? SCNText {
                let boxes = n.childNodes.compactMap { $0.geometry as? SCNBox }
                if boxes.count == 2 {
                    let (lo, hi) = text.boundingBox
                    let cx = Double(lo.x + hi.x) / 2
                    let mid = n.childNodes.filter { $0.geometry is SCNBox }
                        .map { Double($0.position.x) }.reduce(0, +) / 2
                    #expect(abs(mid - cx) < 1e-4, "hat centred at \(mid), name at \(cx)")
                    checked = true
                }
            }
            n.childNodes.forEach(walk)
        }
        walk(controller.scene.rootNode)
        #expect(checked, "never found a hat mark to check")
    }
}
