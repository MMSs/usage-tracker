import Testing
@testable import UsageTracker

@Suite struct ProviderRegistryTests {
    @Test func cursorHasNoShortWindowSoTodayIsDerived() {
        #expect(ProviderRegistry.descriptor(for: .cursor).shortWindowID == nil)
    }

    @Test func everyProviderHasADescriptorWithItsOwnID() {
        for provider in Provider.allCases {
            #expect(ProviderRegistry.descriptor(for: provider).id == provider)
        }
    }

    @Test func halvesHaveDisplayNames() {
        #expect(Half.subscription.displayName == "Plan usage")
        #expect(Half.api.displayName == "API spend")
    }

    @Test func eachHalfNamesTheServiceItTalksTo() {
        let anthropic = ProviderRegistry.descriptor(for: .anthropic)
        #expect(anthropic.service(for: .subscription) == HalfService(name: "claude.ai", host: "claude.ai"))
        #expect(anthropic.service(for: .api) == HalfService(name: "Anthropic API", host: "api.anthropic.com"))
        #expect(ProviderRegistry.descriptor(for: .cursor).service(for: .subscription) == HalfService(name: "Cursor", host: "cursor.com"))
    }

    @Test func aHalfWithoutAServiceFallsBackToTheProviderName() {
        #expect(ProviderRegistry.descriptor(for: .cursor).service(for: .api) == HalfService(name: "Cursor", host: "Cursor"))
    }

    @Test func registryListsCursorAnthropicOpenAIInOrder() {
        #expect(ProviderRegistry.all.map(\.id) == [.cursor, .anthropic, .openai])
    }

    @Test func cursorDescriptor() {
        let descriptor = ProviderRegistry.descriptor(for: .cursor)

        #expect(descriptor.displayName == "Cursor")
        #expect(descriptor.fields.map(\.id) == ["session-token"])
        #expect(descriptor.capabilities == ProviderCapabilities(
            hasSubscription: true, hasAPISpend: false, hasCycle: true, hasDailyChart: true, canStartSession: false
        ))
        #expect(descriptor.longWindowID == "cycle")
        #expect(descriptor.fields[0].title == "Session token")
        #expect(!descriptor.fields[0].isMultiline)
        #expect(descriptor.fields[0].helpSteps.count == 3)
        #expect(descriptor.fields[0].copyChip == "WorkosCursorSessionToken")
    }

    @Test func anthropicAndOpenAIHaveBothHalves() {
        for provider in [Provider.anthropic, .openai] {
            let descriptor = ProviderRegistry.descriptor(for: provider)

            #expect(!descriptor.subscriptionFields.isEmpty)
            #expect(descriptor.apiFields.map(\.id).contains("admin-key"))
            #expect(descriptor.capabilities.canStartSession)
            #expect(descriptor.shortWindowID == "session")
            #expect(descriptor.longWindowID == "weekly")
        }
    }

    @Test func fieldIDsAndHalvesMatchTheSpec() {
        let anthropic = ProviderRegistry.descriptor(for: .anthropic)
        #expect(anthropic.subscriptionFields.map(\.id) == ["session-key"])
        #expect(anthropic.apiFields.map(\.id) == ["admin-key", "api-budget"])

        let openai = ProviderRegistry.descriptor(for: .openai)
        #expect(openai.subscriptionFields.map(\.id) == ["auth-json"])
        #expect(openai.apiFields.map(\.id) == ["admin-key", "api-budget"])
        #expect(openai.subscriptionFields[0].isMultiline)
        #expect(openai.subscriptionFields[0].copyChip == "cat ~/.codex/auth.json | pbcopy")
        #expect(openai.apiFields[1].copyChip == nil)
        #expect(!openai.apiFields[1].isMultiline)
    }
}
