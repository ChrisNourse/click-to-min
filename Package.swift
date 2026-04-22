// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClickToMin",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClickToMin", targets: ["ClickToMin"]),
        .library(name: "ClickToMinCore", targets: ["ClickToMinCore"]),
    ],
    targets: [
        // Pure-logic library: no AppKit/AX/NSWorkspace imports.
        // Boundary is enforced at the compiler level by the target split.
        .target(
            name: "ClickToMinCore",
            path: "Sources/ClickToMin/Core"
        ),
        // Executable: AppDelegate + DockWatcher + IO adapters.
        .executableTarget(
            name: "ClickToMin",
            dependencies: ["ClickToMinCore"],
            path: "Sources/ClickToMin",
            exclude: ["Core"],
            sources: ["AppDelegate.swift", "DockWatcher.swift", "IO"]
        ),
        .testTarget(
            name: "ClickToMinTests",
            dependencies: ["ClickToMinCore"],
            path: "Tests/ClickToMinTests"
        ),
    ]
)
