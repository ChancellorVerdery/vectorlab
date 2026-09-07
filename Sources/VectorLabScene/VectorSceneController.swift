import AppKit
import SceneKit
import simd
import VectorLabCore

/// Owns the SCNScene: content (arrows, points, arcs), axes, grid, camera.
/// Math convention is z-up; SceneKit is y-up. We map with the cyclic
/// permutation (x, y, z) → (y, z, x), a proper rotation (det +1), so
/// handedness — and therefore cross-product direction — renders correctly.
public final class VectorSceneController {
    public let scene = SCNScene()
    public let cameraNode = SCNNode()

    private let contentNode = SCNNode()
    private let axesNode = SCNNode()
    private let gridNode = SCNNode()
    private var extent: Double = 5

    /// Nodes whose girth/size should track camera distance so arrows stay
    /// slim on screen at any zoom. radial = scale x/z only (keeps length).
    private struct Scalable {
        let node: SCNNode
        let radial: Bool
        let base: Double
    }
    private var contentScalables: [Scalable] = []
    private var axesScalables: [Scalable] = []
    private var screenFactor: Double = 1

    /// Arrow shaft+tip pairs whose geometry is rebuilt on zoom so the tip's
    /// LENGTH shrinks with its girth (radial-only scaling makes needles) and
    /// the shaft always meets the cone base.
    private struct ArrowTip {
        let cone: SCNCone
        let coneNode: SCNNode
        let shaft: SCNCylinder
        let shaftNode: SCNNode
        let length: Double
        let baseTip: Double
        let baseRadius: Double
    }
    private var arrowTips: [ArrowTip] = []

    public init() {
        scene.background.contents = NSColor(red: 0.075, green: 0.085, blue: 0.12, alpha: 1)

        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 4000
        cameraNode.camera = camera

        scene.rootNode.addChildNode(contentNode)
        scene.rootNode.addChildNode(axesNode)
        scene.rootNode.addChildNode(gridNode)
        scene.rootNode.addChildNode(cameraNode)

        rebuildAxesAndGrid()
        apply(preset: .iso, animated: false)
    }

    // MARK: - Coordinate mapping (math z-up → SceneKit y-up)

    private func s(_ v: Vec3) -> SCNVector3 { SCNVector3(v.y, v.z, v.x) }

    /// SceneKit keeps node transforms as 32-bit floats, so ANY coordinate past
    /// Float.greatestFiniteMagnitude (~3.4e38) reads back as ∞ however good the
    /// Double we hand it was — ∞ positions, ∞ shaft heights, NaN orientations.
    ///
    /// Pass 1 shut this off for arrows with `length.isFinite`, but that only
    /// worked by accident: |<1e200, 1e200, 0>| itself overflowed to ∞ first.
    /// With an overflow-safe Vec3.length that length is now a real 1.4e200, so
    /// the arrow sailed past the guard and rebuilt the infinite geometry. The
    /// bound the renderer actually has is stated here instead of relied upon.
    private static let maxRenderable = Double(Float.greatestFiniteMagnitude)

    private static func isRenderable(_ v: Vec3) -> Bool {
        v.isFinite && v.maxAbsComponent <= maxRenderable
    }

    // MARK: - Content

    public func update(items: [ColoredDrawable], arcs: [ColoredArc], showAxes: Bool, showGrid: Bool,
                       showArrowheads: Bool = true) {
        var maxCoord = 2.0
        // Only geometry that will actually be DRAWN may grow the viewport.
        // `isFinite` alone let a point at 1e200 — finite, so Engine.drawable
        // emits it — pin extent to its 1000 cap while pointNode declined to
        // draw it: axes 1000 units long, nothing at the far end, and the
        // user's real <3, 4, 0> vector shrunk to invisibility. isRenderable is
        // the same predicate the node builders use.
        func fold(_ v: Vec3) {
            if Self.isRenderable(v) { maxCoord = max(maxCoord, v.maxAbsComponent) }
        }
        for item in items {
            switch item.drawable.shape {
            case .arrow(let tail, let vec):
                fold(tail)
                fold(tail + vec)
            case .point(let p):
                fold(p)
            }
        }
        // Arcs were left out entirely, so an arc anchored further out than
        // every arrow was drawn outside the axes. Its radius is already capped
        // by extent, so the origin is the whole reach.
        for colored in arcs {
            fold(colored.arc.origin)
        }
        // Axes: 5 units minimum, exactly 20% beyond the largest component,
        // identical length on x, y, z. Capped at 1000 — keeps Int(extent)
        // and the grid loop safe for any input; beyond that content clips.
        let newExtent = min(1000, max(5, maxCoord * 1.2))
        if newExtent != extent {
            extent = newExtent
            rebuildAxesAndGrid()
            cameraNode.camera?.zFar = max(4000, extent * 8)
            fit()   // re-frame so a big moment vector doesn't bury the camera
        }
        axesNode.isHidden = !showAxes
        gridNode.isHidden = !showGrid

        // ponytail: full rebuild per edit; diff nodes only if scenes ever get huge
        contentNode.childNodes.forEach { $0.removeFromParentNode() }
        contentScalables.removeAll()
        arrowTips.removeAll()

        // Seed label obstacles: axis labels, every arrow tip, every point.
        labelObstacles.removeAll()
        for axis in [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)] {
            labelObstacles.append((axis * (extent * 1.07), labelScale))
        }
        for item in items {
            switch item.drawable.shape {
            case .arrow(let tail, let vec) where vec.length > 1e-9:
                let tipLength = min(0.25 * vec.length, 0.04 * extent + 0.06)
                labelObstacles.append((tail + vec, tipLength * 0.7 + labelScale * 0.2))
            case .arrow(let tail, _):
                labelObstacles.append((tail, labelScale * 0.5))
            case .point(let p):
                labelObstacles.append((p, 0.009 * extent + 0.02 + labelScale * 0.3))
            }
        }

        for item in items {
            let color = Palette.color(item.colorIndex)
            switch item.drawable.shape {
            case .arrow(let tail, let vec):
                contentNode.addChildNode(arrowNode(tail: tail, vec: vec, color: color,
                                                   label: item.drawable.label, showHead: showArrowheads))
            case .point(let p):
                contentNode.addChildNode(pointNode(at: p, color: color, label: item.drawable.label))
            }
        }
        for colored in arcs {
            if let node = arcNode(colored.arc, color: Palette.color(colored.colorIndex)) {
                contentNode.addChildNode(node)
            }
        }
        applyScreenScale()   // new nodes match the current zoom immediately
    }

    /// Called every frame with the live camera position: rescales girth and
    /// labels so they look constant-size on screen instead of clunky up close.
    public func updateScreenScale(cameraPosition p: SCNVector3) {
        let d = (Double(p.x) * Double(p.x) + Double(p.y) * Double(p.y) + Double(p.z) * Double(p.z)).squareRoot()
        guard d.isFinite, d > 0 else { return }
        let factor = min(3.0, max(0.15, d / (extent * 2.9)))   // 1.0 at preset distance
        guard abs(factor - screenFactor) > screenFactor * 0.03 else { return }
        screenFactor = factor
        applyScreenScale()
    }

    private func applyScreenScale() {
        let f = screenFactor
        for s in contentScalables + axesScalables {
            if s.radial {
                s.node.scale = SCNVector3(f, 1, f)
            } else {
                let b = s.base * f
                s.node.scale = SCNVector3(b, b, b)
            }
        }
        for t in arrowTips {
            let tip = min(t.baseTip * f, 0.3 * t.length)
            let radius = t.baseRadius * f
            t.shaft.radius = radius
            t.shaft.height = max(0.001, t.length - tip)
            t.shaftNode.position.y = (t.length - tip) / 2
            t.cone.height = tip
            t.cone.bottomRadius = radius * 2.8
            t.coneNode.position.y = t.length - tip / 2
        }
    }

    // MARK: - Camera

    public func apply(preset: CameraPreset, animated: Bool = true) {
        let d = extent * 2.9
        let position: Vec3
        let up: Vec3
        switch preset {
        case .iso:
            position = Vec3(1.05, 0.85, 0.65).normalized! * d
            up = Vec3(0, 0, 1)
        case .top:   // looking down math +z: the XY plane, x right, y up-screen
            position = Vec3(0, 0, 1) * d
            up = Vec3(0, 1, 0)
        case .front: // looking along math +y: the XZ plane, x right, z up
            position = Vec3(0, -1, 0) * d
            up = Vec3(0, 0, 1)
        case .side:  // looking along math −x: the YZ plane, y right, z up
            position = Vec3(1, 0, 0) * d
            up = Vec3(0, 0, 1)
        }
        withTransaction(animated: animated) {
            cameraNode.position = s(position)
            cameraNode.look(at: SCNVector3(0, 0, 0), up: s(up), localFront: SCNVector3(0, 0, -1))
        }
    }

    /// Keeps the current view direction, resets distance to frame the content.
    public func fit() {
        let p = simd_double3(Double(cameraNode.position.x), Double(cameraNode.position.y), Double(cameraNode.position.z))
        let len = simd_length(p)
        guard len > 1e-6 else { return }
        let target = p / len * (extent * 2.9)
        withTransaction(animated: true) {
            cameraNode.position = SCNVector3(target.x, target.y, target.z)
        }
    }

    private func withTransaction(animated: Bool, _ body: () -> Void) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.35 : 0
        body()
        SCNTransaction.commit()
    }

    // MARK: - Node builders

    private var labelScale: Double { max(0.15, extent * 0.028) }

    /// The one vertical datum every label is placed against: the baseline and
    /// cap top of this font at the size `attributedLabel` uses.
    ///
    /// `makeLabel` used to pivot each label on the midpoint of ITS OWN ink box
    /// and hang the arrow/hat mark off ITS OWN ink top. Both quantities depend
    /// on which glyphs the name happens to contain, so a label's height above
    /// its anchor point was a function of its spelling. Measured pivot y, one
    /// label each: `F` 1.3523, `j` 1.3195, `r_AB` 1.2744, `y` 1.1714 — a spread
    /// of 0.18 text units, about a quarter of a cap height, between names that
    /// are drawn at the same size on the same point. The axis labels show it
    /// plainly: `x` has no descender and `y` does, so the two ticks of a pair
    /// sat at different heights. Marks drifted the same way, riding 0.26 lower
    /// over `r_AB` (ink top 1.5487) than over `j` (1.8084).
    ///
    /// Text shares a baseline; it does not share a bounding-box centre. So both
    /// now measure one reference capital instead. `F` has no descender and no
    /// ascender above the cap line, so its ink bottom IS the baseline and its
    /// ink top IS the cap height — a constant of the font, not of the string.
    ///
    /// This is a real move: every label whose glyphs are not exactly cap-band
    /// shifts. `F` itself does not move by a single bit, because for a lone
    /// capital the new datum IS the old ink box, and that is the point — the
    /// change aligns the others TO the ordinary case rather than relocating it.
    ///
    /// Horizontal placement is untouched: centring on the ink box is correct
    /// for x, where the whole string's extent is what should be centred.
    private static let labelDatum: (baseline: CGFloat, capTop: CGFloat) = {
        let probe = SCNText(string: attributedLabel("F"), extrusionDepth: 0)
        probe.flatness = 0.05
        let (lo, hi) = probe.boundingBox
        return (CGFloat(lo.y), CGFloat(hi.y))
    }()

    private func registerScalable(_ node: SCNNode, radial: Bool, base: Double = 1, axes: Bool = false) {
        if axes {
            axesScalables.append(Scalable(node: node, radial: radial, base: base))
        } else {
            contentScalables.append(Scalable(node: node, radial: radial, base: base))
        }
    }

    private func material(_ color: NSColor, constant: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        if constant { m.lightingModel = .constant }
        m.emission.contents = color.withAlphaComponent(0.35)
        return m
    }

    private func orient(_ node: SCNNode, along dir: Vec3) {
        // Rotate local +Y onto the scene-space direction.
        let sceneDir = simd_normalize(simd_double3(dir.y, dir.z, dir.x))
        let from = simd_double3(0, 1, 0)
        let dot = simd_dot(from, sceneDir)
        if dot < -0.999999 {
            node.simdOrientation = simd_quatf(angle: .pi, axis: simd_float3(1, 0, 0))
        } else {
            let q = simd_quatd(from: from, to: sceneDir)
            node.simdOrientation = simd_quatf(vector: simd_float4(q.vector))
        }
    }

    private func arrowNode(tail: Vec3, vec: Vec3, color: NSColor, label: String?, showHead: Bool) -> SCNNode {
        let node = SCNNode()
        // An unrenderable tail cannot be placed at all — anywhere we put it is
        // ∞ — so the whole arrow is dropped rather than drawn in the wrong spot.
        guard Self.isRenderable(tail) else { return node }
        node.position = s(tail)
        let length = vec.length

        // Beyond Float range the shaft height and tip position come back ∞;
        // see maxRenderable. Values this large already clipped out of the
        // scene, so nothing that was previously visible stops being drawn.
        guard length > 1e-9, length <= Self.maxRenderable, Self.isRenderable(vec),
              let dir = vec.normalized else {
            // Zero vector: a small marker at the tail so M = 0 still shows up.
            let g = SCNSphere(radius: 0.03 * labelScale + 0.03)
            g.materials = [material(color)]
            let marker = SCNNode(geometry: g)
            node.addChildNode(marker)
            registerScalable(marker, radial: false)
            if let label {
                addLabel(label, color: color, to: node, parentOrigin: tail,
                         desired: tail + Vec3(0, 0, 0.25), escape: Vec3(0, 0, 1))
            }
            return node
        }

        let tipLength = showHead ? min(0.25 * length, 0.04 * extent + 0.06) : 0
        let shaftRadius = 0.003 * extent

        let aligned = SCNNode()
        orient(aligned, along: dir)

        let shaft = SCNCylinder(radius: shaftRadius, height: length - tipLength)
        shaft.radialSegmentCount = 16
        shaft.materials = [material(color)]
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position.y = (length - tipLength) / 2
        aligned.addChildNode(shaftNode)

        if showHead {
            let cone = SCNCone(topRadius: 0, bottomRadius: shaftRadius * 2.8, height: tipLength)
            cone.radialSegmentCount = 16
            cone.materials = [material(color)]
            let coneNode = SCNNode(geometry: cone)
            coneNode.position.y = length - tipLength / 2
            aligned.addChildNode(coneNode)
            // Whole-tip zoom scaling (length + girth together, shaft follows).
            arrowTips.append(ArrowTip(cone: cone, coneNode: coneNode,
                                      shaft: shaft, shaftNode: shaftNode,
                                      length: length, baseTip: tipLength,
                                      baseRadius: shaftRadius))
        } else {
            registerScalable(shaftNode, radial: true)
        }
        node.addChildNode(aligned)

        if let label {
            // Unit vectors wear a hat, everything else the arrow — matches
            // the notebook's automatic notation.
            let mark: LabelMark = abs(length - 1) <= 1e-6 ? .hat : .arrow
            addLabel(label, color: color, to: node, parentOrigin: tail,
                     desired: tail + vec + dir * (labelScale * 0.8), escape: dir,
                     mark: mark)
        }
        return node
    }

    private func pointNode(at p: Vec3, color: NSColor, label: String?) -> SCNNode {
        let node = SCNNode()
        // Same Float bound as arrows: a point at 1e200 reads back at ∞.
        guard Self.isRenderable(p) else { return node }
        node.position = s(p)
        let g = SCNSphere(radius: 0.009 * extent + 0.02)
        g.segmentCount = 24
        g.materials = [material(color)]
        let sphere = SCNNode(geometry: g)
        node.addChildNode(sphere)
        registerScalable(sphere, radial: false)
        if let label {
            let off = Vec3(0.55, 0, 0.83)
            addLabel(label, color: color, to: node, parentOrigin: p,
                     desired: p + off * (0.03 * extent), escape: off)
        }
        return node
    }

    // MARK: - Labels

    /// Occupied spots (math coords) that labels must clear: arrow tips,
    /// points, axis labels, and labels already placed this rebuild.
    private var labelObstacles: [(pos: Vec3, radius: Double)] = []

    /// `_AB` in a name typesets as a subscript: smaller, no underscore. The
    /// editable text can't do this at all (Unicode has no capital subscript
    /// letters), but an attributed SCNText can size a run.
    ///
    /// It CANNOT lower one. This carried `.baselineOffset: -0.22` from the day
    /// it was written; the attribute never did anything. SCNText lays every run
    /// of an attributed string on one baseline and ignores all four vertical
    /// mechanisms — `NSBaselineOffset`, CoreText's own `CTBaselineOffset` key,
    /// `CTSuperscript`, and a translating font matrix. Measured: `F` + a 0.62
    /// run reading `1` occupies y = [1.0000, 1.7046] with the offset, without
    /// it, and at every offset from 0 to -0.5. See Pass15Tests, which pins the
    /// no-op so that if SceneKit ever gains the support the pin fails loudly
    /// and a real lowered subscript can be put back.
    ///
    /// The output is nonetheless right, because this font's own designed
    /// subscript glyph also sits on the baseline: `₁` alone measures
    /// y = [1.0005, 1.4082] and w = 0.3164, against y = [1.0000, 1.4368] and
    /// w = 0.3106 for the 0.62 run. The eyeballed 0.62 lands within 2% of the
    /// font's subscript on width and 7% on height — and no single size can hit
    /// both, since those two targets disagree with each other by more than 0.62
    /// misses either. So 0.62 stays; it was measured, not merely kept.
    private static func attributedLabel(_ string: String) -> NSAttributedString {
        let base = NSFont.monospacedSystemFont(ofSize: 1, weight: .semibold)
        let small = NSFont.monospacedSystemFont(ofSize: 0.62, weight: .semibold)
        let result = NSMutableAttributedString()
        var idx = string.startIndex
        while idx < string.endIndex {
            if string[idx] == "_" {
                var j = string.index(after: idx)
                var run = ""
                while j < string.endIndex, string[j].isLetter || string[j].isNumber {
                    run.append(string[j])
                    j = string.index(after: j)
                }
                if !run.isEmpty {
                    result.append(NSAttributedString(string: run, attributes: [.font: small]))
                    idx = j
                    continue
                }
            }
            result.append(NSAttributedString(string: String(string[idx]), attributes: [.font: base]))
            idx = string.index(after: idx)
        }
        return result
    }

    enum LabelMark {
        case arrow   // full-width vector arrow over the name
        case hat     // centered ^ for unit vectors
    }

    /// `SCNText.boundingBox` does not always answer with a measurement. When
    /// the geometry has no laid-out glyphs it returns SceneKit's empty-box
    /// sentinel — `(+inf, -inf)`, the identity element for box union, not a
    /// size. Pass 16 caught it on a re-read and could not say whether
    /// `makeLabel`'s own read was exposed. Pass 17 measured it:
    ///
    /// - It happens to ORDINARY NAMES. `A` read back as the sentinel on 40 of
    ///   40 fresh reads, `r_AB` on 37–40 of 40 — and `r_AB` is in the app's own
    ///   sample notebook.
    /// - It happens at EVERY construction stage `makeLabel` performs. Fresh
    ///   text, materials assigned, node attached, both: all four stages read
    ///   the sentinel for the same two names.
    /// - It is STICKY per object. A sentinel read stays a sentinel; nothing
    ///   done afterwards recovered one (0 of 18).
    /// - It is not a race. `SCNText` is main-actor isolated and non-Sendable,
    ///   so the app cannot lay out two of these concurrently.
    /// - It is not the empty string, which measures an honest `(0, 0)`.
    ///
    /// See `Pass17Tests.recordWhichNamesReadBackAsTheSentinel` and
    /// `recordWhichConstructionStepMakesTheBoxReadable` for the raw numbers.
    ///
    /// The old code used the read raw: `(minB.x + maxB.x) / 2` is
    /// `(+inf + -inf) / 2` — NaN. A NaN pivot is not a label in the wrong place,
    /// it is a node with no transform, and nothing downstream checks for it.
    /// The vertical half of the same problem was closed in pass 16 by moving
    /// the datum into a `static let`; this is the other half.
    ///
    /// A finite box is returned unchanged, so every label whose box reads
    /// cleanly keeps the coordinates it has always had, bit for bit. Otherwise
    /// CoreText's typographic advance stands in: it comes from the text system
    /// rather than SceneKit's geometry builder, so it cannot be the sentinel.
    /// It is a DIFFERENT number, not a substitute — the advance is the
    /// monospace cell and the ink box is the glyph inside it, so it runs from
    /// 1.00x (`W`, which fills its cell) to 1.68x (`j`). For `A` it is 1.04x.
    /// That is why it is a fallback: it keeps a label finite and near-centred,
    /// it does not reproduce the measurement. See
    /// `Pass17Tests.theTypographicAdvanceBoundsTheInkBox`.
    private static func inkSpanX(_ text: SCNText,
                                 of attributed: NSAttributedString) -> (min: CGFloat, max: CGFloat) {
        let (lo, hi) = text.boundingBox
        if lo.x.isFinite, hi.x.isFinite, hi.x >= lo.x { return (lo.x, hi.x) }
        return (0, attributed.size().width)
    }

    private func makeLabel(_ string: String, color: NSColor, axes: Bool = false,
                           mark: LabelMark? = nil) -> (node: SCNNode, halfWidth: Double) {
        let attributed = Self.attributedLabel(string)
        let text = SCNText(string: attributed, extrusionDepth: 0)
        text.flatness = 0.05
        let m = material(color, constant: true)
        m.readsFromDepthBuffer = false   // labels draw on top, never inside geometry
        text.materials = [m]

        let node = SCNNode(geometry: text)
        node.renderingOrder = 100
        let scale = labelScale
        node.scale = SCNVector3(scale, scale, scale)
        registerScalable(node, radial: false, base: scale, axes: axes)

        // Centre horizontally on the ink box; vertically on the font's cap
        // band, so every label sits at one height regardless of its glyphs.
        let spanX = Self.inkSpanX(text, of: attributed)
        let datum = Self.labelDatum
        node.pivot = SCNMatrix4MakeTranslation(
            (spanX.min + spanX.max) / 2, (datum.baseline + datum.capTop) / 2, 0)
        node.constraints = [SCNBillboardConstraint()]

        if let mark {
            let width = spanX.max - spanX.min
            let y = Self.labelDatum.capTop + 0.3
            let cx = (spanX.min + spanX.max) / 2
            let markMaterial = material(color, constant: true)
            markMaterial.readsFromDepthBuffer = false

            switch mark {
            case .arrow:
                // Full-width arrow over the name — proper vector notation.
                //
                // Bar and head are ONE stroke, so both come from one span. They
                // used to be sized and placed independently: the bar was BUILT
                // `max(0.2, width - 0.14)` wide but POSITIONED as if it were
                // `width - 0.14` wide. Those agree only while the clamp is
                // asleep. When it fires the bar keeps the unclamped centre and
                // overruns the head by exactly the clamp's excess — the two
                // stop being one arrow. A minimum width should widen the whole
                // mark, not desynchronise half of it.
                //
                // Reachable only for a name narrower than 0.34 in text units,
                // which in this monospaced font means no letter and no digit —
                // see Pass14Tests.recordMeasuredLabelWidths. Latent, therefore,
                // but wrong: for every name at or above that width the span IS
                // the width and both nodes land on exactly the coordinates they
                // always had, bit for bit.
                let headLength: CGFloat = 0.14
                let minBar: CGFloat = 0.2
                let span = max(headLength + minBar, width)
                let left = cx - span / 2
                let barWidth = span - headLength

                let bar = SCNBox(width: barWidth, height: 0.05, length: 0.01, chamferRadius: 0)
                bar.materials = [markMaterial]
                let barNode = SCNNode(geometry: bar)
                barNode.renderingOrder = 100
                barNode.position = SCNVector3(left + barWidth / 2, y, 0)
                node.addChildNode(barNode)

                let head = SCNPyramid(width: headLength, height: headLength, length: 0.01)
                head.materials = [markMaterial]
                let headNode = SCNNode(geometry: head)
                headNode.renderingOrder = 100
                headNode.eulerAngles.z = -.pi / 2   // apex points +x
                headNode.position = SCNVector3(left + span - headLength / 2, y, 0)
                node.addChildNode(headNode)

            case .hat:
                // Centered ^ — unit-vector notation.
                for side in [-1.0, 1.0] {
                    let bar = SCNBox(width: 0.26, height: 0.05, length: 0.01, chamferRadius: 0)
                    bar.materials = [markMaterial]
                    let barNode = SCNNode(geometry: bar)
                    barNode.renderingOrder = 100
                    // NEGATIVE side: a caret's arms RISE toward the middle.
                    // With +side the left arm (side = -1) was rotated clockwise
                    // and the right arm counter-clockwise, so both inner ends
                    // went DOWN and the mark rendered as a v. Measured before
                    // the fix: inner ends at y 1.7560, outer ends at y 1.9133 —
                    // the apex was 0.157 BELOW the tips. Every unit vector in
                    // the app wears this mark, and thirteen passes never asked
                    // which way up it was.
                    barNode.eulerAngles.z = CGFloat(-side) * 0.65
                    barNode.position = SCNVector3(cx + CGFloat(side) * 0.1, y, 0)
                    node.addChildNode(barNode)
                }
            }
        }
        return (node, Double(spanX.max - spanX.min) / 2 * scale)
    }

    /// Adds a content label at `desired`, nudged along `escape` until it
    /// stops overlapping registered obstacles. Positions are math coords.
    private func addLabel(_ string: String, color: NSColor, to parent: SCNNode,
                          parentOrigin: Vec3, desired: Vec3, escape: Vec3,
                          mark: LabelMark? = nil) {
        let (node, halfWidth) = makeLabel(string, color: color, mark: mark)
        let radius = max(halfWidth, labelScale * 0.6)
        let dir = escape.normalized ?? Vec3(0, 0, 1)
        var pos = desired
        var attempts = 0
        while attempts < 10,
              labelObstacles.contains(where: { ($0.pos - pos).length < ($0.radius + radius) * 0.72 }) {
            pos = pos + dir * (labelScale * 0.6)
            attempts += 1
        }
        labelObstacles.append((pos, radius))
        node.position = s(pos - parentOrigin)
        parent.addChildNode(node)
    }

    private func arcNode(_ arc: ArcSpec, color: NSColor) -> SCNNode? {
        // Same 32-bit vertex bound arrows and points already respect. Every arc
        // vertex is `origin + radius * unit`, so a non-renderable origin puts all
        // 33 of them at ∞ no matter how small the radius is; a non-renderable leg
        // makes the two basis directions NaN. Arc origins come from a shared point
        // anchor, so `point A = (1e200, 0, 0)` reaches here directly.
        guard Self.isRenderable(arc.origin), Self.isRenderable(arc.from),
              Self.isRenderable(arc.to), arc.degrees.isFinite
        else { return nil }
        guard let ua = arc.from.normalized else { return nil }
        let perp = arc.to - arc.to.dot(ua) * ua
        guard let w = perp.normalized else { return nil }   // parallel vectors: no arc

        let radius = min(0.28 * min(arc.from.length, arc.to.length), 0.35 * extent)
        guard radius > 1e-6 else { return nil }
        let theta = arc.degrees * .pi / 180
        let segments = 32

        var vertices: [SCNVector3] = []
        for n in 0...segments {
            let t = theta * Double(n) / Double(segments)
            let p = arc.origin + radius * (cos(t) * ua + sin(t) * w)
            vertices.append(s(p))
        }
        var indices: [Int32] = []
        for n in 0..<segments {
            indices.append(Int32(n))
            indices.append(Int32(n + 1))
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [material(color, constant: true)]

        let node = SCNNode(geometry: geometry)
        let mid = theta / 2
        let bisector = cos(mid) * ua + sin(mid) * w
        addLabel(Fmt.num(arc.degrees) + "°", color: color, to: node, parentOrigin: .zero,
                 desired: arc.origin + radius * 1.2 * bisector, escape: bisector)
        return node
    }

    // MARK: - Axes & grid

    private func rebuildAxesAndGrid() {
        axesNode.childNodes.forEach { $0.removeFromParentNode() }
        gridNode.childNodes.forEach { $0.removeFromParentNode() }
        axesScalables.removeAll()

        let axes: [(Vec3, NSColor, String)] = [
            (Vec3(1, 0, 0), .systemRed, "x"),
            (Vec3(0, 1, 0), .systemGreen, "y"),
            (Vec3(0, 0, 1), NSColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1), "z"),
        ]
        for (dir, color, name) in axes {
            axesNode.addChildNode(axisNode(dir: dir, color: color, label: name))
        }
        gridNode.addChildNode(gridGeometryNode())
    }

    private func axisNode(dir: Vec3, color: NSColor, label: String) -> SCNNode {
        let node = SCNNode()
        let e = extent
        let radius = 0.002 * e

        let aligned = SCNNode()
        orient(aligned, along: dir)

        let shaft = SCNCylinder(radius: radius, height: 2 * e)
        shaft.radialSegmentCount = 12
        shaft.materials = [material(color.withAlphaComponent(0.8))]
        let shaftNode = SCNNode(geometry: shaft)   // centered: spans -e…+e
        aligned.addChildNode(shaftNode)
        registerScalable(shaftNode, radial: true, axes: true)

        let cone = SCNCone(topRadius: 0, bottomRadius: radius * 3.5, height: 0.03 * e)
        cone.materials = [material(color)]
        let coneNode = SCNNode(geometry: cone)
        coneNode.position.y = e
        aligned.addChildNode(coneNode)
        // Uniform scale: axis tips keep their proportions as zoom changes.
        registerScalable(coneNode, radial: false, axes: true)

        node.addChildNode(aligned)
        let (labelNode, _) = makeLabel(label, color: color, axes: true)
        labelNode.position = s(dir * (e * 1.045))
        node.addChildNode(labelNode)
        return node
    }

    private func gridGeometryNode() -> SCNNode {
        let e = Int(extent)
        let step = max(1, e / 20)   // constant line count as extent grows
        var vertices: [SCNVector3] = []
        for i in stride(from: -e, through: e, by: step) {
            let d = Double(i)
            vertices.append(s(Vec3(d, Double(-e), 0)))
            vertices.append(s(Vec3(d, Double(e), 0)))
            vertices.append(s(Vec3(Double(-e), d, 0)))
            vertices.append(s(Vec3(Double(e), d, 0)))
        }
        let indices = (0..<Int32(vertices.count)).map { $0 }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let m = SCNMaterial()
        m.diffuse.contents = NSColor.gray.withAlphaComponent(0.22)
        m.lightingModel = .constant
        geometry.materials = [m]
        return SCNNode(geometry: geometry)
    }
}
