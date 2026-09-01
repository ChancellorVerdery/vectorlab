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

    // MARK: - Content

    public func update(items: [ColoredDrawable], arcs: [ColoredArc], showAxes: Bool, showGrid: Bool,
                       showArrowheads: Bool = true) {
        var maxCoord = 2.0
        func fold(_ v: Vec3) {
            let c = v.maxAbsComponent
            if c.isFinite { maxCoord = max(maxCoord, c) }
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
        // ponytail: extent capped at 1000 — keeps Int(extent) and the grid loop
        // safe for any input; content beyond that just clips at the far plane
        let newExtent = min(1000, max(5, (maxCoord * 1.2).rounded(.up)))
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

        // Seed label obstacles: axis labels, every arrow tip, every point.
        labelObstacles.removeAll()
        for axis in [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)] {
            labelObstacles.append((axis * (extent * 1.07), labelScale))
        }
        for item in items {
            switch item.drawable.shape {
            case .arrow(let tail, let vec) where vec.length > 1e-9:
                let tipLength = min(0.25 * vec.length, 0.04 * extent + 0.06)
                labelObstacles.append((tail + vec, tipLength + labelScale * 0.3))
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
        node.position = s(tail)
        let length = vec.length

        guard length > 1e-9, let dir = vec.normalized else {
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
        registerScalable(shaftNode, radial: true)

        if showHead {
            let cone = SCNCone(topRadius: 0, bottomRadius: shaftRadius * 2.8, height: tipLength)
            cone.radialSegmentCount = 16
            cone.materials = [material(color)]
            let coneNode = SCNNode(geometry: cone)
            coneNode.position.y = length - tipLength / 2
            aligned.addChildNode(coneNode)
            registerScalable(coneNode, radial: true)
        }
        node.addChildNode(aligned)

        if let label {
            addLabel(label, color: color, to: node, parentOrigin: tail,
                     desired: tail + vec + dir * (labelScale * 1.6), escape: dir,
                     vectorMark: true)
        }
        return node
    }

    private func pointNode(at p: Vec3, color: NSColor, label: String?) -> SCNNode {
        let node = SCNNode()
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
                     desired: p + off * (0.05 * extent), escape: off)
        }
        return node
    }

    // MARK: - Labels

    /// Occupied spots (math coords) that labels must clear: arrow tips,
    /// points, axis labels, and labels already placed this rebuild.
    private var labelObstacles: [(pos: Vec3, radius: Double)] = []

    /// _AB in a name typesets as a true subscript (smaller, lowered, no
    /// underscore) — the editable text can't do this (Unicode has no capital
    /// subscript letters), but attributed SCNText can.
    private func attributedLabel(_ string: String) -> NSAttributedString {
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
                    result.append(NSAttributedString(
                        string: run,
                        attributes: [.font: small, .baselineOffset: -0.22]))
                    idx = j
                    continue
                }
            }
            result.append(NSAttributedString(string: String(string[idx]), attributes: [.font: base]))
            idx = string.index(after: idx)
        }
        return result
    }

    private func makeLabel(_ string: String, color: NSColor, axes: Bool = false,
                           vectorMark: Bool = false) -> (node: SCNNode, halfWidth: Double) {
        let text = SCNText(string: attributedLabel(string), extrusionDepth: 0)
        text.flatness = 0.05
        let m = material(color, constant: true)
        m.readsFromDepthBuffer = false   // labels draw on top, never inside geometry
        text.materials = [m]

        let node = SCNNode(geometry: text)
        node.renderingOrder = 100
        let scale = labelScale
        node.scale = SCNVector3(scale, scale, scale)
        registerScalable(node, radial: false, base: scale, axes: axes)

        // Center the text on its position.
        let (minB, maxB) = text.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
        node.constraints = [SCNBillboardConstraint()]

        if vectorMark {
            // Full-width arrow over the name — proper vector notation.
            let width = CGFloat(maxB.x - minB.x)
            let y = CGFloat(maxB.y) + 0.16
            let barMaterial = material(color, constant: true)
            barMaterial.readsFromDepthBuffer = false

            let bar = SCNBox(width: max(0.2, width - 0.14), height: 0.05, length: 0.01, chamferRadius: 0)
            bar.materials = [barMaterial]
            let barNode = SCNNode(geometry: bar)
            barNode.renderingOrder = 100
            barNode.position = SCNVector3(CGFloat(minB.x) + (width - 0.14) / 2, y, 0)
            node.addChildNode(barNode)

            let head = SCNPyramid(width: 0.14, height: 0.14, length: 0.01)
            head.materials = [barMaterial]
            let headNode = SCNNode(geometry: head)
            headNode.renderingOrder = 100
            headNode.eulerAngles.z = -.pi / 2   // apex points +x
            headNode.position = SCNVector3(CGFloat(maxB.x) - 0.07, y, 0)
            node.addChildNode(headNode)
        }
        return (node, Double(maxB.x - minB.x) / 2 * scale)
    }

    /// Adds a content label at `desired`, nudged along `escape` until it
    /// stops overlapping registered obstacles. Positions are math coords.
    private func addLabel(_ string: String, color: NSColor, to parent: SCNNode,
                          parentOrigin: Vec3, desired: Vec3, escape: Vec3,
                          vectorMark: Bool = false) {
        let (node, halfWidth) = makeLabel(string, color: color, vectorMark: vectorMark)
        let radius = max(halfWidth, labelScale * 0.6)
        let dir = escape.normalized ?? Vec3(0, 0, 1)
        var pos = desired
        var attempts = 0
        while attempts < 10,
              labelObstacles.contains(where: { ($0.pos - pos).length < ($0.radius + radius) * 0.9 }) {
            pos = pos + dir * (labelScale * 0.9)
            attempts += 1
        }
        labelObstacles.append((pos, radius))
        node.position = s(pos - parentOrigin)
        parent.addChildNode(node)
    }

    private func arcNode(_ arc: ArcSpec, color: NSColor) -> SCNNode? {
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
                 desired: arc.origin + radius * 1.45 * bisector, escape: bisector)
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
        registerScalable(coneNode, radial: true, axes: true)

        node.addChildNode(aligned)
        let (labelNode, _) = makeLabel(label, color: color, axes: true)
        labelNode.position = s(dir * (e * 1.07))
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
