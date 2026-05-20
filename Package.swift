// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Toki",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Toki",
            path: "Sources/Toki"
        ),
        .testTarget(
            name: "TokiTests",
            dependencies: ["Toki"],
            path: "Tests/TokiTests"
        )
    ]
)
