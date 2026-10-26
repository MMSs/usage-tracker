// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UsageTracker",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "UsageTracker", targets: ["UsageTracker"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "UsageTracker",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(
            name: "UsageTrackerTests",
            dependencies: ["UsageTracker"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
