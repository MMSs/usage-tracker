import Foundation
import Testing
@testable import UsageTracker

/// `AppIdentity.bundleID` is written again in the plist and the build script;
/// these keep the three from drifting apart.
@Suite struct AppIdentityTests {
    /// The package root, found by walking up from this file to `Package.swift`.
    private func packageRoot(from file: String = #filePath) throws -> URL {
        var directory = URL(fileURLWithPath: file).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
            let parent = directory.deletingLastPathComponent()
            try #require(parent != directory, "no Package.swift above \(file)")
            directory = parent
        }
        return directory
    }

    @Test func infoPlistCarriesTheBundleID() throws {
        let url = try packageRoot().appendingPathComponent("Resources/Info.plist")
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        #expect(plist["CFBundleIdentifier"] as? String == AppIdentity.bundleID)
    }

    @Test func buildScriptSignsWithTheBundleID() throws {
        let url = try packageRoot().appendingPathComponent("scripts/build-app.sh")
        let script = try String(contentsOf: url, encoding: .utf8)
        #expect(script.contains("--identifier \(AppIdentity.bundleID)"))
    }
}
