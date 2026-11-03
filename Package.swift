// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WindowFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WindowFlowCore", path: "Sources/WindowFlowCore"),
        .executableTarget(name: "WindowFlow", dependencies: ["WindowFlowCore"], path: "Sources/WindowFlow"),
        .testTarget(name: "WindowFlowCoreTests", dependencies: ["WindowFlowCore"], path: "Tests/WindowFlowCoreTests"),
    ]
)
