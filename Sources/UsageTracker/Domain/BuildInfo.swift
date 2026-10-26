import Foundation

/// What the running bundle says about itself: its release version and the
/// update feed it was built to check. Builds made from source carry neither.
struct BuildInfo: Equatable {
    /// The release version, or nil in a build made from source.
    let version: String?
    /// The appcast to check for updates, or nil when the build has none.
    let feedURL: URL?

    init(infoDictionary: [String: Any]?) {
        version = infoDictionary?["CFBundleShortVersionString"] as? String
        feedURL = (infoDictionary?["SUFeedURL"] as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    /// The running bundle's build info.
    static var main: BuildInfo {
        BuildInfo(infoDictionary: Bundle.main.infoDictionary)
    }

    /// The version as shown in the UI, `Version dev` for a source build.
    var versionText: String {
        "Version \(version ?? "dev")"
    }
}
