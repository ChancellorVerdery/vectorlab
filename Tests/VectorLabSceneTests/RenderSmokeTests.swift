import AppKit
import Metal
import SceneKit
import Testing
import VectorLabCore
@testable import VectorLabScene

@Suite struct RenderSmokeTests {
    /// Review finding: unclamped extent used to trap Int() on infinite
    /// coordinates and hang building the grid for large finite ones.
    @Test func extremeCoordinatesDoNotCrashSceneUpdate() {
        let controller = VectorSceneController()
        let items = [
            ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(1e20, 0, 0)), label: nil),
                colorIndex: 0),
            ColoredDrawable(
                drawable: Drawable(shape: .point(Vec3(.infinity, 0, 0)), label: nil),
                colorIndex: 1),
        ]
        controller.update(items: items, arcs: [], showAxes: true, showGrid: true)
        controller.update(items: [], arcs: [], showAxes: true, showGrid: true)
    }

    /// Components can be finite while |v| overflows. The arrow then got an
    /// infinite-height shaft and a NaN orientation from normalizing <0,0,0>.
    @Test func overflowingLengthDoesNotBuildInfiniteGeometry() {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(1e200, 1e200, 0)), label: "F"),
                colorIndex: 0)],
            arcs: [], showAxes: true, showGrid: true)

        let bad = nonFiniteGeometry(in: controller.scene.rootNode)
        #expect(bad.isEmpty, "non-finite scene geometry: \(bad)")
    }

    /// The same Float bound applies to POINTS, which pass 1 never exercised:
    /// a point at 1e200 placed its node at an infinite position.
    @Test func overflowingPointDoesNotBuildInfiniteGeometry() {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(
                drawable: Drawable(shape: .point(Vec3(1e200, -1e200, 1e200)), label: "P"),
                colorIndex: 0)],
            arcs: [], showAxes: true, showGrid: true)
        let bad = nonFiniteGeometry(in: controller.scene.rootNode)
        #expect(bad.isEmpty, "non-finite scene geometry: \(bad)")
    }

    /// The renderable cap must not creep down onto magnitudes that always drew.
    /// 1e20 is enormous but sits well inside Float range, so it still gets a
    /// real shaft rather than the zero-vector marker.
    @Test func largeButRenderableArrowStillDrawsAShaft() {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(1e20, 0, 0)), label: "F"),
                colorIndex: 0)],
            arcs: [], showAxes: true, showGrid: true)
        var shafts = 0
        func walk(_ node: SCNNode) {
            if node.geometry is SCNCylinder { shafts += 1 }
            node.childNodes.forEach(walk)
        }
        walk(controller.scene.rootNode)
        #expect(shafts > 0, "a 1e20 arrow should still be drawn")
        #expect(nonFiniteGeometry(in: controller.scene.rootNode).isEmpty)
    }

    /// Offscreen-render a small workspace and check the image isn't blank.
    /// Headless-safe: no window is ever created.
    @Test func offscreenRenderProducesContent() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            // No Metal (e.g. bare CI VM): nothing to verify.
            return
        }

        let controller = VectorSceneController()
        let items = [
            ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(3, 2, 4)), label: "r_AB"),
                colorIndex: 0),
            ColoredDrawable(
                drawable: Drawable(shape: .point(Vec3(1, 1, 1)), label: "A"),
                colorIndex: 1),
        ]
        let arcs = [
            ColoredArc(arc: ArcSpec(origin: .zero, from: Vec3(3, 2, 4), to: Vec3(0, 0, 1), degrees: 42),
                       colorIndex: 2)
        ]
        controller.update(items: items, arcs: arcs, showAxes: true, showGrid: true)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = controller.scene
        renderer.pointOfView = controller.cameraNode
        renderer.autoenablesDefaultLighting = true
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 240, height: 240),
                                      antialiasingMode: .none)

        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            Issue.record("could not read rendered image")
            return
        }
        // Count pixels that differ from the background corner pixel.
        let corner = rep.colorAt(x: 2, y: 2)
        var distinct = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
                if let c = rep.colorAt(x: x, y: y), let corner,
                   abs(c.redComponent - corner.redComponent) + abs(c.greenComponent - corner.greenComponent)
                   + abs(c.blueComponent - corner.blueComponent) > 0.08 {
                    distinct += 1
                }
            }
        }
        #expect(distinct > 20, "rendered scene appears blank (\(distinct) distinct samples)")
    }
}

/// Every non-finite position, orientation or geometry dimension in a subtree.
/// SceneKit stores transforms as 32-bit floats, so anything past ~3.4e38 reads
/// back as infinity — these are the symptoms that shows up as.
private func nonFiniteGeometry(in root: SCNNode) -> [String] {
    var bad: [String] = []
    func walk(_ node: SCNNode) {
        let p = node.position
        if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite { bad.append("position \(p)") }
        let q = node.simdOrientation.vector
        if !q.x.isFinite || !q.y.isFinite || !q.z.isFinite || !q.w.isFinite {
            bad.append("orientation of \(node)")
        }
        if let c = node.geometry as? SCNCylinder, !c.height.isFinite || !c.radius.isFinite {
            bad.append("cylinder \(c.radius) x \(c.height)")
        }
        if let c = node.geometry as? SCNCone, !c.height.isFinite { bad.append("cone \(c.height)") }
        // Pass 4: the walker only ever looked at TRANSFORMS. Arcs are custom
        // geometry whose node sits at the origin while its vertex buffer holds
        // the real coordinates, so an arc drawn 1e200 units out looked clean.
        if let g = node.geometry {
            for source in g.sources where source.semantic == .vertex {
                for v in source.vectorFloat3Values() where !v.x.isFinite || !v.y.isFinite || !v.z.isFinite {
                    bad.append("vertex \(v)")
                    break
                }
            }
        }
        node.childNodes.forEach(walk)
    }
    walk(root)
    return bad
}

// MARK: - Pass 4

extension RenderSmokeTests {
    /// Passes 1 and 2 gave arrows and points a Float-renderability guard.
    /// ARCS never got one. `Engine.arc` takes its origin from the two vectors'
    /// shared anchor, so `point A = (1e200, 0, 0)` … `angle(r_AB, r_AC)`
    /// hands `arcNode` an origin of 1e200; every one of its 33 vertices is
    /// `origin + radius * unit`, which is still 1e200, and SceneKit's 32-bit
    /// vertex storage reads that back as ∞. Same defect, third code path.
    @Test func overflowingArcOriginDoesNotBuildInfiniteGeometry() {
        let controller = VectorSceneController()
        controller.update(
            items: [],
            arcs: [ColoredArc(
                arc: ArcSpec(origin: Vec3(1e200, 0, 0), from: Vec3(1, 0, 0),
                             to: Vec3(0, 1, 0), degrees: 90),
                colorIndex: 0)],
            showAxes: true, showGrid: true)
        let bad = nonFiniteGeometry(in: controller.scene.rootNode)
        #expect(bad.isEmpty, "non-finite scene geometry: \(bad)")
    }

    /// The arc legs are equally capable of overflowing the vertex buffer even
    /// when the origin is fine — `radius * (cos t · â + sin t · ŵ)` is bounded,
    /// but a non-finite leg makes `normalized`/`dot` produce NaN directions.
    @Test func nonFiniteArcLegsDoNotBuildInfiniteGeometry() {
        let controller = VectorSceneController()
        controller.update(
            items: [],
            arcs: [ColoredArc(
                arc: ArcSpec(origin: .zero, from: Vec3(1e200, 1e200, 0),
                             to: Vec3(.infinity, 0, 0), degrees: 45),
                colorIndex: 0)],
            showAxes: true, showGrid: true)
        let bad = nonFiniteGeometry(in: controller.scene.rootNode)
        #expect(bad.isEmpty, "non-finite scene geometry: \(bad)")
    }

    /// An ordinary arc must still be drawn — the guard must not silently
    /// delete every arc in the app.
    @Test func ordinaryArcStillDraws() {
        let controller = VectorSceneController()
        controller.update(
            items: [],
            arcs: [ColoredArc(
                arc: ArcSpec(origin: .zero, from: Vec3(1, 0, 0), to: Vec3(0, 1, 0), degrees: 90),
                colorIndex: 0)],
            showAxes: false, showGrid: false)
        var sawArcLabel = false
        func walk(_ n: SCNNode) {
            if let text = n.geometry as? SCNText {
                let s = (text.string as? NSAttributedString)?.string ?? (text.string as? String) ?? ""
                if s.contains("90") { sawArcLabel = true }
            }
            n.childNodes.forEach(walk)
        }
        walk(controller.scene.rootNode)
        #expect(sawArcLabel, "the 90° arc was not drawn at all")
    }
}


private extension SCNGeometrySource {
    /// The vertex positions as SIMD3<Float>, for float-typed 3-component sources.
    func vectorFloat3Values() -> [SIMD3<Float>] {
        guard usesFloatComponents, componentsPerVector == 3, bytesPerComponent == 4 else { return [] }
        var out: [SIMD3<Float>] = []
        data.withUnsafeBytes { raw in
            for i in 0..<vectorCount {
                let base = dataOffset + i * dataStride
                guard base + 12 <= raw.count else { break }
                out.append(SIMD3<Float>(
                    raw.loadUnaligned(fromByteOffset: base, as: Float.self),
                    raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
                    raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self)))
            }
        }
        return out
    }
}

// MARK: - Pass 5

extension RenderSmokeTests {
    /// The axis shafts are `SCNCylinder(height: 2 * extent)`, so the largest
    /// cylinder in the scene reads back the viewport size the user sees.
    private func axisExtent(_ controller: VectorSceneController) -> Double {
        var tallest = 0.0
        func walk(_ n: SCNNode) {
            if let c = n.geometry as? SCNCylinder { tallest = max(tallest, c.height / 2) }
            n.childNodes.forEach(walk)
        }
        walk(controller.scene.rootNode)
        return tallest
    }

    /// `update` grew the viewport from every FINITE coordinate, but the node
    /// builders refuse anything past `Float.greatestFiniteMagnitude`. A point
    /// at 1e200 is finite, so `Engine.drawable` emits it and `fold` counted it
    /// — pinning `extent` to its 1000 cap — while `pointNode` then declined to
    /// draw it. The user gets axes 1000 units long, nothing at the far end,
    /// and their actual <3, 4, 0> vector shrunk to invisibility.
    @Test func viewportIgnoresGeometryTheSceneRefusesToDraw() {
        let controller = VectorSceneController()
        controller.update(
            items: [
                ColoredDrawable(
                    drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(3, 4, 0)), label: "F"),
                    colorIndex: 0),
                ColoredDrawable(
                    drawable: Drawable(shape: .point(Vec3(1e200, 0, 0)), label: "P"),
                    colorIndex: 1),
            ],
            arcs: [], showAxes: true, showGrid: true)
        #expect(axisExtent(controller) == 5,
                "the undrawable point resized the viewport to \(axisExtent(controller))")
    }

    /// The converse: something that IS drawn must still grow the viewport.
    @Test func drawableGeometryStillGrowsTheViewport() {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(0, 100, 0)), label: "F"),
                colorIndex: 0)],
            arcs: [], showAxes: true, showGrid: true)
        #expect(axisExtent(controller) == 120, "extent was \(axisExtent(controller))")
    }

    /// Pass 4's open lead: `update` computed `maxCoord` from `items` only, so
    /// an arc anchored further out than every arrow was drawn outside the axes.
    @Test func arcOriginGrowsTheViewport() {
        let controller = VectorSceneController()
        controller.update(
            items: [],
            arcs: [ColoredArc(
                arc: ArcSpec(origin: Vec3(50, 0, 0), from: Vec3(1, 0, 0),
                             to: Vec3(0, 1, 0), degrees: 90),
                colorIndex: 0)],
            showAxes: true, showGrid: true)
        #expect(axisExtent(controller) == 60, "extent was \(axisExtent(controller))")
    }
}
