import Foundation
import os

/// Unified log channels. Read them with
/// `log stream --predicate 'subsystem == "com.mohabsam.usage-tracker"' --level debug`.
///
/// Never log credentials, cookies, headers, query strings, or bodies.
enum Log {
    static let subsystem = AppIdentity.bundleID

    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let http = Logger(subsystem: subsystem, category: "http")
    static let scheduler = Logger(subsystem: subsystem, category: "scheduler")
    static let migration = Logger(subsystem: subsystem, category: "migration")
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
