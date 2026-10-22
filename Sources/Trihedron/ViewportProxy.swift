import AppKit
import SceneKit
import TrihedronScene

/// Per-window handle to the live SCNView, so toolbar actions (snapshot)
/// target this window's viewport instead of a shared global.
final class ViewportProxy {
    weak var view: SCNView?
    weak var controller: VectorSceneController?

    func snapshot() -> NSImage? { view?.snapshot() }
}
