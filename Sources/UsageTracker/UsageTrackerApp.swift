import SwiftUI

@main
struct UsageTrackerApp: App {
    nonisolated static let applicationName = "Usage Tracker"
    var body: some Scene {
        MenuBarExtra("Usage Tracker") { Text("Setting up…") }.menuBarExtraStyle(.window)
    }
}
