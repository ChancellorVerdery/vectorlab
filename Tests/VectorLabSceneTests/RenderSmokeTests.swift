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
                drawable: Drawable(shape: .arrow(tail: .zero, vector: Vec3(3, 2, 4)), label: "F"),
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
