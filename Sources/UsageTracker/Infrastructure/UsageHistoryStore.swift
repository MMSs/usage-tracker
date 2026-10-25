import Foundation

protocol UsageHistoryStoring: AnyObject {
    func record(_ report: ProviderReport, provider: Provider, at date: Date)
    /// The last 8 days of samples keyed by window id, oldest first.
    func samples(provider: Provider, now: Date) -> [String: [UsageSample]]
    func clear(provider: Provider)
}

final class UserDefaultsUsageHistoryStore: UsageHistoryStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(_ report: ProviderReport, provider: Provider, at date: Date) {
        // Every stored window is trimmed and thinned, so one that left the report ages out.
        var history = stored(provider: provider).mapValues { Self.thinned(Self.trimmed($0, to: date), to: date) }

        for window in report.windows where window.percentUsed.isFinite {
            let percent = UInt8(clamping: Int(max(min(window.percentUsed, 1_000), -1_000).rounded()))
            var samples = history[window.id] ?? []

            let sample = UsageSample(date: date, percent: percent)

            // One sample a minute: a refresh in the same minute as the last replaces it.
            if let last = samples.last, Self.minute(of: last.date) == Self.minute(of: sample.date) {
                samples.removeLast()
            }
            samples.append(sample)
            history[window.id] = Self.thinned(samples, to: date)
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

    /// Samples in `(date - 8 d, date]`: older and future ones are dropped.
    private static func trimmed(_ samples: [UsageSample], to date: Date) -> [UsageSample] {
        let oldest = date.addingTimeInterval(-retention)

        return samples.filter { $0.date > oldest && $0.date <= date }.sorted { $0.date < $1.date }
    }

    private static func key(_ provider: Provider) -> String {
        "history.\(provider.rawValue)"
    }

    static let retention: TimeInterval = 8 * 86_400
    static let fineSpan: TimeInterval = 86_400

    /// Samples older than `fineSpan` before `date` keep only the latest of each hour.
    private static func thinned(_ samples: [UsageSample], to date: Date) -> [UsageSample] {
        let cutoff = date.addingTimeInterval(-fineSpan)
        var result: [UsageSample] = []

        for sample in samples {
            if sample.date < cutoff, let last = result.last, last.date < cutoff, hour(of: last.date) == hour(of: sample.date) {
                result.removeLast()
            }
            result.append(sample)
        }

        return result
    }

    private static func hour(of date: Date) -> UInt32 {
        UInt32(clamping: Int(date.timeIntervalSince1970)) / 3600
    }

    /// The wall-clock minute of the encoded (whole-second) date.
    private static func minute(of date: Date) -> UInt32 {
        UInt32(clamping: Int(date.timeIntervalSince1970)) / 60
    }
}
