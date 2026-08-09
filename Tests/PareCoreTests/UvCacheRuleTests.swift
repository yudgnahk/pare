import XCTest
@testable import PareCore

final class UvCacheRuleTests: XCTestCase {

    // MARK: - Discovery

    func testReturnsEmptyWhenNoUvCacheExists() async {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let rule = makeRule(toolOutput: nil)
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))

        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty)
    }

    func testDetectsXDGUvCache() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        try createDirWithContent(at: home.appending(path: ".cache/uv"))

        let rule = makeRule(toolOutput: nil)
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!

        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].path.hasSuffix("/.cache/uv"))
        XCTAssertEqual(findings[0].riskLevel, .advanced, "Phase A uv findings must be report-only")
        XCTAssertEqual(findings[0].category, .developerPackageCaches)
        XCTAssertTrue(findings[0].reason.contains("uv cache"), "Reason should identify uv")
        XCTAssertTrue(findings[0].reason.contains("XDG"), "Reason should carry the discovery source")
        XCTAssertGreaterThan(findings[0].sizeBytes, 0)
    }

    func testDetectsPlatformUvCache() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let platformRoot = home.appending(path: "Library/Caches")
        try createDirWithContent(at: platformRoot.appending(path: "uv"))

        let rule = makeRule(platformCacheRoot: platformRoot, toolOutput: nil)
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!

        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].path.hasSuffix("/Library/Caches/uv"))
        XCTAssertTrue(findings[0].reason.contains("macOS cache root"))
    }

    func testDetectsConfiguredUvCache() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appending(path: "custom-volume/uv-cache")
        try createDirWithContent(at: custom)

        // `uv cache dir` reports a directory outside every default root.
        let rule = makeRule(toolOutput: custom.path + "\n")
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!

        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].path.hasSuffix("/custom-volume/uv-cache"))
        XCTAssertTrue(findings[0].reason.contains("uv CLI"), "CLI-discovered root should be labelled uv CLI")
    }

    func testDetectsEnvironmentConfiguredUvCache() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appending(path: "env-uv-cache")
        try createDirWithContent(at: custom)

        let rule = makeRule(environmentVariables: ["UV_CACHE_DIR": custom.path], toolOutput: nil)
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!

        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].path.hasSuffix("/env-uv-cache"))
    }

    func testDeduplicatesUvCandidates() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let xdgUv = home.appending(path: ".cache/uv")
        try createDirWithContent(at: xdgUv)

        // XDG default, UV_CACHE_DIR, and the CLI all resolve to the same physical
        // directory — via different spellings. Exactly one finding must remain.
        let rule = makeRule(
            environmentVariables: ["UV_CACHE_DIR": xdgUv.path],
            toolOutput: home.path + "/.cache/./uv/"
        )
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!

        XCTAssertEqual(findings.count, 1, "One physical directory must produce one finding")
        XCTAssertTrue(findings[0].reason.contains("uv CLI"),
                      "The tool-reported source has highest explanatory confidence")
    }

    func testDetectsBothUvRootsIndependently() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        try createDirWithContent(at: home.appending(path: ".cache/uv"))
        let second = home.appending(path: "other-volume/uv")
        try createDirWithContent(at: second)

        let rule = makeRule(toolOutput: second.path)
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!

        XCTAssertEqual(findings.count, 2, "Two physical uv roots must never be merged")
    }

    func testEmptyUvSkipped() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(
            at: home.appending(path: ".cache/uv"), withIntermediateDirectories: true
        )

        let rule = makeRule(toolOutput: nil)
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!
        XCTAssertTrue(findings.isEmpty, "Empty uv cache directory should not emit a finding")
    }

    func testToolTimeoutFallsBackToRoots() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        try createDirWithContent(at: home.appending(path: ".cache/uv"))

        // Provider returning nil models uv being absent, failing, or timing out.
        let rule = makeRule(toolOutput: nil)
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!

        XCTAssertEqual(findings.count, 1, "Root-derived discovery must survive tool failure")
        XCTAssertTrue(findings[0].path.hasSuffix("/.cache/uv"))
    }

    func testRejectsUnsafeToolOutput() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        for garbage in ["/", home.path, "relative/uv", "/a\n/b"] {
            let rule = makeRule(toolOutput: garbage)
            let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!
            XCTAssertTrue(findings.isEmpty, "Unsafe tool output \(garbage.debugDescription) must yield nothing")
        }
    }

    func testDoesNotMatchUvSiblingDirectories() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        // Neighbours that a substring match would wrongly swallow.
        try createDirWithContent(at: home.appending(path: ".cache/uvicorn"))
        try createDirWithContent(at: home.appending(path: ".cache/uv-backup"))

        let rule = makeRule(toolOutput: nil)
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!
        XCTAssertTrue(findings.isEmpty, "uvicorn / uv-backup must never be reported as the uv cache")
    }

    // MARK: - Cleanup safety

    func testUvFindingCannotPassTrashCleanup() async throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let uvDir = home.appending(path: ".cache/uv")
        try createDirWithContent(at: uvDir)
        backdateItem(at: uvDir, days: 30)

        let rule = makeRule(toolOutput: nil)
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))!
        XCTAssertEqual(findings.count, 1)

        let storeDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let engine = CleanupEngine(store: CleanupTransactionStore(directory: storeDir))

        // Direct clean: hard-blocked because the finding is .advanced.
        let result = try await engine.clean(findings: findings, profileName: "test")
        XCTAssertTrue(result.succeeded.isEmpty, "uv cache must never be moved to Trash")
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("ADVANCED"),
                      "Skip reason should point to the app-native cleanup flow")
        XCTAssertTrue(FileManager.default.fileExists(atPath: uvDir.path),
                      "uv cache directory must remain untouched on disk")

        // Quick clean ignores it entirely (safe-only filter).
        let quick = try await engine.quickClean(findings: findings, profileName: "test")
        XCTAssertTrue(quick.succeeded.isEmpty)

        // Deep clean (safe + review) must also exclude .advanced findings.
        let deep = try await engine.deepClean(
            findings: findings, profileName: "test", confirmed: true
        )
        XCTAssertTrue(deep.succeeded.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: uvDir.path))
    }

    // MARK: - Helpers

    private func makeRule(
        platformCacheRoot: URL? = nil,
        environmentVariables: [String: String] = [:],
        toolOutput: String?
    ) -> UvCacheRule {
        UvCacheRule(
            resolver: CacheRootResolver(
                platformCacheRoot: platformCacheRoot,
                environmentVariables: environmentVariables
            ),
            toolCacheDirProvider: { toolOutput }
        )
    }
}

// MARK: - ToolCommandRunner

final class ToolCommandRunnerTests: XCTestCase {

    func testCapturesTrimmedStdout() async {
        let runner = ToolCommandRunner()
        let output = await runner.capture(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"]
        )
        XCTAssertEqual(output, "hello")
    }

    func testTimeoutReturnsNilWithoutHanging() async {
        let runner = ToolCommandRunner(timeoutSeconds: 0.5)
        let started = Date()
        let output = await runner.capture(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"]
        )
        XCTAssertNil(output, "A timed-out command must yield nil, not an error")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5,
                          "Timeout must bound the wait (not run the full 10s sleep)")
    }

    func testNonZeroExitReturnsNil() async {
        let runner = ToolCommandRunner()
        let output = await runner.capture(
            executable: URL(fileURLWithPath: "/bin/ls"),
            arguments: ["/definitely/not/a/real/path/\(UUID().uuidString)"]
        )
        XCTAssertNil(output)
    }

    func testMissingExecutableIsSkipped() async {
        let runner = ToolCommandRunner()
        XCTAssertNil(runner.resolveExecutable(
            named: "definitely-not-a-real-tool-\(UUID().uuidString)",
            environmentVariables: ["PATH": "/usr/bin:/bin"]
        ))
        let output = await runner.captureOutput(
            of: ToolCacheCommand(
                executableName: "definitely-not-a-real-tool-\(UUID().uuidString)",
                arguments: ["cache", "dir"]
            ),
            environmentVariables: ["PATH": "/usr/bin:/bin"]
        )
        XCTAssertNil(output, "Absent tool must be skipped, never fatal")
    }

    func testResolvesExecutableFromPath() {
        let runner = ToolCommandRunner()
        let resolved = runner.resolveExecutable(
            named: "ls",
            environmentVariables: ["PATH": "/bin"]
        )
        XCTAssertEqual(resolved?.path, "/bin/ls")
    }
}

// MARK: - Test helpers

private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func createDirWithContent(at url: URL, size: Int = 1024) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let data = Data(repeating: 0xAB, count: size)
    try data.write(to: url.appending(path: "content.bin"))
}

private func backdateItem(at url: URL, days: Int) {
    let date = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
    try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}
