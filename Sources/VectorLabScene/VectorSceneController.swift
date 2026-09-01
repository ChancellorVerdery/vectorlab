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

    public func update(items: [ColoredDrawable], arcs: [ColoredArc], showAxes: Bool, showGrid: Bool) {
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
        for item in items {
            let color = Palette.color(item.colorIndex)
            switch item.drawable.shape {
            case .arrow(let tail, let vec):
                contentNode.addChildNode(arrowNode(tail: tail, vec: vec, color: color, label: item.drawable.label))
            case .point(let p):
                contentNode.addChildNode(pointNode(at: p, color: color, label: item.drawable.label))
            }
        }
        for colored in arcs {
            if let node = arcNode(colored.arc, color: Palette.color(colored.colorIndex)) {
                contentNode.addChildNode(node)
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

    private var labelScale: Double { max(0.18, extent * 0.035) }

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

    private func arrowNode(tail: Vec3, vec: Vec3, color: NSColor, label: String?) -> SCNNode {
        let node = SCNNode()
        node.position = s(tail)
        let length = vec.length

        guard length > 1e-9, let dir = vec.normalized else {
            // Zero vector: a small marker at the tail so M = 0 still shows up.
            let g = SCNSphere(radius: 0.05 * labelScale + 0.04)
            g.materials = [material(color)]
            node.addChildNode(SCNNode(geometry: g))
            if let label { node.addChildNode(textNode(label, color: color, offset: Vec3(0, 0, 0.25))) }
            return node
        }

        let tipLength = min(0.3 * length, 0.06 * extent + 0.1)
        let shaftRadius = 0.0055 * extent

        let aligned = SCNNode()
        orient(aligned, along: dir)

        let shaft = SCNCylinder(radius: shaftRadius, height: length - tipLength)
        shaft.radialSegmentCount = 16
        shaft.materials = [material(color)]
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position.y = (length - tipLength) / 2

        let cone = SCNCone(topRadius: 0, bottomRadius: shaftRadius * 3.2, height: tipLength)
        cone.radialSegmentCount = 16
        cone.materials = [material(color)]
        let coneNode = SCNNode(geometry: cone)
        coneNode.position.y = length - tipLength / 2

        aligned.addChildNode(shaftNode)
        aligned.addChildNode(coneNode)
        node.addChildNode(aligned)

        if let label {
            node.addChildNode(textNode(label, color: color, offset: vec + dir * (labelScale * 1.6)))
        }
        return node
    }

    private func pointNode(at p: Vec3, color: NSColor, label: String?) -> SCNNode {
        let node = SCNNode()
        node.position = s(p)
        let g = SCNSphere(radius: 0.014 * extent + 0.03)
        g.segmentCount = 24
        g.materials = [material(color)]
        node.addChildNode(SCNNode(geometry: g))
        if let label {
            node.addChildNode(textNode(label, color: color, offset: Vec3(0, 0, 0.05 * extent)))
        }
        return node
    }

    private func textNode(_ string: String, color: NSColor, offset: Vec3) -> SCNNode {
        let text = SCNText(string: string, extrusionDepth: 0)
        text.font = .monospacedSystemFont(ofSize: 1, weight: .semibold)
        text.flatness = 0.05
        text.materials = [material(color, constant: true)]

        let node = SCNNode(geometry: text)
        let scale = labelScale
        node.scale = SCNVector3(scale, scale, scale)

        // Center the text on its position.
        let (minB, maxB) = text.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
        node.position = s(offset)
        node.constraints = [SCNBillboardConstraint()]
        return node
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
        let labelPos = arc.origin + radius * 1.45 * (cos(mid) * ua + sin(mid) * w)
        node.addChildNode(labelNodeAtWorld(Fmt.num(arc.degrees) + "°", color: color, worldPos: labelPos))
        return node
    }

    private func labelNodeAtWorld(_ string: String, color: NSColor, worldPos: Vec3) -> SCNNode {
        let n = textNode(string, color: color, offset: .zero)
        n.position = s(worldPos)
        return n
    }

    // MARK: - Axes & grid

    private func rebuildAxesAndGrid() {
        axesNode.childNodes.forEach { $0.removeFromParentNode() }
        gridNode.childNodes.forEach { $0.removeFromParentNode() }

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
        let radius = 0.0035 * e

        let aligned = SCNNode()
        orient(aligned, along: dir)

        let shaft = SCNCylinder(radius: radius, height: 2 * e)
        shaft.radialSegmentCount = 12
        shaft.materials = [material(color.withAlphaComponent(0.8))]
        aligned.addChildNode(SCNNode(geometry: shaft))   // centered: spans -e…+e

        let cone = SCNCone(topRadius: 0, bottomRadius: radius * 4, height: 0.045 * e)
        cone.materials = [material(color)]
        let coneNode = SCNNode(geometry: cone)
        coneNode.position.y = e
        aligned.addChildNode(coneNode)

        node.addChildNode(aligned)
        node.addChildNode(textNode(label, color: color, offset: dir * (e * 1.07)))
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
