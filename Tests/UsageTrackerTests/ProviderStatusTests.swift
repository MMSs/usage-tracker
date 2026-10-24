import Testing
@testable import UsageTracker

@Suite struct ProviderStatusTests {
    private let offline = HalfErrorMessage(
        text: "Plan usage: Couldn't reach claude.ai.", fix: "Check your connection; it retries automatically.", severity: .warning
    )
    private let expired = HalfErrorMessage(
        text: "API spend: Credential expired — replace it in Settings", fix: nil, severity: .critical
    )

    @Test func unconfiguredWinsOverEverything() {
        #expect(ProviderStatus.make(configured: false, statuses: [.error], errors: [offline], planName: "Pro") == ProviderStatus(text: "Not set up", tone: .neutral))
    }

    @Test func worstHalfDecidesTheToneWithoutAMessage() {
        #expect(ProviderStatus.make(configured: true, statuses: [.ready, .expired], planName: nil) == ProviderStatus(text: "Credential expired", tone: .bad))
        #expect(ProviderStatus.make(configured: true, statuses: [.ready, .error], planName: nil) == ProviderStatus(text: "Unable to refresh", tone: .warning))
        #expect(ProviderStatus.make(configured: true, statuses: [.loading, .unconfigured], planName: nil) == ProviderStatus(text: "Connecting…", tone: .neutral))
    }

    @Test func aFailingHalfShowsItsMessageAndFix() {
        let status = ProviderStatus.make(configured: true, statuses: [.error, .ready], errors: [offline], planName: "Pro")
        #expect(status == ProviderStatus(lines: [
            .init(text: "Plan usage: Couldn't reach claude.ai. Check your connection; it retries automatically.", tone: .warning),
        ]))
    }

    @Test func twoFailingHalvesGetALineEach() {
        let status = ProviderStatus.make(configured: true, statuses: [.error, .expired], errors: [offline, expired], planName: nil)
        #expect(status.lines == [
            .init(text: "Plan usage: Couldn't reach claude.ai. Check your connection; it retries automatically.", tone: .warning),
            .init(text: "API spend: Credential expired — replace it in Settings", tone: .bad),
        ])
    }

    @Test func aHalfWaitingForAnOrganizationIsNeutralGuidance() {
        let choose = HalfErrorMessage(
            text: "Plan usage: Choose an organization in Settings", fix: nil, severity: .notice,
            settingsLine: "Plan usage: Choose an organization on the Subscription tab."
        )
        let status = ProviderStatus.make(configured: true, statuses: [.needsOrganization, .ready], errors: [choose], planName: nil)
        #expect(status.lines == [.init(text: "Plan usage: Choose an organization on the Subscription tab.", tone: .neutral)])
        #expect(ProviderStatus.make(configured: true, statuses: [.needsOrganization], planName: nil) == ProviderStatus(text: "Choose an organization", tone: .neutral))
    }

    @Test func disabledComesAfterNotSetUpAndBeforeTheHalves() {
        #expect(ProviderStatus.make(configured: false, enabled: false, statuses: [], planName: nil) == ProviderStatus(text: "Not set up", tone: .neutral))
        #expect(ProviderStatus.make(configured: true, enabled: false, statuses: [.error], errors: [offline], planName: "Pro") == ProviderStatus(text: "Disabled", tone: .neutral))
    }

    @Test func noEnabledHalvesReadsNothingSwitchedOn() {
        #expect(ProviderStatus.make(configured: true, enabled: true, statuses: [], planName: "Pro") == ProviderStatus(text: "Nothing switched on", tone: .neutral))
    }

    @Test func connectedShowsThePlan() {
        #expect(ProviderStatus.make(configured: true, statuses: [.ready], planName: "Pro") == ProviderStatus(text: "Connected · Pro", tone: .good))
        #expect(ProviderStatus.make(configured: true, statuses: [.ready, .unconfigured], planName: nil) == ProviderStatus(text: "Connected", tone: .good))
    }
}
