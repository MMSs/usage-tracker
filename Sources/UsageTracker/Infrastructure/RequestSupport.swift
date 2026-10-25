import Foundation

/// Pieces every provider service builds the same way.
enum RequestSupport {
    /// RFC 3986 unreserved characters; everything else in a query value is escaped.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

        return "UsageTracker/\(version) (https://github.com/MMSs/usage-tracker)"
    }

    static func encodedQuery(_ query: [(name: String, value: String)]) -> String {
        query
            .map { "\($0.name)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
    }

    /// nil unless `text` is a plain decimal number; `Decimal(string:)` alone
    /// stops at the first bad character, so "12,5" would read as 12.
    static func decimal(fromNumericString text: String) -> Decimal? {
        guard text.range(of: #"^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else {
            return nil
        }

        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}
