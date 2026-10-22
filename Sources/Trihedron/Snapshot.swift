import AppKit
import SceneKit
import TrihedronScene

/// Screenshot mode for the README: `TRIHEDRON_SNAPSHOT=<dir> Trihedron` loads
/// each worked example below into an in-memory notebook (the saved workspace is
/// never read or written), captures the window in-process — no Screen
/// Recording permission needed — writes `<dir>/<name>.png`, then quits.
enum Snapshot {
    static let directory: URL? = ProcessInfo.processInfo.environment["TRIHEDRON_SNAPSHOT"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

    struct Example {
        let name: String
        let preset: CameraPreset
        let lines: [String]
    }

    static let examples: [Example] = [
        Example(name: "graph-curves", preset: .iso, lines: [
            "# Curves: the axis on the left picks the plane",
            "y = x^2 / 4",
            "z = 2 * sin(deg(x))",
            "x = 3 - y^2 / 3",
            "v = <4, 3, 2>",
        ]),
        Example(name: "graph-surface", preset: .iso, lines: [
            "# Surface z = x² + y² with a point on it",
            "z = x^2 + y^2, x in [-2, 2], y in [-2, 2]",
            "point P = (1.5, -1, 3.25)",
            "r_P = <1.5, -1, 3.25>",
            "|r_P|",
        ]),
        Example(name: "planar-polar", preset: .top, lines: [
            "# Planar forces in polar form (XY view)",
            "T_A = 50∠30",
            "T_B = 40∠135",
            "W = <0, -60, 0>",
            "R = T_A + T_B + W",
            "|R|",
            "atan2(R.y, R.x)",
        ]),
        Example(name: "resultant", preset: .iso, lines: [
            "# Concurrent forces (N) and their resultant",
            "F_A = <250, -200, 0>",
            "F_B = <0, -150, 200>",
            "F_C = <150, 100, 120>",
            "R = resultant(F_A, F_B, F_C)",
            "|R|",
            "û_R = unit(R)",
            "angle(R, k)",
        ]),
        Example(name: "dot-cross", preset: .iso, lines: [
            "# Dot and cross products",
            "a = <3, 1, 0>",
            "b = <1, 2, 2>",
            "a · b",
            "n = a × b",
            "angle(a, b)",
            "comp(a, b)",
            "p = proj(a, b)",
        ]),
        Example(name: "cable-moment", preset: .iso, lines: [
            "# 1.3 kN force along cable AB, moment about O",
            "point O = (0, 0, 0)",
            "point A = (0, 0, 12)",
            "point B = (4, -3, 0)",
            "r_AB",
            "F = 1.3 * unit(r_AB)",
            "M_O = moment(r_OA, F)",
            "|M_O|",
            "angle(F, r_OA)",
        ]),
        Example(name: "position-vectors", preset: .iso, lines: [
            "# Moment of F about the x axis (AB)",
            "point A = (0, 0, 0)",
            "point B = (6, 0, 0)",
            "point C = (6, -4, 3)",
            "point D = (0, 0, 3)",
            "r_AC",
            "r_CD",
            "F = 8 * unit(r_CD)",
            "dist(A, C)",
            "moment(unit(r_AB), r_AC, F)",
        ]),
    ]

    /// The app's model: in memory only, and empty so the examples below are
    /// the only lines on screen.
    static func makeModel() -> AppModel {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let model = AppModel(saveURL: nil)
        model.entries = []
        return model
    }

    /// Drives the window through every example. Called once the window is up.
    static func run(model: AppModel, proxy: ViewportProxy, into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let window = proxy.view?.window {
            // An occluded window gets throttled display updates and SwiftUI may
            // never redraw it, so keep it briefly in front while capturing.
            window.level = .floating
            window.setContentSize(NSSize(width: 1080, height: 680))
            // SwiftUI rasterizes at the window's backing scale, so put the window
            // on the sharpest display (a retina panel next to a 1x monitor).
            if let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) {
                let area = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2,
                                              y: area.midY - window.frame.height / 2))
            } else {
                window.center()
            }
            window.orderFrontRegardless()
        }
        // Lines are rewritten in place and only ever appended (examples run
        // shortest first): replacing or shrinking `entries` underneath live
        // row bindings trips SwiftUI's stale-index read in RichEntryField.
        for example in examples.sorted(by: { $0.lines.count < $1.lines.count }) {
            for (i, text) in example.lines.enumerated() {
                let color = i % Palette.nsColors.count
                if model.entries.indices.contains(i) {
                    model.entries[i].text = text
                    model.entries[i].colorIndex = color
                } else {
                    model.entries.append(Entry(text: text, colorIndex: color))
                }
            }
            model.reevaluate()
            model.preset = example.preset
            model.presetToken += 1
            try? await Task.sleep(for: .seconds(2))
            if let png = capture(proxy: proxy) {
                try? png.write(to: dir.appendingPathComponent("\(example.name).png"))
            }
        }
        NSApp.terminate(nil)
    }

    /// The window's content area (below the toolbar, whose glass items do not
    /// draw through `cacheDisplay`), with the Metal-backed SceneKit view — which
    /// `cacheDisplay` also leaves blank — rendered separately and composited on
    /// top. Always at least 2x (the window's backing scale if higher), never
    /// downscaled.
    private static func capture(proxy: ViewportProxy) -> Data? {
        guard let scnView = proxy.view, let window = scnView.window,
              let frameView = window.contentView?.superview
        else { return nil }
        let scale = max(2, window.backingScaleFactor)
        let size = frameView.bounds.size
        guard let rep = bitmap(size, scale: scale) else { return nil }

        // A window that is not on screen gets no display-link ticks, so camera
        // animations never finish and the zoom-dependent sizing goes stale.
        // Snap both to their final state before rendering.
        if let camera = scnView.pointOfView {
            camera.removeAllAnimations()
            proxy.controller?.updateScreenScale(cameraPosition: camera.position)
        }
        window.display()
        frameView.cacheDisplay(in: frameView.bounds, to: rep)

        // The viewport, rendered offscreen at the same pixel scale.
        let renderer = SCNRenderer(device: scnView.device, options: nil)
        renderer.scene = scnView.scene
        renderer.pointOfView = scnView.pointOfView
        renderer.autoenablesDefaultLighting = scnView.autoenablesDefaultLighting
        let viewportImage = renderer.snapshot(
            atTime: 0,
            with: CGSize(width: scnView.bounds.width * scale, height: scnView.bounds.height * scale),
            antialiasingMode: .multisampling4X)

        let crop = window.contentLayoutRect   // window coordinates, bottom-left origin
        guard let out = bitmap(crop.size, scale: scale) else { return nil }

        var viewport = scnView.convert(scnView.bounds, to: frameView)
        if frameView.isFlipped { viewport.origin.y = size.height - viewport.maxY }
        let shift = { (r: NSRect) in r.offsetBy(dx: -crop.minX, dy: -crop.minY) }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        rep.draw(in: shift(NSRect(origin: .zero, size: size)))
        viewportImage.draw(in: shift(viewport))
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(using: .png, properties: [:])
    }

    /// An RGBA bitmap of `size` points at `scale` pixels per point.
    private static func bitmap(_ size: NSSize, scale: CGFloat) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = size
        return rep
    }
}
