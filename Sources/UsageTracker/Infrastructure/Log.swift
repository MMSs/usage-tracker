import Foundation
import os

/// Unified log channels. Read them with
/// `log stream --predicate 'subsystem == "com.mohabsam.usage-tracker"' --level debug`.
///
/// Only the bundled app logs into that subsystem. A test run or an unbundled
/// binary has no bundle identifier of its own, so it logs into a separate
/// `.unbundled` subsystem and never mixes into the app's log.
///
/// Never log credentials, cookies, headers, query strings, or bodies.
enum Log {
    static let subsystem = subsystem(forBundleIdentifier: Bundle.main.bundleIdentifier)

    static func subsystem(forBundleIdentifier bundleIdentifier: String?) -> String {
        bundleIdentifier == AppIdentity.bundleID ? AppIdentity.bundleID : AppIdentity.bundleID + ".unbundled"
    }

    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let http = Logger(subsystem: subsystem, category: "http")
    static let scheduler = Logger(subsystem: subsystem, category: "scheduler")
    static let migration = Logger(subsystem: subsystem, category: "migration")
    static let loginItem = Logger(subsystem: subsystem, category: "login-item")
}

/// Account-neutral text for log lines.
enum LogFormat {
    /// Host and path with no query string, and any UUID segment (an
    /// organization id) replaced by `{uuid}`.
    static func endpoint(_ url: URL?) -> String {
        guard let url, let host = url.host() else {
            return "?"
        }

        let path = url.path(percentEncoded: false)
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { UUID(uuidString: String($0)) == nil ? String($0) : "{uuid}" }
            .joined(separator: "/")

        return host + path
    }

    /// The kind of decoding failure and the key path it happened at, without
    /// the debug description, which can quote the response.
    static func decodingSummary(_ error: any Error) -> String {
        guard let error = error as? DecodingError else {
            return String(describing: type(of: error))
        }

        switch error {
        case let .typeMismatch(_, context):
            return "type mismatch at \(path(context.codingPath))"
        case let .valueNotFound(_, context):
            return "missing value at \(path(context.codingPath))"
        case let .keyNotFound(key, context):
            return "missing key \(key.stringValue) at \(path(context.codingPath))"
        case let .dataCorrupted(context):
            return "corrupted data at \(path(context.codingPath))"
        @unknown default:
            return "decoding error"
        }
    }

    /// The server's own explanation of a failure: the `type` and `message`
    /// of an API error envelope, or a top-level `message`, `detail` or
    /// `error` string. Nil for anything else, such as an HTML challenge page.
    /// Cut to 200 characters. It describes the request, never a credential.
    static func errorSummary(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var parts: [String] = []
        switch object["error"] {
        case let error as [String: Any]:
            parts += [error["type"] as? String, error["message"] as? String].compactMap { $0 }
        case let error as String:
            parts.append(error)
        default:
            for key in ["message", "detail"] where parts.isEmpty {
                if let text = object[key] as? String {
                    parts.append(text)
                }
            }
        }

        guard !parts.isEmpty else {
            return nil
        }

        let text = parts.joined(separator: ": ")
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }

    /// "data[1].amount", or "root" for the top level.
    private static func path(_ codingPath: [any CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "root"
        }

        var text = ""
        for key in codingPath {
            if let index = key.intValue {
                text += "[\(index)]"
            } else {
                text += text.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return text
    }
}
