import XCTest
@testable import PareCore

final class ScanPolicyPathContainmentTests: XCTestCase {

    func testCanonicalPathURLMapsPrivateAliases() {
        let cases: [(name: String, input: String, expected: String)] = [
            ("var alias", "/var/folders/ab/T/x", "/private/var/folders/ab/T/x"),
            ("tmp alias", "/tmp/build", "/private/tmp/build"),
            ("etc alias", "/etc/hosts", "/private/etc/hosts"),
            ("bare var", "/var", "/private/var"),
            ("already private", "/private/var/folders/x", "/private/var/folders/x"),
            ("not an alias prefix", "/variable/x", "/variable/x"),
            ("home path untouched", "/Users/k/Library/Caches", "/Users/k/Library/Caches"),
            ("dot segments", "/var/folders/../folders/x/./y", "/private/var/folders/x/y"),
        ]
        for testCase in cases {
            let result = ScanPolicy.canonicalPathURL(URL(fileURLWithPath: testCase.input))
            XCTAssertEqual(result.path, testCase.expected, testCase.name)
        }
    }

    func testCanonicalContainment() {
        let cases: [(name: String, candidate: String, root: String, expected: Bool)] = [
            ("var vs private var", "/private/var/folders/x/cache", "/var/folders/x", true),
            ("private var vs var", "/var/folders/x/cache", "/private/var/folders/x", true),
            ("tmp vs private tmp", "/private/tmp/a/b", "/tmp/a", true),
            ("exact alias match", "/var/folders/x", "/private/var/folders/x", true),
            ("case-insensitive", "/Users/k/Library/Caches/build/item", "/Users/k/Library/Caches/Build", true),
            ("sibling prefix uvicorn", "/a/uvicorn", "/a/uv", false),
            ("sibling prefix uv-backup", "/a/uv-backup/x", "/a/uv", false),
            ("parent is not inside child", "/a", "/a/uv", false),
            ("alias-like sibling", "/private/variable/x", "/var", false),
            ("unrelated", "/Users/k/Desktop", "/Users/k/Downloads", false),
        ]
        for testCase in cases {
            let result = ScanPolicy.isCanonicallyEqualToOrDescendant(
                candidate: URL(fileURLWithPath: testCase.candidate),
                root: URL(fileURLWithPath: testCase.root)
            )
            XCTAssertEqual(result, testCase.expected, testCase.name)
        }
    }

    func testHasSymbolicLinkComponent() throws {
        let root = URL(fileURLWithPath: "/private/tmp/SymlinkComponent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appending(path: "real/cache")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appending(path: "real"))
        let tmpAliasSpelling = "/tmp/" + root.lastPathComponent + "/real/cache"

        let cases: [(name: String, path: String, expected: Bool)] = [
            ("plain directory", real.path, false),
            ("link in the middle", link.appending(path: "cache").path, true),
            ("link as leaf", link.path, true),
            ("/tmp system alias", tmpAliasSpelling, false),
            ("/var system alias", NSTemporaryDirectory(), false),
            ("missing path", root.appending(path: "missing/x").path, false),
        ]
        for testCase in cases {
            XCTAssertEqual(ScanPolicy.hasSymbolicLinkComponent(atPath: testCase.path), testCase.expected, testCase.name)
        }
    }
}
