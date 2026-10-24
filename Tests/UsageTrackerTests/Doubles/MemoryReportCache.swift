@testable import UsageTracker

final class MemoryReportCache: ReportCaching {
    var entries: [String: CachedReport] = [:]
    private(set) var clearCount = 0

    func cached(provider: Provider, half: Half) -> CachedReport? {
        entries["\(provider.rawValue).\(half.rawValue)"]
    }

    func store(_ cached: CachedReport, provider: Provider, half: Half) {
        entries["\(provider.rawValue).\(half.rawValue)"] = cached
    }

    func clear(provider: Provider, half: Half) {
        clearCount += 1
        entries["\(provider.rawValue).\(half.rawValue)"] = nil
    }
}
