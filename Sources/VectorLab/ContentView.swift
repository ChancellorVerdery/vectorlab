import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VectorLabScene

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showingHelp = false
    @State private var viewportProxy = ViewportProxy()

    var body: some View {
        @Bindable var model = model
        HSplitView {
            NotebookView(model: model)
                .frame(minWidth: 320, idealWidth: 400)

            Viewport3D(
                proxy: viewportProxy,
                items: model.coloredDrawables,
                arcs: model.coloredArcs,
                showAxes: model.showAxes,
                showGrid: model.showGrid,
                showArrowheads: model.showArrowheads,
                preset: model.preset,
                presetToken: model.presetToken,
                fitToken: model.fitToken
            )
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.entries) {
            model.reevaluate()
        }
        .onChange(of: model.preset) {
            model.presetToken += 1
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Camera view", selection: $model.preset) {
                    ForEach(CameraPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Button("Fit view", systemImage: "arrow.down.left.and.arrow.up.right") {
                    model.fitToken += 1
                }

                Toggle("Axes", systemImage: "move.3d", isOn: $model.showAxes)
                Toggle("Grid", systemImage: "grid", isOn: $model.showGrid)
                Toggle("Arrowheads", systemImage: "arrowtriangle.up", isOn: $model.showArrowheads)

                Button("Save snapshot", systemImage: "camera", action: saveSnapshot)

                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Load example") { model.loadExample() }
                    Button("Clear all", role: .destructive) { model.clearAll() }
                }

                Button("Notation help", systemImage: "questionmark.circle") {
                    showingHelp.toggle()
                }
                .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                    CheatSheetView()
                }
            }
        }
        .navigationTitle("VectorLab")
    }

    private func saveSnapshot() {
        guard let image = viewportProxy.snapshot() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "VectorLab.png"
        guard panel.runModal() == .OK, let url = panel.url,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
