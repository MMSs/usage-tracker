/// The one place the bundle identifier is written in code. `Resources/Info.plist`
/// and `scripts/build-app.sh` carry the same value.
enum AppIdentity {
    static let bundleID = "com.mohabsam.usage-tracker"

    /// The identifier before the rename; only the one-time migration reads it.
    static let previousBundleID = "com.mohab.usage-tracker"
}
