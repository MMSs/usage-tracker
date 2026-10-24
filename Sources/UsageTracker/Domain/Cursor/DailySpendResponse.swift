import Foundation

struct DailySpendResponse: Decodable, Equatable {
    struct Entry: Decodable, Equatable {
        let day: String
        var category = "Other"
        let spendCents: Int
        var totalTokens: String?

        init(day: String, category: String = "Other", spendCents: Int, totalTokens: String? = nil) {
            self.day = day
            self.category = category
            self.spendCents = spendCents
            self.totalTokens = totalTokens
        }

        private enum CodingKeys: String, CodingKey {
            case day, category, spendCents, totalTokens
        }

        // Cursor omits spendCents on days with no billed spend.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            day = try container.decode(String.self, forKey: .day)
            category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Other"
            spendCents = try container.decodeIfPresent(Int.self, forKey: .spendCents) ?? 0
            totalTokens = try container.decodeIfPresent(String.self, forKey: .totalTokens)
        }
    }

    let dailySpend: [Entry]
}

enum CursorDayConversion {
    /// Milliseconds of UTC midnight for the calendar day of `date`.
    static func apiMilliseconds(forLocalDay date: Date, calendar: Calendar = .current) -> Int64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = utc.date(from: components)!

        return Int64(midnight.timeIntervalSince1970 * 1000)
    }

    /// Local-midnight date for the UTC calendar day containing the API timestamp.
    static func localDay(forAPIMilliseconds milliseconds: Double, calendar: Calendar) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = utc.dateComponents(
            [.year, .month, .day],
            from: Date(timeIntervalSince1970: milliseconds / 1000)
        )

        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone

        return local.date(from: components)!
    }
}
