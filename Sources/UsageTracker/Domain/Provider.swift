import Foundation

/// Case order is the menu bar insertion order, so the first case is rightmost
/// on screen. The display order, left to right, is the reverse
/// (`AppModel.menuBarDisplayOrder`).
enum Provider: String, CaseIterable, Codable, Identifiable, Sendable {
    case cursor, openai, anthropic

    var id: String { rawValue }
}

enum Half: String, Codable, Sendable {
    case subscription, api

    /// Names the half in status and error text.
    var displayName: String {
        switch self {
        case .subscription: "Plan usage"
        case .api: "API spend"
        }
    }
}

/// What a half fetches from, for naming it in error messages.
struct HalfService: Equatable, Sendable {
    /// "Anthropic API".
    let name: String
    /// "api.anthropic.com".
    let host: String
}

struct CredentialField: Identifiable, Equatable, Sendable {
    let id: String
    let half: Half
    let title: String
    let isMultiline: Bool
    /// Markdown lines shown in the field's help disclosure.
    let helpSteps: [String]
    /// Text the copy chip puts on the clipboard.
    let copyChip: String?
    /// Checked before the value is saved.
    var format: CredentialFormat = .plain
}

struct ProviderCapabilities: Equatable, Sendable {
    let hasSubscription: Bool
    let hasAPISpend: Bool
    let hasCycle: Bool
    let hasDailyChart: Bool
    let canStartSession: Bool
}

struct ProviderDescriptor: Identifiable, Sendable {
    let id: Provider
    let displayName: String
    let capabilities: ProviderCapabilities
    let fields: [CredentialField]
    let services: [Half: HalfService]
    /// "session", or nil when the provider has no short window (Cursor).
    let shortWindowID: String?
    /// "weekly" or "cycle".
    let longWindowID: String

    var subscriptionFields: [CredentialField] { fields.filter { $0.half == .subscription } }
    var apiFields: [CredentialField] { fields.filter { $0.half == .api } }

    /// The half's service; the provider's name when none is listed.
    func service(for half: Half) -> HalfService {
        services[half] ?? HalfService(name: displayName, host: displayName)
    }
}

enum ProviderRegistry {
    static func descriptor(for provider: Provider) -> ProviderDescriptor {
        switch provider {
        case .cursor: cursor
        case .anthropic: anthropic
        case .openai: openai
        }
    }

    static var all: [ProviderDescriptor] {
        Provider.allCases.map(descriptor(for:))
    }

    private static let budgetExplanation = "Optional. Lets the ring, pacing, and alerts work for API spend. Not enforced anywhere."

    private static let cursor = ProviderDescriptor(
        id: .cursor,
        displayName: "Cursor",
        capabilities: ProviderCapabilities(
            hasSubscription: true, hasAPISpend: false, hasCycle: true, hasDailyChart: true, canStartSession: false
        ),
        fields: [
            CredentialField(
                id: "session-token",
                half: .subscription,
                title: "Session token",
                isMultiline: false,
                helpSteps: [
                    "Sign in to the [Cursor dashboard](https://cursor.com/dashboard) in Chrome.",
                    "Press **⌥⌘I** and open **Application › Cookies › cursor.com**.",
                    "Copy the value of `WorkosCursorSessionToken` and paste it into Settings.",
                ],
                copyChip: "WorkosCursorSessionToken"
            ),
        ],
        services: [.subscription: HalfService(name: "Cursor", host: "cursor.com")],
        shortWindowID: nil,
        longWindowID: "cycle"
    )

    private static let anthropic = ProviderDescriptor(
        id: .anthropic,
        displayName: "Anthropic",
        capabilities: ProviderCapabilities(
            hasSubscription: true, hasAPISpend: true, hasCycle: false, hasDailyChart: true, canStartSession: true
        ),
        fields: [
            CredentialField(
                id: "session-key",
                half: .subscription,
                title: "Session key",
                isMultiline: false,
                helpSteps: [
                    "Sign in to [claude.ai](https://claude.ai) in Chrome.",
                    "Press **⌥⌘I** and open **Application › Cookies › claude.ai**.",
                    "Copy the value of `sessionKey` (starts with `sk-ant-sid01-`) and paste it here.",
                    "Note: signing out of claude.ai in that browser invalidates the key.",
                ],
                copyChip: "sessionKey"
            ),
            CredentialField(
                id: "admin-key",
                half: .api,
                title: "Admin key",
                isMultiline: false,
                helpSteps: [
                    "Open [console.anthropic.com → Settings → Admin keys](https://console.anthropic.com/settings/admin-keys).",
                    "Create a key (any name), copy the `sk-ant-admin…` value, and paste it here.",
                    "Only organization admins can create one; it reads cost data and cannot call models.",
                ],
                copyChip: nil
            ),
            CredentialField(
                id: "api-budget",
                half: .api,
                title: "Monthly API budget",
                isMultiline: false,
                helpSteps: [budgetExplanation],
                copyChip: nil
            ),
        ],
        services: [
            .subscription: HalfService(name: "claude.ai", host: "claude.ai"),
            .api: HalfService(name: "Anthropic API", host: "api.anthropic.com"),
        ],
        shortWindowID: "session",
        longWindowID: "weekly"
    )

    private static let openai = ProviderDescriptor(
        id: .openai,
        displayName: "OpenAI",
        capabilities: ProviderCapabilities(
            hasSubscription: true, hasAPISpend: true, hasCycle: false, hasDailyChart: true, canStartSession: true
        ),
        fields: [
            CredentialField(
                id: "auth-json",
                half: .subscription,
                title: "Codex auth.json",
                isMultiline: true,
                helpSteps: [
                    "In Terminal run `codex login` if you have not already, then `cat ~/.codex/auth.json | pbcopy`.",
                    "Paste here. The app keeps it only in Keychain and never changes the file.",
                    "If Codex later asks you to log in again, re-paste the new file.",
                ],
                copyChip: "cat ~/.codex/auth.json | pbcopy",
                format: .codexAuthJSON
            ),
            CredentialField(
                id: "admin-key",
                half: .api,
                title: "Admin key",
                isMultiline: false,
                helpSteps: [
                    "Open [platform.openai.com → Settings → Organization → Admin keys](https://platform.openai.com/settings/organization/admin-keys).",
                    "Create a key, copy the `sk-admin-…` value, and paste it here.",
                    "Reads usage and costs only.",
                ],
                copyChip: nil
            ),
            CredentialField(
                id: "api-budget",
                half: .api,
                title: "Monthly API budget",
                isMultiline: false,
                helpSteps: [budgetExplanation],
                copyChip: nil
            ),
        ],
        services: [
            .subscription: HalfService(name: "ChatGPT", host: "chatgpt.com"),
            .api: HalfService(name: "OpenAI API", host: "api.openai.com"),
        ],
        shortWindowID: "session",
        longWindowID: "weekly"
    )
}
