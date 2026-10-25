import Foundation

protocol UsageHistoryStoring: AnyObject {
    func record(_ report: ProviderReport, provider: Provider, at date: Date)
    /// The last 24 hours of samples keyed by window id, oldest first.
    func samples(provider: Provider, now: Date) -> [String: [UsageSample]]
    func clear(provider: Provider)
}

final class UserDefaultsUsageHistoryStore: UsageHistoryStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(_ report: ProviderReport, provider: Provider, at date: Date) {
        // Every stored window is trimmed, so one that left the report ages out.
        var history = stored(provider: provider).mapValues { Self.trimmed($0, to: date) }

        for window in report.windows where window.percentUsed.isFinite {
            let percent = UInt8(clamping: Int(max(min(window.percentUsed, 1_000), -1_000).rounded()))
            var samples = history[window.id] ?? []

            let sample = UsageSample(date: date, percent: percent)

            // One sample a minute: a refresh in the same minute as the last replaces it.
            if let last = samples.last, Self.minute(of: last.date) == Self.minute(of: sample.date) {
                samples.removeLast()
            }
            samples.append(sample)
            history[window.id] = samples
        }

        let encoded = history.compactMapValues { $0.isEmpty ? nil : UsageSampleCoding.encode($0) }
        defaults.set(encoded, forKey: Self.key(provider))
    }

    func samples(provider: Provider, now: Date) -> [String: [UsageSample]] {
        stored(provider: provider).compactMapValues { samples in
            let recent = Self.trimmed(samples, to: now)

            return recent.isEmpty ? nil : recent
        }
    }

    func clear(provider: Provider) {
        defaults.removeObject(forKey: Self.key(provider))
    }

    /// Corrupt or wrongly typed data reads as no history.
    private func stored(provider: Provider) -> [String: [UsageSample]] {
        guard let raw = defaults.dictionary(forKey: Self.key(provider)) as? [String: Data] else {
            return [:]
        }

        return raw.mapValues(UsageSampleCoding.decode)
    }

    /// Samples in `(date - 24 h, date]`: older and future ones are dropped.
    private static func trimmed(_ samples: [UsageSample], to date: Date) -> [UsageSample] {
        let oldest = date.addingTimeInterval(-retention)

        return samples.filter { $0.date > oldest && $0.date <= date }.sorted { $0.date < $1.date }
    }

    private static func key(_ provider: Provider) -> String {
        "history.\(provider.rawValue)"
    }

    private static let retention: TimeInterval = 24 * 60 * 60

    /// The wall-clock minute of the encoded (whole-second) date.
    private static func minute(of date: Date) -> UInt32 {
        UInt32(clamping: Int(date.timeIntervalSince1970)) / 60
    }
}
