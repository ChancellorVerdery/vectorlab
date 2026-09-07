// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VectorLab",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "VectorLabCore"),
        .target(
            name: "VectorLabScene",
            dependencies: ["VectorLabCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "VectorLab",
            dependencies: ["VectorLabCore", "VectorLabScene"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "VectorLabCoreTests", dependencies: ["VectorLabCore"]),
        .testTarget(
            name: "VectorLabSceneTests",
            dependencies: ["VectorLabScene"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "VectorLabAppTests",
            dependencies: ["VectorLab"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
