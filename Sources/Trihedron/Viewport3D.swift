import QuartzCore
import SceneKit
import SwiftUI
import TrihedronScene

struct Viewport3D: NSViewRepresentable {
    let proxy: ViewportProxy
    var items: [ColoredDrawable]
    var arcs: [ColoredArc]
    var showAxes: Bool
    var showGrid: Bool
    var showArrowheads: Bool
    var preset: CameraPreset
    var presetToken: Int
    var fitToken: Int

    final class Coordinator: NSObject {
        let controller = VectorSceneController()
        weak var view: SCNView?
        var displayLink: CADisplayLink?
        var lastItems: [ColoredDrawable]?
        var lastArcs: [ColoredArc]?
        var lastAxes = true
        var lastGrid = true
        var lastArrowheads = true
        var lastPresetToken = 0
        var lastFitToken = 0

        // Runs on the main run loop each frame: keeps arrow girth and label
        // size visually constant as the user zooms the camera.
        @objc func tick(_ link: CADisplayLink) {
            guard let view, let pov = view.pointOfView else { return }
            controller.updateScreenScale(cameraPosition: pov.presentation.position)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let coordinator = context.coordinator
        view.scene = coordinator.controller.scene
        view.pointOfView = coordinator.controller.cameraNode
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        coordinator.view = view
        proxy.view = view

        let link = view.displayLink(target: coordinator, selector: #selector(Coordinator.tick(_:)))
        link.add(to: .main, forMode: .common)
        coordinator.displayLink = link
        return view
    }

    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.displayLink?.invalidate()
        coordinator.displayLink = nil
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        if items != c.lastItems || arcs != c.lastArcs || showAxes != c.lastAxes
            || showGrid != c.lastGrid || showArrowheads != c.lastArrowheads {
            c.controller.update(items: items, arcs: arcs, showAxes: showAxes,
                                showGrid: showGrid, showArrowheads: showArrowheads)
            c.lastItems = items
            c.lastArcs = arcs
            c.lastAxes = showAxes
            c.lastGrid = showGrid
            c.lastArrowheads = showArrowheads
        }
        if presetToken != c.lastPresetToken {
            c.lastPresetToken = presetToken
            c.controller.apply(preset: preset)
        }
        if fitToken != c.lastFitToken {
            c.lastFitToken = fitToken
            c.controller.fit()
        }
    }
}
