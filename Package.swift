// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UsageTracker",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "UsageTracker", targets: ["UsageTracker"])],
    targets: [
        .executableTarget(name: "UsageTracker"),
        .testTarget(name: "UsageTrackerTests", dependencies: ["UsageTracker"]),
    ]
)
