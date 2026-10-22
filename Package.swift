// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Trihedron",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "TrihedronCore"),
        .target(
            name: "TrihedronScene",
            dependencies: ["TrihedronCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "Trihedron",
            dependencies: ["TrihedronCore", "TrihedronScene"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "TrihedronCoreTests", dependencies: ["TrihedronCore"]),
        .testTarget(
            name: "TrihedronSceneTests",
            dependencies: ["TrihedronScene"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "TrihedronAppTests",
            dependencies: ["Trihedron"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
