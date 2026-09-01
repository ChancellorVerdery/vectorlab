import SwiftUI

@main
struct VectorLabApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("VectorLab") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1150, height: 720)
    }
}
