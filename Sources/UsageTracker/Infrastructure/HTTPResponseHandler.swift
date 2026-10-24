import Foundation

/// Status and transport mapping shared by every provider's services.
enum HTTPResponseHandler {
    @MainActor
    static func data(for request: URLRequest, client: HTTPClient) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch {
            // A cancelled request is not a failure; let callers tell the difference.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw FetchError.transport
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
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
            default:
                break
            }

            throw FetchError.httpStatus(httpResponse.statusCode)
        }

        return data
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
            throw FetchError.decoding
        }
    }
}
