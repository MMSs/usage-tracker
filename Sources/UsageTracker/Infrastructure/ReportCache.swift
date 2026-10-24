import Foundation

struct CachedReport: Codable, Equatable {
    let report: ProviderReport
    let fetchedAt: Date
}

protocol ReportCaching: AnyObject {
    func cached(provider: Provider, half: Half) -> CachedReport?
    func store(_ cached: CachedReport, provider: Provider, half: Half)
    func clear(provider: Provider, half: Half)
}

final class UserDefaultsReportCache: ReportCaching {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func cached(provider: Provider, half: Half) -> CachedReport? {
        guard let data = defaults.data(forKey: Self.key(provider: provider, half: half)) else {
            return nil
        }

        return try? Self.decoder.decode(CachedReport.self, from: data)
    }

    func store(_ cached: CachedReport, provider: Provider, half: Half) {
        guard let data = try? Self.encoder.encode(cached) else {
            return
        }

        defaults.set(data, forKey: Self.key(provider: provider, half: half))
    }

    func clear(provider: Provider, half: Half) {
        defaults.removeObject(forKey: Self.key(provider: provider, half: half))
    }

    private static func key(provider: Provider, half: Half) -> String {
        "report.\(provider.rawValue).\(half.rawValue)"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
