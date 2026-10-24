import Foundation
import os

/// Status and transport mapping shared by every provider's services.
enum HTTPResponseHandler {
    @MainActor
    static func data(for request: URLRequest, client: HTTPClient) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let endpoint = LogFormat.endpoint(request.url)
        let start = ContinuousClock.now

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch {
            // A cancelled request is not a failure; let callers tell the difference.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
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

    /// When a `Retry-After` value (delay seconds or any HTTP-date form) says
    /// to try again; nil when it is missing or unreadable.
    static func retryAfter(_ value: String?, now: Date) -> Date? {
        guard let text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            return nil
        }

        if text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber) {
            return TimeInterval(text).map { now.addingTimeInterval($0) }
        }

        // IMF-fixdate, then the obsolete RFC 850 and asctime forms RFC 9110 still requires.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }

        return nil
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        dates: JSONDecoder.DateDecodingStrategy = .deferredToDate
    ) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dates

        do {
            return try decoder.decode(type, from: data)
        } catch {
            logDecodingFailure(error, decoding: type)
            throw FetchError.decoding
        }
    }

    /// One line naming the type and where decoding stopped; never the data.
    static func logDecodingFailure(_ error: any Error, decoding type: Any.Type) {
        Log.http.error("decoding \(String(describing: type), privacy: .public) failed: \(LogFormat.decodingSummary(error), privacy: .public)")
    }
}
