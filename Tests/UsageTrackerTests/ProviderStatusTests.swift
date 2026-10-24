import Testing
@testable import UsageTracker

@Suite struct ProviderStatusTests {
    @Test func unconfiguredWinsOverEverything() {
        #expect(ProviderStatus.make(configured: false, statuses: [.error], planName: "Pro") == ProviderStatus(text: "Not set up", tone: .neutral))
    }

    @Test func worstHalfDecidesTheTone() {
        #expect(ProviderStatus.make(configured: true, statuses: [.ready, .expired], planName: nil).tone == .bad)
        #expect(ProviderStatus.make(configured: true, statuses: [.ready, .error], planName: nil) == ProviderStatus(text: "Unable to refresh", tone: .warning))
        #expect(ProviderStatus.make(configured: true, statuses: [.loading, .unconfigured], planName: nil) == ProviderStatus(text: "Connecting…", tone: .neutral))
    }

    @Test func disabledComesAfterNotSetUpAndBeforeTheHalves() {
        #expect(ProviderStatus.make(configured: false, enabled: false, statuses: [], planName: nil).text == "Not set up")
        #expect(ProviderStatus.make(configured: true, enabled: false, statuses: [.error], planName: "Pro") == ProviderStatus(text: "Disabled", tone: .neutral))
    }

    @Test func noEnabledHalvesReadsNothingSwitchedOn() {
        #expect(ProviderStatus.make(configured: true, enabled: true, statuses: [], planName: "Pro") == ProviderStatus(text: "Nothing switched on", tone: .neutral))
    }

    @Test func connectedShowsThePlan() {
        #expect(ProviderStatus.make(configured: true, statuses: [.ready], planName: "Pro").text == "Connected · Pro")
        #expect(ProviderStatus.make(configured: true, statuses: [.ready, .unconfigured], planName: nil).text == "Connected")
    }
}
