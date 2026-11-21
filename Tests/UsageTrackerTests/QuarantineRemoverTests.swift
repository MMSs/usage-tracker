import Foundation
import Testing
@testable import UsageTracker

@Suite struct QuarantineRemoverTests {
    private static let otherAttribute = "com.example.keep"

    /// A bundle-shaped tree: the root, a nested directory and two files.
    private func withBundle(_ body: (_ root: URL, _ items: [URL]) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "QuarantineRemoverTests-\(UUID().uuidString).app")
        let nested = root.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let binary = nested.appending(path: "UsageTracker")
        let plist = root.appending(path: "Contents/Info.plist")
        try Data("binary".utf8).write(to: binary)
        try Data("plist".utf8).write(to: plist)
        defer { try? FileManager.default.removeItem(at: root) }

        try body(root, [root, root.appending(path: "Contents"), nested, binary, plist])
    }

    private func setAttribute(_ name: String, on url: URL) throws {
        let value = "0181;6ae7d82d;;00000000-0000-0000-0000-000000000000"
        let result = value.withCString { pointer in
            setxattr(url.path, name, pointer, strlen(pointer), 0, XATTR_NOFOLLOW)
        }
        try #require(result == 0, "setxattr failed: \(errno)")
    }

    private func hasAttribute(_ name: String, on url: URL) -> Bool {
        getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    @Test func removesQuarantineFromEveryItemAndCountsThem() throws {
        try withBundle { root, items in
            for item in items {
                try setAttribute(QuarantineRemover.attributeName, on: item)
            }

            let cleared = QuarantineRemover(bundleURL: root).run()

            #expect(cleared == items.count)
            for item in items {
                #expect(!hasAttribute(QuarantineRemover.attributeName, on: item), "\(item.lastPathComponent)")
            }
        }
    }

    @Test func leavesOtherAttributesAndReportsNothingToClear() throws {
        try withBundle { root, items in
            try setAttribute(Self.otherAttribute, on: root)

            let cleared = QuarantineRemover(bundleURL: root).run()

            #expect(cleared == 0)
            #expect(hasAttribute(Self.otherAttribute, on: root))
            for item in items {
                #expect(!hasAttribute(QuarantineRemover.attributeName, on: item))
            }
        }
    }

    @Test func skipsItemsItCannotChangeAndKeepsGoing() throws {
        try withBundle { root, items in
            for item in items {
                try setAttribute(QuarantineRemover.attributeName, on: item)
            }
            let readOnly = items.last!
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnly.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: readOnly.path) }

            let cleared = QuarantineRemover(bundleURL: root).run()

            #expect(cleared == items.count - 1)
            #expect(hasAttribute(QuarantineRemover.attributeName, on: readOnly))
            #expect(!hasAttribute(QuarantineRemover.attributeName, on: root))
        }
    }

    @Test func missingBundleClearsNothing() {
        let missing = URL(filePath: "/nonexistent/QuarantineRemoverTests.app")

        #expect(QuarantineRemover(bundleURL: missing).run() == 0)
    }
}
