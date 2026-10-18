// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KeyScore",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "KeyScore", path: "Sources/KeyScore"),
        .testTarget(name: "KeyScoreTests", dependencies: ["KeyScore"], path: "Tests/KeyScoreTests"),
    ],
    swiftLanguageModes: [.v6]
)
