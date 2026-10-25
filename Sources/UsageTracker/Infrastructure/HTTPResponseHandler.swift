import Foundation
import os

/// Status and transport mapping shared by every provider's services.
enum HTTPResponseHandler {
    /// `overrides` replaces the shared error for a status, for a service that
    /// must tell it apart from the statuses mapped alongside it.
    @MainActor
    static func data(for request: URLRequest, client: HTTPClient, overrides: [Int: any Error] = [:]) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let endpoint = LogFormat.endpoint(request.url)
        let start = ContinuousClock.now

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch {
            // A cancelled request is not a failure; let callers tell the
            // difference. A session that cancels while the task is still
            // wanted is one, or the half would keep its old report unexplained.
            if error is CancellationError || ((error as? URLError)?.code == .cancelled && Task.isCancelled) {
                Log.http.debug("\(method, privacy: .public) \(endpoint, privacy: .public) cancelled")
                throw CancellationError()
            }

            let code = (error as? URLError).map { "URLError \($0.code.rawValue)" } ?? String(describing: type(of: error))
            Log.http.notice("\(method, privacy: .public) \(endpoint, privacy: .public) transport error \(code, privacy: .public)")
            throw FetchError.transport
        }

        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.http.notice("\(method, privacy: .public) \(endpoint, privacy: .public) non-HTTP response")
            throw FetchError.invalidResponse
        }

        let status = httpResponse.statusCode
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "-"
        let line = "\(method) \(endpoint) \(status) \(contentType) \(milliseconds) ms"
        if (200...299).contains(status) {
            Log.http.info("\(line, privacy: .public)")
        } else {
            Log.http.notice("\(line, privacy: .public)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let error = overrides[httpResponse.statusCode] {
                throw error
            }

            switch httpResponse.statusCode {
            case 401:
                throw FetchError.unauthorized
            case 403:
                // An HTML 403 is a bot-protection challenge, not an expired session.
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                if contentType.hasPrefix("text/html") {
                    throw FetchError.challenge
                }
                throw FetchError.unauthorized
            case 429:
                let header = httpResponse.value(forHTTPHeaderField: "Retry-After")
                throw FetchError.rateLimited(until: retryAfter(header, now: Date()))
            default:
                break
            }

            throw FetchError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    /// The longest `Retry-After` honoured. The providers' rate limits run
    /// per minute, so a genuine one is seconds to minutes; an hour caps what
    /// a bad header (or clock skew on an HTTP-date) can cost at one hour of
    /// scheduled refreshes, and Refresh still asks at any time.
    static let longestRetryAfter: TimeInterval = 3600

    /// When a `Retry-After` value (delay seconds or any HTTP-date form) says
    /// to try again, at most `longestRetryAfter` from `now`; nil when it is
    /// missing or unreadable. A past date is returned as is: retry now.
    static func retryAfter(_ value: String?, now: Date) -> Date? {
        guard let text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            return nil
        }

        let latest = now.addingTimeInterval(longestRetryAfter)
        if text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber) {
            // Enough digits parse as a huge number or infinity; the cap comes first.
            return TimeInterval(text).map { now.addingTimeInterval(min($0, longestRetryAfter)) }
        }

        // IMF-fixdate, then the obsolete RFC 850 and asctime forms RFC 9110 still requires.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return min(date, latest)
            }
        }

        return nil
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        dates: JSONDecoder.DateDecodingStrategy = .deferredToDate,
        optional: Bool = false
    ) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dates

        do {
            return try decoder.decode(type, from: data)
        } catch {
            logDecodingFailure(error, decoding: type, optional: optional)
            throw FetchError.decoding
        }
    }

    /// One line naming the type and where decoding stopped; never the data.
    /// A failure of an `optional` response, which the caller shrugs off, is
    /// debug noise rather than an error.
    static func logDecodingFailure(_ error: any Error, decoding type: Any.Type, optional: Bool = false) {
        let line = "decoding \(String(describing: type)) failed: \(LogFormat.decodingSummary(error))"
        if optional {
            Log.http.debug("\(line, privacy: .public)")
        } else {
            Log.http.error("\(line, privacy: .public)")
        }
    }
}
