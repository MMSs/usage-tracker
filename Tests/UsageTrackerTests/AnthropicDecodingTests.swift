import Foundation
import Testing
@testable import UsageTracker

@Suite struct AnthropicDecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))

        return try Data(contentsOf: url)
    }

    private func usage(_ json: String) throws -> AnthropicUsageResponse {
        try AnthropicUsageResponse.decoder().decode(AnthropicUsageResponse.self, from: Data(json.utf8))
    }

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test func fixtureUsageDecodesWindowsAndScopedLimits() throws {
        let response = try AnthropicUsageResponse.decoder().decode(
            AnthropicUsageResponse.self,
            from: fixture("anthropic-usage")
        )

        let fiveHourReset = try #require(response.fiveHour?.resetsAt)
        #expect(response.fiveHour?.utilization == 37)
        #expect(abs(fiveHourReset.timeIntervalSince(try date("2026-10-24T19:59:59Z")) - 0.661633) < 0.001)
        #expect(response.sevenDay?.utilization == 62.5)
        #expect(response.sevenDay?.resetsAt == (try date("2026-10-29T07:00:00Z")))

        #expect(response.limits == [
            AnthropicUsageResponse.ScopedLimit(
                kind: "weekly_scoped",
                percent: 18.5,
                resetsAt: try date("2026-10-29T07:00:00Z"),
                modelID: "claude-opus-5-5",
                modelDisplayName: "Opus"
            ),
            AnthropicUsageResponse.ScopedLimit(
                kind: "weekly_scoped",
                percent: 54,
                resetsAt: try date("2026-10-29T07:00:00Z"),
                modelID: "claude-sonnet-5-5",
                modelDisplayName: "Sonnet"
            ),
            AnthropicUsageResponse.ScopedLimit(
                kind: "daily_scoped",
                percent: 3,
                resetsAt: try date("2026-10-25T00:00:00Z"),
                modelID: "claude-haiku-5-5",
                modelDisplayName: "Haiku"
            ),
        ])

        #expect(Set(response.legacyModelWindows.keys) == ["opus", "sonnet"])
        #expect(response.legacyModelWindows["opus"]?.utilization == 12)
        #expect(response.legacyModelWindows["sonnet"]?.utilization == 48)
        #expect(response.legacyModelWindows["sonnet"]?.resetsAt == nil)
    }

    @Test func percentsDecodeFromNumbersAndStrings() throws {
        let response = try usage("""
        {"five_hour":{"utilization":"41.5"},"seven_day":{"utilization":7},
         "limits":[{"kind":"weekly_scoped","percent":"54"},{"kind":"weekly_scoped","percent":12.25},
                   {"kind":"weekly_scoped","percent":"n/a"},{"kind":"weekly_scoped","percent":null}]}
        """)

        #expect(response.fiveHour?.utilization == 41.5)
        #expect(response.sevenDay?.utilization == 7)
        #expect(response.limits.map(\.percent) == [54, 12.25, nil, nil])
    }

    @Test func lossyNumberDecodesNumbersStringsAndNull() throws {
        func decode(_ json: String) throws -> Double? {
            try JSONDecoder().decode([LossyNumber].self, from: Data(json.utf8))[0].value
        }

        #expect(try decode("[3]") == 3)
        #expect(try decode("[3.5]") == 3.5)
        #expect(try decode(#"["3.5"]"#) == 3.5)
        #expect(try decode(#"["abc"]"#) == nil)
        #expect(try decode("[null]") == nil)
        #expect(try decode("[true]") == nil)
    }

    @Test(arguments: ["nan", "NaN", "inf", "-inf", "Infinity", "1e999"])
    func lossyNumberRejectsNonFiniteStrings(text: String) throws {
        let values = try JSONDecoder().decode([LossyNumber].self, from: Data(#"["\#(text)"]"#.utf8))

        #expect(values[0].value == nil)
    }

    @Test func unknownKindsAndMissingScopesAreSkipped() throws {
        let response = try usage("""
        {"limits":[
          {"kind":"weekly_scoped","percent":10,"resets_at":"2026-10-29T07:00:00Z"},
          {"kind":"daily_scoped","percent":3,"scope":{"model":{"id":"m","display_name":"M"}}},
          {"kind":"brand_new_kind","percent":1,"scope":{"region":"eu"}},
          {"kind":"weekly_scoped","scope":{"model":{"id":"only-id"}}},
          {"percent":5},
          "garbage",
          {"kind":"weekly_scoped","percent":2}
        ]}
        """)

        #expect(response.limits.map(\.kind) == [
            "weekly_scoped", "daily_scoped", "brand_new_kind", "weekly_scoped", "weekly_scoped",
        ])
        #expect(response.limits[0].modelID == nil)
        #expect(response.limits[0].modelDisplayName == nil)
        #expect(response.limits[1].modelID == "m")
        #expect(response.limits[2].modelID == nil)
        #expect(response.limits[3].modelID == "only-id")
        #expect(response.limits[3].modelDisplayName == nil)
        #expect(response.limits[3].percent == nil)
    }

    @Test func missingOrMalformedLimitsDefaultToEmpty() throws {
        #expect(try usage("{}").limits == [])
        #expect(try usage(#"{"limits":null}"#).limits == [])
        #expect(try usage(#"{"limits":"oops"}"#).limits == [])
    }

    @Test func legacySevenDayKeysAreCollected() throws {
        let response = try usage("""
        {"seven_day":{"utilization":1},
         "seven_day_opus":{"utilization":20,"resets_at":"2026-10-29T07:00:00Z"},
         "seven_day_oauth_apps":null,
         "seven_day_cowork":"unexpected",
         "seven_day_":{"utilization":9},
         "sevenday_other":{"utilization":9},
         "one_day_x":{"utilization":9}}
        """)

        #expect(Set(response.legacyModelWindows.keys) == ["opus"])
        #expect(response.legacyModelWindows["opus"]?.utilization == 20)
        #expect(response.sevenDay?.utilization == 1)
    }

    @Test func nullResetsAtDecodesAsNil() throws {
        let response = try usage("""
        {"five_hour":{"utilization":5,"resets_at":null},"seven_day":{"utilization":6},
         "limits":[{"kind":"weekly_scoped","percent":1,"resets_at":null}]}
        """)

        #expect(response.fiveHour?.resetsAt == nil)
        #expect(response.sevenDay?.resetsAt == nil)
        #expect(response.limits[0].resetsAt == nil)
    }

    @Test func nullWindowsDecodeAsNil() throws {
        let response = try usage(#"{"five_hour":null,"seven_day":null}"#)

        #expect(response.fiveHour == nil)
        #expect(response.sevenDay == nil)
    }

    @Test(arguments: [
        "2026-10-24T19:59:59.661633+00:00",
        "2026-10-24T19:59:59.661633Z",
        "2026-10-24T19:59:59.661+00:00",
        "2026-10-24T19:59:59.661Z",
        "2026-10-24T19:59:59+00:00",
        "2026-10-24T19:59:59Z",
    ])
    func datesDecodeWithAnyFractionAndOffset(_ text: String) throws {
        let response = try usage(#"{"five_hour":{"utilization":1,"resets_at":"\#(text)"}}"#)
        let reset = try #require(response.fiveHour?.resetsAt)
        let whole = try date("2026-10-24T19:59:59Z")

        #expect(reset.timeIntervalSince(whole) >= 0)
        #expect(reset.timeIntervalSince(whole) < 0.67)
        #expect(text.contains(".") == (reset != whole))
    }

    @Test func microsecondFractionsKeepMilliseconds() throws {
        let response = try usage(#"{"five_hour":{"utilization":1,"resets_at":"2026-10-24T19:59:59.661633+00:00"}}"#)
        let reset = try #require(response.fiveHour?.resetsAt)

        #expect(abs(reset.timeIntervalSince(try date("2026-10-24T19:59:59Z")) - 0.661) < 0.001)
    }

    @Test func unparseableResetsAtDecodesAsNil() throws {
        let response = try usage(#"{"five_hour":{"utilization":1,"resets_at":"soon"}}"#)

        #expect(response.fiveHour?.utilization == 1)
        #expect(response.fiveHour?.resetsAt == nil)
    }

    @Test func overageShapesDecode() throws {
        let limit = try JSONDecoder().decode(
            AnthropicOverageSpendLimit.self,
            from: fixture("anthropic-overage-spend-limit")
        )
        #expect(limit == AnthropicOverageSpendLimit(
            isEnabled: true, usedCredits: 12.34, monthlyCreditLimit: 50, currency: "USD"
        ))

        let grant = try JSONDecoder().decode(
            AnthropicOverageCreditGrant.self,
            from: fixture("anthropic-overage-credit-grant")
        )
        #expect(grant == AnthropicOverageCreditGrant(remainingBalance: 7.5, totalGranted: 25, currency: "USD"))
    }

    @Test func overageNumbersDecodeFromStringsAndNulls() throws {
        let limit = try JSONDecoder().decode(
            AnthropicOverageSpendLimit.self,
            from: Data(#"{"is_enabled":false,"used_credits":"4.5","monthly_credit_limit":null}"#.utf8)
        )
        #expect(limit == AnthropicOverageSpendLimit(
            isEnabled: false, usedCredits: 4.5, monthlyCreditLimit: 0, currency: nil
        ))

        let grant = try JSONDecoder().decode(
            AnthropicOverageCreditGrant.self,
            from: Data(#"{"remaining_balance":"3"}"#.utf8)
        )
        #expect(grant == AnthropicOverageCreditGrant(remainingBalance: 3, totalGranted: nil, currency: nil))
    }

    @Test func organizationsDecodeFromArrayAndObject() throws {
        let fromArray = try JSONDecoder().decode(
            AnthropicOrganizationsResponse.self,
            from: fixture("anthropic-organizations")
        )
        #expect(fromArray.organizations == [
            AnthropicOrganizationsResponse.Organization(
                uuid: "3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14",
                name: "sam@example.com's Organization",
                rateLimitTier: "default_claude_max_5x",
                capabilities: ["chat", "claude_max"]
            ),
        ])

        let fromObject = try JSONDecoder().decode(
            AnthropicOrganizationsResponse.self,
            from: Data(#"{"organizations":[{"uuid":"u1"},{"uuid":"u2","name":"Two","extra":1}]}"#.utf8)
        )
        #expect(fromObject.organizations.map(\.uuid) == ["u1", "u2"])
        #expect(fromObject.organizations[0].name == nil)
        #expect(fromObject.organizations[0].rateLimitTier == nil)
        #expect(fromObject.organizations[0].capabilities == nil)
        #expect(fromObject.organizations[1].name == "Two")

        let empty = try JSONDecoder().decode(AnthropicOrganizationsResponse.self, from: Data("[]".utf8))
        #expect(empty.organizations.isEmpty)
    }

    @Test func organizationsSkipMalformedElementsInBothShapes() throws {
        let elements = #"[{"name":"no uuid"},"garbage",{"uuid":"a"},{"uuid":3},{"uuid":"b"}]"#
        let fromArray = try JSONDecoder().decode(AnthropicOrganizationsResponse.self, from: Data(elements.utf8))
        let fromObject = try JSONDecoder().decode(
            AnthropicOrganizationsResponse.self,
            from: Data(#"{"organizations":\#(elements)}"#.utf8)
        )

        #expect(fromArray.organizations.map(\.uuid) == ["a", "b"])
        #expect(fromObject.organizations.map(\.uuid) == ["a", "b"])
    }

    @Test func primaryOrganizationPrefersChat() {
        typealias Organization = AnthropicOrganizationsResponse.Organization
        let api = Organization(uuid: "api", capabilities: ["api"])
        let chat = Organization(uuid: "chat", capabilities: ["api", "chat"])

        #expect(AnthropicOrganizationsResponse(organizations: [api, chat]).primary == chat)
        #expect(AnthropicOrganizationsResponse(organizations: [api, Organization(uuid: "bare")]).primary == api)
        #expect(AnthropicOrganizationsResponse(organizations: []).primary == nil)
    }

    @Test func planNameFromTier() {
        #expect(AnthropicPlanName.from(rateLimitTier: "default_claude_max_5x", capabilities: nil) == "Max 5x")
        #expect(AnthropicPlanName.from(rateLimitTier: "default_claude_max_20x", capabilities: nil) == "Max 20x")
        #expect(AnthropicPlanName.from(rateLimitTier: "default_claude_pro", capabilities: nil) == "Pro")
        #expect(AnthropicPlanName.from(rateLimitTier: "DEFAULT_CLAUDE_TEAM", capabilities: nil) == "Team")
        #expect(AnthropicPlanName.from(rateLimitTier: "default_enterprise", capabilities: nil) == "Enterprise")
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: nil) == nil)
        #expect(AnthropicPlanName.from(rateLimitTier: "default_free", capabilities: ["chat"]) == nil)
    }

    @Test func planNameFallsBackToCapabilities() {
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["chat", "claude_pro"]) == "Pro")
        #expect(AnthropicPlanName.from(rateLimitTier: "default_claude_max_5x", capabilities: ["claude_pro"]) == "Max 5x")
    }

    @Test func planNameMatchesCapabilityTokensExactly() {
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["chat", "project", "promo"]) == nil)
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["claude_pro_extra", "teamwork"]) == nil)
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["Claude_Team"]) == "Team")
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["claude_enterprise"]) == "Enterprise")
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["default_claude_max_5x"]) == "Max 5x")
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["default_claude_max_20x"]) == "Max 20x")
    }

    @Test func bareMaxCapabilityCannotTellTheMultiplier() {
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["chat", "claude_max"]) == "Max")
        #expect(AnthropicPlanName.from(rateLimitTier: "default_claude_max_20x", capabilities: ["claude_max"]) == "Max 20x")
    }

    @Test func highestPlanWinsRegardlessOfOrder() {
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["claude_pro", "claude_max"]) == "Max")
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["claude_max", "claude_pro"]) == "Max")
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["claude_pro", "claude_team"]) == "Team")
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["claude_team", "claude_enterprise"]) == "Enterprise")
        #expect(AnthropicPlanName.from(rateLimitTier: nil, capabilities: ["max_5x", "max_20x"]) == "Max 20x")
        #expect(AnthropicPlanName.from(rateLimitTier: "default_claude_pro", capabilities: ["claude_max_5x"]) == "Max 5x")
    }
}
