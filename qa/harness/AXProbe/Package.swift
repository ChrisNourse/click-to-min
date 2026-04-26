// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AXProbe",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "axprobe", targets: ["AXProbe"]),
    ],
    targets: [
        .executableTarget(
            name: "AXProbe",
            path: "Sources/AXProbe"
        ),
        .testTarget(
            name: "AXProbeTests",
            dependencies: ["AXProbe"],
            path: "Tests/AXProbeTests"
        ),
    ]
)
