import XCTest
@testable import PareCore

/// Old app versions kept side by side: offered for review, newest two and running ones always kept.
final class VersionSiblingTests: XCTestCase {

    private var root: URL!
    private var home: URL { root.appending(path: "home") }

    override func setUpWithError() throws {
        // Canonical `/private/var/…` spelling, as directory listings and `ps` report it.
        root = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_versions_\(UUID().uuidString)")
        // A real home holds `Library`; dot-directory roots count only directly inside such a folder.
        try FileManager.default.createDirectory(at: home.appending(path: "Library"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - SemanticVersion

    func testSemanticVersionOrdering() throws {
        let ascending: [(lower: String, higher: String)] = [
            ("1.0.0", "2.0.0"),
            ("9.9.9", "10.0.0"),
            ("1.9.0", "1.10.0"),
            ("1.2.3-alpha", "1.2.3"),
            ("1.0.0-alpha", "1.0.0-alpha.1"),
            ("1.0.0-alpha.1", "1.0.0-alpha.beta"),
            ("1.0.0-beta.2", "1.0.0-beta.11"),
            ("1.0.0-rc.1", "1.0.0"),
        ]
        for pair in ascending {
            let lower = try XCTUnwrap(SemanticVersion(pair.lower), pair.lower)
            let higher = try XCTUnwrap(SemanticVersion(pair.higher), pair.higher)
            XCTAssertLessThan(lower, higher, "\(pair.lower) < \(pair.higher)")
            XCTAssertFalse(higher < lower, "\(pair.higher) !< \(pair.lower)")
        }
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion("1.2.3"))
        for invalid in ["1.2", "a.b.c", "1.2.x", "99999999999999999999.0.0"] {
            XCTAssertNil(SemanticVersion(invalid), invalid)
        }
    }

    func testVersionedNameSplitsAroundTheSemverToken() {
        let cases: [(name: String, prefix: String?, token: String?, suffix: String?)] = [
            ("0.12.3-aarch64-apple-darwin", "", "0.12.3-aarch64", "-apple-darwin"),
            ("v18.2.0", "v", "18.2.0", ""),
            ("Tool 2.0.0-beta.1", "Tool ", "2.0.0-beta.1", ""),
            ("plain", nil, nil, nil),
            ("1.2", nil, nil, nil),
        ]
        for testCase in cases {
            let split = VersionedName(testCase.name)
            XCTAssertEqual(split?.prefix, testCase.prefix, testCase.name)
            XCTAssertEqual(split?.token, testCase.token, testCase.name)
            XCTAssertEqual(split?.suffix, testCase.suffix, testCase.name)
        }
    }

    func testTwoDotPrefilterAgreesWithTheTokenPattern() {
        let names = [
            "", "plain", "1.2", "1.2.3", "a1.2.3b", "1..2", "..", "1.2.x", "v18.2.0", "x.y.z",
            "1.2.3-beta.1", "\u{663}.\u{664}.\u{665}", "\u{FF11}\u{FF0E}\u{FF12}\u{FF0E}\u{FF13}",
            "1\u{3002}2\u{3002}3", "1.\u{301}2.3", "1.2.\u{301}3", "1\u{2024}2\u{2024}3", "node-v20.11.1-darwin-arm64",
        ]
        for name in names {
            let range = name.range(of: VersionedName.tokenPattern, options: .regularExpression)
            let expected = range.flatMap { SemanticVersion(String(name[$0])) } != nil
            XCTAssertEqual(VersionedName(name) != nil, expected, name)
            if range != nil { XCTAssertTrue(VersionedName.hasTwoDots(name), name) }
        }
    }

    // MARK: - Rule

    func testKeepsNewestTwoAndOffersOlderVersions() async throws {
        let releases = home.appending(path: ".codex/packages/app-server-daemon/releases")
        for version in ["0.2.5", "0.9.0", "0.10.0", "0.10.1"] {
            try makeVersion(releases, "\(version)-aarch64-apple-darwin")
        }
        let executables = StubExecutables(["/usr/libexec/somed"])

        let findings = await rule(executables).customScan(environment: environment()) ?? []

        XCTAssertEqual(Set(findings.map(\.path)), [
            releases.appending(path: "0.2.5-aarch64-apple-darwin").path,
            releases.appending(path: "0.9.0-aarch64-apple-darwin").path,
        ])
        let older = try XCTUnwrap(findings.first { $0.path.hasSuffix("0.9.0-aarch64-apple-darwin") })
        XCTAssertEqual(older.reason, "Older app-server-daemon version 0.9.0; newest 0.10.1 and 0.10.0 are kept")
        XCTAssertEqual(older.riskLevel, .review)
        XCTAssertEqual(older.category, .applications)
        XCTAssertGreaterThan(older.sizeBytes, 0)
        XCTAssertEqual(executables.calls, 1)
    }

    func testTwoVersionsAreNotEnough() async throws {
        let versions = home.appending(path: ".tool/versions")
        try makeVersion(versions, "1.0.0")
        try makeVersion(versions, "1.1.0")

        let findings = await rule(StubExecutables([])).customScan(environment: environment()) ?? []

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    func testVersionARunningProcessExecutesFromIsKept() async throws {
        let versions = home.appending(path: "Library/Application Support/Foo/versions")
        for version in ["1.0.0", "1.1.0", "2.0.0", "2.1.0"] {
            try makeVersion(versions, version)
        }
        // Spelled through the `/var` alias: matching must canonicalize.
        let aliasPath = String(versions.path.dropFirst("/private".count)) + "/1.1.0/bin/foo"
        let findings = await rule(StubExecutables([aliasPath])).customScan(environment: environment()) ?? []

        XCTAssertEqual(findings.map(\.path), [versions.appending(path: "1.0.0").path])
        XCTAssertEqual(findings.first?.reason, "Older Foo version 1.0.0; newest 2.1.0 and 2.0.0 are kept")
    }

    func testSnapshotFailureReportsNothing() async throws {
        let versions = home.appending(path: ".tool/versions")
        for version in ["1.0.0", "1.1.0", "1.2.0"] {
            try makeVersion(versions, version)
        }

        let findings = await rule(StubExecutables(nil)).customScan(environment: environment()) ?? []

        XCTAssertTrue(findings.isEmpty)
    }

    func testVersionManagerAndPackageTreesAreIgnored() async throws {
        for tree in [".nvm/versions/node", ".pyenv/versions", ".cargo/registry/src/index", ".vscode/extensions"] {
            for version in ["v18.0.0", "v19.0.0", "v20.0.0"] {
                try makeVersion(home.appending(path: tree), version)
            }
        }
        let executables = StubExecutables([])

        let findings = await rule(executables).customScan(environment: environment()) ?? []

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
        XCTAssertEqual(executables.calls, 0, "no process snapshot when there is nothing to offer")
    }

    func testSymlinkedAndPackageVersionsAreNotMembers() async throws {
        let versions = home.appending(path: ".tool/versions")
        try makeVersion(versions, "1.0.0")
        try makeVersion(versions, "1.1.0")
        let elsewhere = try makeVersion(root.appending(path: "elsewhere"), "1.2.0")
        try FileManager.default.createSymbolicLink(at: versions.appending(path: "1.2.0"), withDestinationURL: elsewhere)
        let bundles = home.appending(path: ".tool/bundles")
        for version in ["1.0.0", "1.1.0", "1.2.0"] {
            try makeVersion(bundles, "Tool-\(version).app")
        }

        let findings = await rule(StubExecutables([])).customScan(environment: environment()) ?? []

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    func testWideDirectoryStillGroupsItsVersionedFolders() async throws {
        let releases = home.appending(path: ".tool/releases")
        for version in ["1.0.0", "1.1.0", "1.2.0"] {
            try makeVersion(releases, version)
        }
        for index in 0...VersionSiblingsRule.fanOutLimit {
            try Data().write(to: releases.appending(path: "session-\(index).json"))
        }

        let findings = await rule(StubExecutables([])).customScan(environment: environment()) ?? []

        XCTAssertEqual(findings.map(\.path), [releases.appending(path: "1.0.0").path])
    }

    func testRuntimeManagerHomesAreIgnored() async throws {
        let trees = [
            "Library/Application Support/fnm/node-versions", ".local/share/fnm/node-versions", ".proto/tools/node",
            ".rye/py", ".juliaup/bin", ".swiftly/toolchains", ".elan/toolchains", ".tfenv/versions",
            "Library/Application Support/mise/installs/node",
        ]
        for tree in trees {
            for version in ["v18.0.0", "v19.0.0", "v20.0.0"] {
                try makeVersion(home.appending(path: tree), version)
            }
            XCTAssertFalse(ScanPolicy.isVersionSiblingMember(home.appending(path: tree + "/v18.0.0")), tree)
        }

        let findings = await rule(StubExecutables([])).customScan(environment: environment()) ?? []

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    func testAliasPinnedGroupIsNeverOffered() async throws {
        let cases: [(name: String, pinned: Bool, pin: (URL, URL) throws -> Void)] = [
            ("aliases/ symlink into a member", true, { manager, oldest in
                try FileManager.default.createDirectory(at: manager.appending(path: "aliases"), withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(at: manager.appending(path: "aliases/default"),
                                                           withDestinationURL: oldest.appending(path: "bin"))
            }),
            ("current symlink beside the members", true, { manager, oldest in
                try FileManager.default.createSymbolicLink(at: manager.appending(path: "node-versions/current"),
                                                           withDestinationURL: oldest)
            }),
            ("default file naming a partial version", true, { manager, _ in
                try "v1.0\n".write(to: manager.appending(path: "default"), atomically: true, encoding: .utf8)
            }),
            ("version file with alias syntax", true, { manager, _ in
                try "lts/*".write(to: manager.appending(path: "version"), atomically: true, encoding: .utf8)
            }),
            ("default file naming another version", false, { manager, _ in
                try "0.9.0".write(to: manager.appending(path: "default"), atomically: true, encoding: .utf8)
            }),
            ("no alias", false, { _, _ in }),
        ]
        for testCase in cases {
            let manager = root.appending(path: "home-\(UUID().uuidString)/.toolman")
            try FileManager.default.createDirectory(at: manager.deletingLastPathComponent().appending(path: "Library"),
                                                    withIntermediateDirectories: true)
            let versions = manager.appending(path: "node-versions")
            let oldest = try makeVersion(versions, "v1.0.0")
            try makeVersion(versions, "v1.1.0")
            try makeVersion(versions, "v1.2.0")
            try testCase.pin(manager, oldest)
            let members = ["v1.0.0", "v1.1.0", "v1.2.0"].map { versions.appending(path: $0) }

            XCTAssertEqual(ScanPolicy.isPinnedVersionSiblingGroup(members), testCase.pinned, testCase.name)
            XCTAssertEqual(ScanPolicy.isReclaimableVersionSibling(oldest, runningExecutables: []), !testCase.pinned, testCase.name)
            let scan = ScanEnvironment(homeDirectory: manager.deletingLastPathComponent(),
                                       tempDirectory: root.appending(path: "tmp"), systemApplicationDirectories: [])
            let findings = await rule(StubExecutables([])).customScan(environment: scan) ?? []
            XCTAssertEqual(findings.map(\.path), testCase.pinned ? [] : [oldest.path], testCase.name)
        }
    }

    func testVersionExecutedThroughASymlinkIsKept() throws {
        let versions = home.appending(path: ".tool/versions")
        let oldest = try makeVersion(versions, "1.0.0")
        try makeVersion(versions, "1.1.0")
        try makeVersion(versions, "1.2.0")
        // Like fnm_multishells: the process runs from a link outside the group's own folders.
        let shell = root.appending(path: "multishells/1234_abcd")
        try FileManager.default.createDirectory(at: shell.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: shell, withDestinationURL: oldest)
        let running = [shell.appending(path: "bin/tool").path]

        XCTAssertTrue(ScanPolicy.isExecutedFrom(oldest, runningExecutables: running))
        XCTAssertFalse(ScanPolicy.isReclaimableVersionSibling(oldest, runningExecutables: running))
        XCTAssertTrue(ScanPolicy.isReclaimableVersionSibling(oldest, runningExecutables: []), "control")
    }

    func testSearchDepthIsBounded() async throws {
        let deep = home.appending(path: ".tool/a/b/c/d/e/f/versions")
        for version in ["1.0.0", "1.1.0", "1.2.0"] {
            try makeVersion(deep, version)
        }

        let findings = await rule(StubExecutables([])).customScan(environment: environment()) ?? []

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    // MARK: - Cleanup re-verification

    func testReclaimableVersionSiblingPolicy() throws {
        let versions = home.appending(path: ".tool/versions")
        for version in ["1.0.0", "1.1.0", "1.2.0", "1.3.0"] {
            try makeVersion(versions, version)
        }
        let oldest = versions.appending(path: "1.0.0")
        let cases: [(name: String, url: URL, executables: [String]?, reclaimable: Bool)] = [
            ("oldest", oldest, [], true),
            ("second oldest", versions.appending(path: "1.1.0"), [], true),
            ("previous is kept", versions.appending(path: "1.2.0"), [], false),
            ("newest is kept", versions.appending(path: "1.3.0"), [], false),
            ("running", oldest, [oldest.appending(path: "bin/tool").path], false),
            ("no snapshot", oldest, nil, false),
        ]
        for testCase in cases {
            XCTAssertEqual(
                ScanPolicy.isReclaimableVersionSibling(testCase.url, runningExecutables: testCase.executables),
                testCase.reclaimable,
                testCase.name
            )
        }

        try FileManager.default.removeItem(at: versions.appending(path: "1.3.0"))
        XCTAssertFalse(ScanPolicy.isReclaimableVersionSibling(versions.appending(path: "1.1.0"), runningExecutables: []),
                       "fewer than two newer siblings remain")
    }

    func testRefusalNamesWhyAVersionIsKept() throws {
        let versions = home.appending(path: ".tool/versions")
        let oldest = try makeVersion(versions, "1.0.0")
        try makeVersion(versions, "1.1.0")
        try makeVersion(versions, "1.2.0")
        let cases: [(name: String, url: URL, executables: [String]?, refusal: VersionSiblingRefusal?)] = [
            ("reclaimable", oldest, [], nil),
            ("previous is kept", versions.appending(path: "1.1.0"), [], .fewerNewerVersions),
            ("no snapshot", oldest, nil, .processListUnavailable),
            ("running", oldest, [oldest.appending(path: "bin/tool").path], .runningFrom),
            ("not a member", home.appending(path: "Documents/MyApp-1.0.0"), [], .outsidePolicy),
        ]
        for testCase in cases {
            let refusal = ScanPolicy.versionSiblingRefusal(testCase.url, runningExecutables: testCase.executables, customRoots: [])
            XCTAssertEqual(refusal, testCase.refusal, testCase.name)
        }
        XCTAssertEqual(VersionSiblingRefusal.fewerNewerVersions.reason, "fewer than 2 newer versions")
    }

    func testShrunkGroupIsRecognisedOnlyBelowTheMinimum() throws {
        let versions = home.appending(path: ".tool/versions")
        let oldest = try makeVersion(versions, "1.0.0")
        try makeVersion(versions, "1.1.0")
        let newest = try makeVersion(versions, "1.2.0")
        XCTAssertFalse(ScanPolicy.isShrunkVersionSiblingGroup(newest), "a full group goes through the gate itself")

        try FileManager.default.removeItem(at: oldest)
        XCTAssertTrue(ScanPolicy.isShrunkVersionSiblingGroup(newest))
        XCTAssertFalse(ScanPolicy.isShrunkVersionSiblingGroup(oldest), "a folder that is gone is not a sibling")

        let nvm = try makeVersion(home.appending(path: ".nvm/versions/node"), "v18.0.0")
        XCTAssertFalse(ScanPolicy.isShrunkVersionSiblingGroup(nvm), "excluded trees are never version siblings")
    }

    func testNeverCleanVersionSiblingsAreNeverReclaimable() throws {
        let tool = home.appending(path: ".gotool")
        let oldest = try makeVersion(tool.appending(path: "versions"), "1.0.0")
        try makeVersion(tool.appending(path: "versions"), "1.1.0")
        try makeVersion(tool.appending(path: "versions"), "1.2.0")

        XCTAssertTrue(ScanPolicy.isReclaimableVersionSibling(oldest, runningExecutables: [], customRoots: []), "control")
        XCTAssertEqual(ScanPolicy.versionSiblingRefusal(oldest, runningExecutables: [], customRoots: [tool]), .outsidePolicy)
        XCTAssertFalse(ScanPolicy.isReclaimableVersionSibling(oldest, runningExecutables: [], customRoots: [tool]))
    }

    func testExcludedTreeIsNeverReclaimable() throws {
        let versions = home.appending(path: ".nvm/versions/node")
        for version in ["v18.0.0", "v19.0.0", "v20.0.0"] {
            try makeVersion(versions, version)
        }

        XCTAssertFalse(ScanPolicy.isVersionSiblingMember(versions.appending(path: "v18.0.0")))
        XCTAssertFalse(ScanPolicy.isReclaimableVersionSibling(versions.appending(path: "v18.0.0"), runningExecutables: []))
    }

    func testCleanupEngineOnlyPassesVersionSiblingsThroughTheirOwnGate() async throws {
        let versions = home.appending(path: ".tool/versions")
        for version in ["1.0.0", "1.1.0", "1.2.0"] {
            try makeVersion(versions, version)
        }
        let oldest = versions.appending(path: "1.0.0")
        let newest = versions.appending(path: "1.2.0")

        let ok = try await engine(StubExecutables([])).clean(findings: [finding(oldest), finding(newest)], profileName: "test")
        XCTAssertEqual(ok.succeeded.map(\.originalPath), [oldest.path], "\(ok.skipped.map(\.reason))")
        XCTAssertEqual(ok.skipped.map(\.path), [newest.path])
        guard case .some(.versionKept(_, let reason)) = ok.skipped.first?.error else {
            return XCTFail("expected .versionKept, got \(ok.skipped.map(\.reason))")
        }
        XCTAssertEqual(reason, "fewer than 2 newer versions")

        let middle = versions.appending(path: "1.1.0")
        try makeVersion(versions, "1.3.0")
        try makeVersion(versions, "1.4.0")
        let failed = try await engine(StubExecutables(nil)).clean(findings: [finding(middle)], profileName: "test")
        XCTAssertTrue(failed.succeeded.isEmpty, "no process snapshot means no cleanup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: middle.path))
    }

    // MARK: - Process snapshot

    func testPsProviderParsesPathsAndFailsClosed() async {
        let cases: [(name: String, script: String, expected: [String]?)] = [
            ("paths", "printf '/usr/libexec/a\\n  /Applications/X.app/Contents/MacOS/X\\nkernel_task\\n'",
             ["/usr/libexec/a", "/Applications/X.app/Contents/MacOS/X"]),
            ("no paths", "echo kernel_task", nil),
            ("non-zero exit", "printf '/usr/libexec/a\\n'\nexit 1", nil),
            ("timeout", "exec sleep 5", nil),
        ]
        for testCase in cases {
            let paths = await psProvider(testCase.script).runningExecutablePaths()
            XCTAssertEqual(paths, testCase.expected, testCase.name)
        }
    }

    // MARK: - Helpers

    private func environment() -> ScanEnvironment {
        ScanEnvironment(homeDirectory: home, tempDirectory: root.appending(path: "tmp"), systemApplicationDirectories: [])
    }

    private func rule(_ executables: StubExecutables) -> VersionSiblingsRule {
        VersionSiblingsRule(runningExecutables: executables)
    }

    func testSiblingsOutsideTheRuleRootsAreNeverReclaimable() throws {
        for tree in ["Documents/Releases", "Desktop/Builds", "Library/Mobile Documents/com~apple~CloudDocs/.app", "Projects/app/.cache"] {
            let parent = home.appending(path: tree)
            let oldest = try makeVersion(parent, "MyApp-1.0.0")
            try makeVersion(parent, "MyApp-1.1.0")
            try makeVersion(parent, "MyApp-1.2.0")

            XCTAssertFalse(ScanPolicy.isReclaimableVersionSibling(oldest, runningExecutables: []), tree)
        }
        let allowed = home.appending(path: ".tool/versions")
        let oldest = try makeVersion(allowed, "MyApp-1.0.0")
        try makeVersion(allowed, "MyApp-1.1.0")
        try makeVersion(allowed, "MyApp-1.2.0")
        XCTAssertTrue(ScanPolicy.isReclaimableVersionSibling(oldest, runningExecutables: []), "control: inside a home dot directory")
    }

    @discardableResult
    private func makeVersion(_ parent: URL, _ name: String) throws -> URL {
        let dir = parent.appending(path: name)
        try FileManager.default.createDirectory(at: dir.appending(path: "bin"), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 4096).write(to: dir.appending(path: "bin/tool"))
        return URL(fileURLWithPath: dir.path)
    }

    private func finding(_ url: URL) -> ScanFinding {
        ScanFinding(category: .applications, riskLevel: .review, reason: "old version", path: url.path,
                    sizeBytes: 4096, lastUsed: nil, confidence: 1.0)
    }

    private func engine(_ executables: StubExecutables) -> CleanupEngine {
        let trash = root.appending(path: "Trash")
        try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: root.appending(path: "store")),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            trashItem: { url in
                let destination = trash.appending(path: UUID().uuidString)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            },
            runningExecutables: executables
        )
    }

    private func psProvider(_ body: String) -> PsRunningExecutablesProvider {
        let script = root.appending(path: "ps-\(UUID().uuidString).sh")
        try? Data("#!/bin/sh\n\(body)\n".utf8).write(to: script)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return PsRunningExecutablesProvider(executable: script, timeoutSeconds: 1)
    }
}

/// Canned running-executable paths (nil = snapshot unavailable), counting calls.
private final class StubExecutables: RunningExecutablesProviding, @unchecked Sendable {
    private let paths: [String]?
    private let lock = NSLock()
    private var count = 0

    init(_ paths: [String]?) {
        self.paths = paths
    }

    var calls: Int { lock.withLock { count } }

    func runningExecutablePaths() async -> [String]? {
        recordCall()
        return paths
    }

    private func recordCall() {
        lock.withLock { count += 1 }
    }
}
