import Foundation

enum OpenAIReportMapper {
    private static let sessionSeconds = 18000
    private static let weeklySeconds = 604_800

    /// A window with a usable length, before ids are made unique.
    private struct Classified {
        let baseID: String
        let label: String
        let seconds: Int
        let window: OpenAIUsageResponse.Window

        /// Session first, then weekly, then everything else by length.
        var rank: Int {
            switch seconds {
            case sessionSeconds: 0
            case weeklySeconds: 1
            default: 2
            }
        }
    }

    static func subscription(_ usage: OpenAIUsageResponse, now: Date) -> ProviderReport {
        var usedIDs: Set<String> = []
        let parents = classify([usage.primary, usage.secondary]).sorted {
            ($0.rank, $0.seconds) < ($1.rank, $1.seconds)
        }

        var windows: [LimitWindow] = []
        for (index, parent) in parents.enumerated() {
            let parentID = uniqueID(parent.baseID, used: &usedIDs)
            windows.append(limitWindow(parent, id: parentID, parentID: nil, label: parent.label, now: now))

            // Children attach to the first top-level window of their length.
            guard parents.firstIndex(where: { $0.seconds == parent.seconds }) == index else { continue }

            for limit in usage.additional {
                for child in classify([limit.primary, limit.secondary]) where child.seconds == parent.seconds {
                    windows.append(limitWindow(
                        child,
                        id: uniqueID("\(parentID):\(limit.name)", used: &usedIDs),
                        parentID: parentID,
                        label: displayName(limit.name),
                        now: now
                    ))
                }
            }
        }

        var extras: [MoneyRow] = []
        if let credits = usage.credits, credits.hasCredits, !credits.unlimited, let balance = credits.balance {
            extras.append(MoneyRow(id: "credits", label: "Credits", amount: balance, limit: nil))
        }

        return ProviderReport(planName: planName(usage.planType), windows: windows, extras: extras, spend: nil)
    }

    static func planName(_ planType: String?) -> String? {
        guard let text = planType?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        return capitalizingFirst(text)
    }

    /// Windows without a positive length cannot be told apart, so they are dropped.
    private static func classify(_ windows: [OpenAIUsageResponse.Window?]) -> [Classified] {
        windows.compactMap { window in
            guard let window, let seconds = window.windowSeconds, seconds > 0 else {
                return nil
            }

            switch seconds {
            case sessionSeconds:
                return Classified(baseID: "session", label: "Session", seconds: seconds, window: window)
            case weeklySeconds:
                return Classified(baseID: "weekly", label: "Weekly", seconds: seconds, window: window)
            default:
                return Classified(baseID: "window:\(seconds)", label: humanized(seconds: seconds), seconds: seconds, window: window)
            }
        }
    }

    private static func limitWindow(
        _ classified: Classified,
        id: String,
        parentID: String?,
        label: String,
        now: Date
    ) -> LimitWindow {
        // A reset that has passed means the window has closed.
        let resetsAt = classified.window.resetAt.flatMap { $0 > now ? $0 : nil }

        return LimitWindow(
            id: id,
            label: label,
            percentUsed: classified.window.usedPercent ?? 0,
            resetsAt: resetsAt,
            parentID: parentID,
            windowLength: TimeInterval(classified.seconds)
        )
    }

    /// `id`, or `id:2`, `id:3`... when it is already taken.
    private static func uniqueID(_ id: String, used: inout Set<String>) -> String {
        var candidate = id
        var suffix = 2
        while !used.insert(candidate).inserted {
            candidate = "\(id):\(suffix)"
            suffix += 1
        }

        return candidate
    }

    private static func humanized(seconds: Int) -> String {
        let (count, unit) = switch seconds {
        case ..<3600: (seconds / 60, "minute")
        case ..<86400: (seconds / 3600, "hour")
        default: (seconds / 86400, "day")
        }

        return count == 1 ? "\(count) \(unit)" : "\(count) \(unit)s"
    }

    /// `codex_other` reads as "Codex other".
    private static func displayName(_ name: String) -> String {
        capitalizingFirst(name.replacingOccurrences(of: "_", with: " "))
    }

    private static func capitalizingFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
