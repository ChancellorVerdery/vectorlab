import AppKit
import Metal
import SceneKit
import Testing
import TrihedronCore
@testable import TrihedronScene

/// Graphed curves and surfaces reach the scene as real geometry.
@Suite struct GraphRenderTests {
    private func parabola(reach: Double, samples: Int = 40) -> [Vec3] {
        (0...samples).map { i in
            let x = -reach + 2 * reach * Double(i) / Double(samples)
            return Vec3(x, x * x / reach, 0)
        }
    }

    private func bowl(size: Int = 6, hole: Bool = false) -> [[Vec3?]] {
        (0..<size).map { i in
            (0..<size).map { j in
                if hole, i == size / 2, j == size / 2 { return nil }
                let x = Double(i) - Double(size - 1) / 2, y = Double(j) - Double(size - 1) / 2
                return Vec3(x, y, (x * x + y * y) / 4)
            }
        }
    }

    private func walk(_ node: SCNNode, _ visit: (SCNNode) -> Void) {
        visit(node)
        node.childNodes.forEach { walk($0, visit) }
    }

    /// Graph meshes are plain SCNGeometry; SceneKit's own shapes (the axis
    /// cylinders, cones, text) are subclasses and are not counted.
    private func isMesh(_ g: SCNGeometry?) -> Bool {
        guard let g else { return false }
        return type(of: g) == SCNGeometry.self && g.elements.contains { $0.primitiveType == .triangles }
    }

    private func triangleElements(in root: SCNNode) -> [SCNGeometryElement] {
        var found: [SCNGeometryElement] = []
        walk(root) { n in
            guard isMesh(n.geometry) else { return }
            for e in n.geometry?.elements ?? [] where e.primitiveType == .triangles {
                found.append(e)
            }
        }
        return found
    }

    private func labels(in root: SCNNode) -> [String] {
        var found: [String] = []
        walk(root) { n in
            if let text = n.geometry as? SCNText {
                found.append((text.string as? NSAttributedString)?.string ?? (text.string as? String) ?? "")
            }
        }
        return found
    }

    /// Axis shafts are the only cylinders when nothing else is drawn, and
    /// each spans -extent…+extent.
    private func axisLength(in controller: VectorSceneController) -> Double? {
        var heights: [Double] = []
        walk(controller.scene.rootNode) { n in
            if let c = n.geometry as? SCNCylinder { heights.append(Double(c.height)) }
        }
        return heights.max()
    }

    private func nonFinite(in root: SCNNode) -> [String] {
        var bad: [String] = []
        walk(root) { node in
            let p = node.position
            if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite { bad.append("position \(p)") }
            for source in node.geometry?.sources ?? []
            where source.semantic == .vertex && source.bytesPerComponent == 4 && source.dataStride == 12 {
                source.data.withUnsafeBytes { raw in
                    for f in raw.bindMemory(to: Float.self) where !f.isFinite {
                        bad.append("vertex \(f)")
                        break
                    }
                }
            }
        }
        return bad
    }

    @Test func aCurveBecomesOneTubePerRunWithItsLabelAtTheEnd() {
        let controller = VectorSceneController()
        let runs = [parabola(reach: 4), [Vec3(0, 0, 0), Vec3(1, 0, 1), Vec3(2, 0, 4)]]
        controller.update(
            items: [ColoredDrawable(drawable: Drawable(shape: .curve(segments: runs), label: "y = x^2"),
                                    colorIndex: 0)],
            arcs: [], showAxes: false, showGrid: false)
        let tubes = triangleElements(in: controller.scene.rootNode)
        #expect(tubes.count == 2)
        // 8 sides × 2 triangles per segment.
        #expect(tubes[0].primitiveCount == 40 * 8 * 2)
        #expect(tubes[1].primitiveCount == 2 * 8 * 2)
        #expect(labels(in: controller.scene.rootNode).contains("y = x^2"))
        #expect(nonFinite(in: controller.scene.rootNode).isEmpty)
    }

    @Test func aSurfaceBecomesAMeshAndHolesRemoveTheirQuads() {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(drawable: Drawable(shape: .surface(rows: bowl()), label: "z = x^2 + y^2"),
                                    colorIndex: 1)],
            arcs: [], showAxes: false, showGrid: false)
        let full = triangleElements(in: controller.scene.rootNode)
        #expect(full.count == 1)
        #expect(full.first?.primitiveCount == 5 * 5 * 2)

        controller.update(
            items: [ColoredDrawable(drawable: Drawable(shape: .surface(rows: bowl(hole: true)), label: "z"),
                                    colorIndex: 1)],
            arcs: [], showAxes: false, showGrid: false)
        let holed = triangleElements(in: controller.scene.rootNode)
        // The hole vertex touches four quads.
        #expect(holed.first?.primitiveCount == (25 - 4) * 2)
        #expect(labels(in: controller.scene.rootNode).contains("z"))
        #expect(nonFinite(in: controller.scene.rootNode).isEmpty)
    }

    @Test func aSurfaceIsTwoSidedAndTranslucent() {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(drawable: Drawable(shape: .surface(rows: bowl()), label: nil), colorIndex: 2)],
            arcs: [], showAxes: false, showGrid: false)
        var fill: SCNMaterial?
        walk(controller.scene.rootNode) { n in
            if isMesh(n.geometry) { fill = n.geometry?.materials.first }
        }
        #expect(fill?.isDoubleSided == true)
        #expect((fill?.diffuse.contents as? NSColor)?.alphaComponent ?? 1 < 1)
    }

    @Test func graphsGrowTheAxesOnlyToTheirOwnReach() {
        // A vector of reach 5 gets the 20% margin: 6-unit axes. A curve of
        // reach 5 does not: 5-unit axes. A curve of reach 9 makes them 9.
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(drawable: Drawable(shape: .curve(segments: [parabola(reach: 5)]), label: nil),
                                    colorIndex: 0)],
            arcs: [], showAxes: true, showGrid: false)
        #expect(axisLength(in: controller) == 10)

        controller.update(
            items: [ColoredDrawable(drawable: Drawable(shape: .curve(segments: [parabola(reach: 9)]), label: nil),
                                    colorIndex: 0)],
            arcs: [], showAxes: true, showGrid: false)
        #expect(axisLength(in: controller) == 18)

        controller.update(
            items: [ColoredDrawable(drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(5, 0, 0)), label: nil),
                                    colorIndex: 0)],
            arcs: [], showAxes: true, showGrid: false)
        #expect(axisLength(in: controller) == 12)
    }

    @Test func unrenderableGraphVerticesAreDroppedNotSentToSceneKit() {
        let controller = VectorSceneController()
        var run = parabola(reach: 3)
        run.insert(Vec3(1e200, 0, 0), at: 5)
        var rows = bowl()
        rows[1][1] = Vec3(.infinity, 0, 0)
        rows[2][2] = Vec3(0, 1e300, 0)
        controller.update(
            items: [
                ColoredDrawable(drawable: Drawable(shape: .curve(segments: [run]), label: "c"), colorIndex: 0),
                ColoredDrawable(drawable: Drawable(shape: .surface(rows: rows), label: "s"), colorIndex: 1),
            ],
            arcs: [], showAxes: true, showGrid: true)
        #expect(nonFinite(in: controller.scene.rootNode).isEmpty)
        #expect(axisLength(in: controller) == 10, "an unrenderable vertex must not grow the axes")
    }

    @Test func tubesAreRebuiltWhenTheCameraZooms() {
        let controller = VectorSceneController()
        controller.update(
            items: [ColoredDrawable(drawable: Drawable(shape: .curve(segments: [parabola(reach: 4)]), label: nil),
                                    colorIndex: 0)],
            arcs: [], showAxes: false, showGrid: false)
        var before: SCNGeometry?
        walk(controller.scene.rootNode) { n in
            if isMesh(n.geometry) { before = n.geometry }
        }
        controller.updateScreenScale(cameraPosition: SCNVector3(0, 0, 200))
        var after: SCNGeometry?
        walk(controller.scene.rootNode) { n in
            if isMesh(n.geometry) { after = n.geometry }
        }
        #expect(before != nil && after != nil && before !== after)
    }

    /// Offscreen-render a curve, a surface and a vector together and check
    /// the image is not blank. Headless-safe: no window is ever created.
    @Test func offscreenRenderOfGraphsProducesContent() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let controller = VectorSceneController()
        controller.update(
            items: [
                ColoredDrawable(drawable: Drawable(shape: .curve(segments: [parabola(reach: 4)]), label: "y = x^2"),
                                colorIndex: 0),
                ColoredDrawable(drawable: Drawable(shape: .surface(rows: bowl(size: 12)), label: "z"),
                                colorIndex: 1),
                ColoredDrawable(drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(3, 2, 4)), label: "F"),
                                colorIndex: 2),
            ],
            arcs: [], showAxes: true, showGrid: true)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = controller.scene
        renderer.pointOfView = controller.cameraNode
        renderer.autoenablesDefaultLighting = true
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 240, height: 240), antialiasingMode: .none)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            Issue.record("could not read rendered image")
            return
        }
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
