import Foundation
import Testing
@testable import UsageTracker

@Suite struct OpenAIDecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))

        return try Data(contentsOf: url)
    }

    private func usage(_ json: String) throws -> OpenAIUsageResponse {
        try JSONDecoder().decode(OpenAIUsageResponse.self, from: Data(json.utf8))
    }

    @Test func fixtureDecodesWindowsAndCredits() throws {
        let response = try JSONDecoder().decode(OpenAIUsageResponse.self, from: fixture("openai-wham-usage"))

        #expect(response.planType == "plus")
        #expect(response.primary == OpenAIUsageResponse.Window(
            usedPercent: 41,
            windowSeconds: 18000,
            resetAt: Date(timeIntervalSince1970: 1_792_890_000),
            resetAfterSeconds: 7800
        ))
        #expect(response.secondary?.usedPercent == 70)
        #expect(response.secondary?.windowSeconds == 604_800)
        #expect(response.secondary?.resetAt == Date(timeIntervalSince1970: 1_793_140_000))
        #expect(response.additional.isEmpty)
        #expect(response.credits == OpenAIUsageResponse.Credits(hasCredits: true, unlimited: false, balance: Decimal(string: "12.50")))
    }

    @Test func stringPercentsDecode() throws {
        let response = try JSONDecoder().decode(OpenAIUsageResponse.self, from: fixture("openai-wham-usage-additional"))

        #expect(response.primary?.usedPercent == 55)
        #expect(response.secondary?.usedPercent == 12)
        #expect(response.credits?.balance == 0)
        #expect(response.additional.map(\.name) == ["codex_other"])
        #expect(response.additional.first?.primary?.usedPercent == 30)
        #expect(response.additional.first?.secondary == nil)
    }

    @Test func nullAdditionalLimitsDecodeAsEmpty() throws {
        let response = try usage(#"{"plan_type": "plus", "additional_rate_limits": null}"#)

        #expect(response.additional.isEmpty)
    }

    @Test func malformedCreditsDoNotFailTheResponse() throws {
        let response = try usage(#"{"plan_type": "plus", "credits": "x", "rate_limit": {"primary_window": {"used_percent": 5}}}"#)

        #expect(response.credits == nil)
        #expect(response.primary?.usedPercent == 5)
    }

    @Test func aBalanceWithTrailingTextIsUnknown() throws {
        let response = try usage(#"{"plan_type": "plus", "credits": {"has_credits": true, "balance": "12abc"}}"#)

        #expect(response.credits?.hasCredits == true)
        #expect(response.credits?.balance == nil)
        #expect(try usage(#"{"credits": {"balance": " 7.25 "}}"#).credits?.balance == Decimal(string: "7.25"))
    }

    @Test func resetAfterSecondsDecodes() throws {
        let response = try JSONDecoder().decode(OpenAIUsageResponse.self, from: fixture("openai-wham-usage"))

        #expect(response.primary?.resetAfterSeconds == 7800)
        #expect(response.secondary?.resetAfterSeconds == 259_200)
    }

    @Test func unreadableResetIsFlagged() throws {
        func window(_ fields: String) throws -> OpenAIUsageResponse.Window {
            let json = #"{"rate_limit": {"primary_window": {"used_percent": 5\#(fields)}}}"#

            return try #require(usage(json).primary)
        }

        let unreadable = try window(#", "reset_at": "soon""#)
        #expect(unreadable.resetAt == nil)
        #expect(unreadable.hasUnreadableReset)
        #expect(try window(#", "reset_at": null"#).hasUnreadableReset == false)
        #expect(try window("").hasUnreadableReset == false)
        #expect(try window(#", "reset_at": "1792890000""#).hasUnreadableReset == false)
    }

    @Test func missingRateLimitDecodesWithoutWindows() throws {
        let response = try usage(#"{"plan_type": "free", "rate_limit": null}"#)

        #expect(response.planType == "free")
        #expect(response.primary == nil)
        #expect(response.secondary == nil)
    }
}
