import SwiftUI

@main
struct TrihedronApp: App {
    @State private var model = Snapshot.directory == nil ? AppModel() : Snapshot.makeModel()

    var body: some Scene {
        WindowGroup("Trihedron") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1150, height: 720)
    }
}
