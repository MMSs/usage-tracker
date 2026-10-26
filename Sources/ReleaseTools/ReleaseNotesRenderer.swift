import Foundation

/// Renders a plan as Markdown (GitHub Release) and HTML (Sparkle's window).
public enum ReleaseNotesRenderer {
    /// Markdown notes. The first release is the summary alone.
    public static func markdown(_ plan: ReleasePlan, repository: String, firstReleaseSummary: String?) -> String {
        var out = "## \(plan.version)\n\n"
        guard let previous = plan.previousTag else {
            return out + (firstReleaseSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (title, entries) in sections(plan) {
            out += "### \(title)\n"
            for entry in entries {
                let scope = entry.scope.map { "**\($0):** " } ?? ""
                let link = entry.pullRequest.map {
                    " ([#\($0)](https://github.com/\(repository)/pull/\($0)))"
                } ?? ""
                out += "- \(scope)\(entry.text)\(link)\n"
                for bullet in entry.bullets { out += "  - \(bullet)\n" }
            }
            out += "\n"
        }
        out += "**Full changelog:** https://github.com/\(repository)/compare/\(previous)...v\(plan.version)\n"
        return out
    }

    /// HTML notes without a version heading; every piece of text is escaped.
    public static func html(_ plan: ReleasePlan, repository: String, firstReleaseSummary: String?) -> String {
        guard let previous = plan.previousTag else {
            let paragraphs = (firstReleaseSummary ?? "")
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return paragraphs.map { "<p>\(escape($0))</p>\n" }.joined()
        }
        var out = ""
        for (title, entries) in sections(plan) {
            out += "<h3>\(title)</h3>\n<ul>\n"
            for entry in entries {
                let scope = entry.scope.map { "<strong>\(escape($0)):</strong> " } ?? ""
                let link = entry.pullRequest.map {
                    " (<a href=\"https://github.com/\(escape(repository))/pull/\($0)\">#\($0)</a>)"
                } ?? ""
                out += "<li>\(scope)\(escape(entry.text))\(link)"
                if entry.bullets.isEmpty {
                    out += "</li>\n"
                } else {
                    out += "\n<ul>\n"
                    for bullet in entry.bullets { out += "<li>\(escape(bullet))</li>\n" }
                    out += "</ul>\n</li>\n"
                }
            }
            out += "</ul>\n"
        }
        let compare = "https://github.com/\(escape(repository))/compare/\(escape(previous))...v\(plan.version)"
        out += "<p><strong>Full changelog:</strong> <a href=\"\(compare)\">\(compare)</a></p>\n"
        return out
    }

    private static func sections(_ plan: ReleasePlan) -> [(String, [ReleaseEntry])] {
        [("Breaking changes", plan.breaking), ("Features", plan.features), ("Fixes", plan.fixes)]
            .filter { !$0.1.isEmpty }
    }

    /// Escapes text for HTML element content and double-quoted attributes.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
