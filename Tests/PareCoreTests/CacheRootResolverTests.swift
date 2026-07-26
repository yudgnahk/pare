import XCTest
@testable import PareCore

final class CacheRootResolverTests: XCTestCase {

    // MARK: - Base root resolution

    func testResolvesInjectedPlatformCacheRoot() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let fakePlatformRoot = home.appending(path: "FakePlatform/Caches")
        try FileManager.default.createDirectory(at: fakePlatformRoot, withIntermediateDirectories: true)

        let resolver = CacheRootResolver(platformCacheRoot: fakePlatformRoot, environmentVariables: [:])
        let roots = resolver.resolveBaseRoots(homeDirectory: home)

        let platformRoots = roots.filter { $0.source == .platform }
        XCTAssertEqual(platformRoots.count, 1)
        XCTAssertTrue(platformRoots[0].url.path.hasSuffix("/FakePlatform/Caches"),
                      "Injected platform root should be used, not the real user's Foundation directory")
        let realCaches = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches").path
        XCTAssertFalse(roots.contains { $0.url.path == realCaches },
                       "Real ~/Library/Caches must never be consulted when a fake root is injected")
    }

    func testResolvesDefaultXDGRoot() {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let resolver = CacheRootResolver(platformCacheRoot: nil, environmentVariables: [:])
        let roots = resolver.resolveBaseRoots(homeDirectory: home)

        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].source, .xdg)
        XCTAssertTrue(roots[0].url.path.hasSuffix("/.cache"), "Unset XDG_CACHE_HOME → <home>/.cache")
    }

    func testResolvesAbsoluteXDGOverride() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appending(path: "custom-xdg-cache")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)

        let resolver = CacheRootResolver(
            platformCacheRoot: nil,
            environmentVariables: ["XDG_CACHE_HOME": custom.path]
        )
        let roots = resolver.resolveBaseRoots(homeDirectory: home)

        XCTAssertEqual(roots.count, 1)
        XCTAssertTrue(roots[0].url.path.hasSuffix("/custom-xdg-cache"))
        XCTAssertEqual(roots[0].source, .xdg)
    }

    func testRejectsRelativeXDGOverride() {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let resolver = CacheRootResolver(
            platformCacheRoot: nil,
            environmentVariables: ["XDG_CACHE_HOME": "relative/cache-dir"]
        )
        let roots = resolver.resolveBaseRoots(homeDirectory: home)

        XCTAssertEqual(roots.count, 1)
        XCTAssertTrue(roots[0].url.path.hasSuffix("/.cache"),
                      "Relative XDG_CACHE_HOME must be ignored per the XDG spec (fall back to <home>/.cache)")
        XCTAssertFalse(roots[0].url.path.contains("relative/cache-dir"))
    }

    func testDangerousXDGOverrideFallsBackToDefault() {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let resolver = CacheRootResolver(
            platformCacheRoot: nil,
            environmentVariables: ["XDG_CACHE_HOME": "/"]
        )
        let roots = resolver.resolveBaseRoots(homeDirectory: home)

        XCTAssertEqual(roots.count, 1)
        XCTAssertTrue(roots[0].url.path.hasSuffix("/.cache"), "Dangerous XDG override must not become a root")
    }

    func testCanonicalizesAndDeduplicatesRoots() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let xdgDefault = home.appending(path: ".cache")
        try FileManager.default.createDirectory(at: xdgDefault, withIntermediateDirectories: true)

        // Platform root injected as a non-canonical spelling of the same directory.
        let sloppySpelling = URL(fileURLWithPath: home.path + "/./.cache/")
        let resolver = CacheRootResolver(platformCacheRoot: sloppySpelling, environmentVariables: [:])
        let roots = resolver.resolveBaseRoots(homeDirectory: home)

        XCTAssertEqual(roots.count, 1, "Two spellings of one physical directory must dedupe to one root")
    }

    func testDeduplicatesThroughSymlinks() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let real = home.appending(path: ".cache")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = home.appending(path: "cache-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let resolver = CacheRootResolver(platformCacheRoot: link, environmentVariables: [:])
        let roots = resolver.resolveBaseRoots(homeDirectory: home)

        XCTAssertEqual(roots.count, 1, "A symlink to the XDG root must not produce a second root")
    }

    // MARK: - Dangerous root rejection

    func testRejectsDangerousRoots() {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let dangerous = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/System"),
            URL(fileURLWithPath: "/tmp"),
            URL(fileURLWithPath: "/Users"),
            URL(fileURLWithPath: "/Volumes"),
            URL(fileURLWithPath: "/Library"),
            URL(fileURLWithPath: "/private/var"),
            home,                                     // bare home
            home.appending(path: "Library"),          // bare ~/Library
        ]
        for url in dangerous {
            XCTAssertTrue(CacheRootResolver.isDangerousRoot(url, homeDirectory: home),
                          "\(url.path) must be rejected as a cache root")
        }

        let safe = [
            home.appending(path: ".cache"),
            home.appending(path: "Library/Caches"),   // platform root itself is fine
        ]
        for url in safe {
            XCTAssertFalse(CacheRootResolver.isDangerousRoot(url, homeDirectory: home),
                           "\(url.path) should be an acceptable cache root")
        }
    }

    // MARK: - Tool-reported path validation

    func testRejectsUnsafeToolOutput() {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let rejected: [String] = [
            "",
            "   \n",
            "relative/path/uv",
            "/",
            home.path,                                     // bare home
            "/first/line\n/second/line",                   // embedded newline
            "/has\u{0}nul",                                // NUL garbage
            "/System",                                     // system root
            String(repeating: "/x", count: 3000),          // over-long
        ]
        for raw in rejected {
            XCTAssertNil(CacheRootResolver.validatedToolReportedPath(raw, homeDirectory: home),
                         "Tool output \(raw.debugDescription.prefix(60)) must be rejected")
        }

        let accepted = CacheRootResolver.validatedToolReportedPath(
            "  \(home.path)/.cache/uv\n", homeDirectory: home
        )
        XCTAssertNotNil(accepted, "A padded absolute single-line path should validate")
        XCTAssertTrue(accepted!.path.hasSuffix("/.cache/uv"))
    }

    // MARK: - Source labels

    func testRecordsDiscoverySource() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let platform = home.appending(path: "Library/Caches")
        try FileManager.default.createDirectory(at: platform, withIntermediateDirectories: true)

        let resolver = CacheRootResolver(platformCacheRoot: platform, environmentVariables: [:])
        let roots = resolver.resolveBaseRoots(homeDirectory: home)

        XCTAssertEqual(roots.map(\.source), [.platform, .xdg])
        XCTAssertEqual(CacheRootSource.platform.label, "macOS cache root")
        XCTAssertEqual(CacheRootSource.xdg.label, "XDG")
    }
}

// MARK: - ScanPolicy exact-root boundary

final class ScanPolicyExactRootBoundaryTests: XCTestCase {

    func testExactRootBoundary() {
        let root = URL(fileURLWithPath: "/Users/a/.cache/uv")

        XCTAssertTrue(ScanPolicy.isEqualToOrDescendant(
            candidate: URL(fileURLWithPath: "/Users/a/.cache/uv"), root: root))
        XCTAssertTrue(ScanPolicy.isEqualToOrDescendant(
            candidate: URL(fileURLWithPath: "/Users/a/.cache/uv/archive-v0"), root: root))

        XCTAssertFalse(ScanPolicy.isEqualToOrDescendant(
            candidate: URL(fileURLWithPath: "/Users/a/.cache/uvicorn"), root: root),
            "uvicorn must not match the uv root — substring matching is forbidden")
        XCTAssertFalse(ScanPolicy.isEqualToOrDescendant(
            candidate: URL(fileURLWithPath: "/Users/a/.cache/uv-backup"), root: root))

        let pipRoot = URL(fileURLWithPath: "/Users/a/.cache/pip")
        XCTAssertFalse(ScanPolicy.isEqualToOrDescendant(
            candidate: URL(fileURLWithPath: "/Users/a/.cache/pipx/venvs"), root: pipRoot))
    }

    /// Guard against regression: uv discovery must never authorize Trash cleanup
    /// through the substring marker allow-lists.
    func testUvNotInTrashCleanupMarkerLists() {
        XCTAssertFalse(ScanPolicy.developerPackageCacheMarkers.contains { $0.contains("/.cache/uv") },
                       "/.cache/uv must not be a persona Trash-cleanup marker")
        XCTAssertFalse(ScanPolicy.reconstructibleCachePathMarkers.contains { $0.contains("/.cache/uv") },
                       "/.cache/uv must not be a reconstructible-cache Trash marker")
    }
}

// MARK: - Test helpers

private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
