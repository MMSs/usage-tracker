import Foundation

/// Everything the claude.ai endpoints return for one refresh. The extras are
/// nil when the account has no overage or the endpoint failed.
struct AnthropicSubscriptionSnapshot: Equatable, Sendable {
    let usage: AnthropicUsageResponse
    let planName: String?
    let spendLimit: AnthropicOverageSpendLimit?
    let creditGrant: AnthropicOverageCreditGrant?
}
