import Foundation

/// Builds the Sparkle appcast feed for one release.
public enum Appcast {
    /// An RSS 2.0 feed with a single item. The notes go in CDATA; any `]]>`
    /// inside them is split across two sections so the CDATA cannot end early.
    public static func xml(
        version: SemanticVersion, url: URL, length: Int, edSignature: String,
        notesHTML: String, published: Date, minimumSystemVersion: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss +0000"
        let cdata = notesHTML.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>Usage Tracker</title>
            <item>
              <title>\(escape("Version \(version)"))</title>
              <pubDate>\(formatter.string(from: published))</pubDate>
              <sparkle:version>\(version)</sparkle:version>
              <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>\(escape(minimumSystemVersion))</sparkle:minimumSystemVersion>
              <description><![CDATA[\(cdata)]]></description>
              <enclosure url="\(escape(url.absoluteString))" length="\(length)" type="application/octet-stream" sparkle:edSignature="\(escape(edSignature))"/>
            </item>
          </channel>
        </rss>

        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
