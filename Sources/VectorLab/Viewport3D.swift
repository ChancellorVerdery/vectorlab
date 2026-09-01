import SceneKit
import SwiftUI
import VectorLabScene

struct Viewport3D: NSViewRepresentable {
    let model: AppModel
    var items: [ColoredDrawable]
    var arcs: [ColoredArc]
    var showAxes: Bool
    var showGrid: Bool
    var preset: CameraPreset
    var presetToken: Int
    var fitToken: Int

    final class Coordinator {
        let controller = VectorSceneController()
        var lastItems: [ColoredDrawable]?
        var lastArcs: [ColoredArc]?
        var lastAxes = true
        var lastGrid = true
        var lastPresetToken = 0
        var lastFitToken = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let controller = context.coordinator.controller
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        model.snapshotProvider = { [weak view] in view?.snapshot() }
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        if items != c.lastItems || arcs != c.lastArcs || showAxes != c.lastAxes || showGrid != c.lastGrid {
            c.controller.update(items: items, arcs: arcs, showAxes: showAxes, showGrid: showGrid)
            c.lastItems = items
            c.lastArcs = arcs
            c.lastAxes = showAxes
            c.lastGrid = showGrid
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
