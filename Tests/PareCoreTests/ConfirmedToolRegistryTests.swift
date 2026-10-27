import XCTest
@testable import PareCore

/// Mirrors `KeychainConfirmedToolStore`: returns what was saved, or throws the read error it was given.
final class InMemoryConfirmedToolStore: ConfirmedToolStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tools: [ConfirmableTool: ConfirmedTool]
    private let loadError: KeychainStoreError?
    private let loadDelay: TimeInterval

    init(_ tools: [ConfirmableTool: ConfirmedTool] = [:], loadError: KeychainStoreError? = nil, loadDelay: TimeInterval = 0) {
        self.tools = tools
        self.loadError = loadError
        self.loadDelay = loadDelay
    }

    func load() throws -> [ConfirmableTool: ConfirmedTool] {
        if loadDelay > 0 { Thread.sleep(forTimeInterval: loadDelay) }
        if let loadError { throw loadError }
        return lock.withLock { tools }
    }

    func save(_ tools: [ConfirmableTool: ConfirmedTool]) throws {
        lock.withLock { self.tools = tools }
    }

    var saved: [ConfirmableTool: ConfirmedTool] { lock.withLock { tools } }
}

final class ConfirmedToolRegistryTests: XCTestCase {
    private var root: URL!
    private var marker: URL { root.appending(path: "spawned") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "pare-confirmed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "bin"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A planted tool that leaves a marker file if anything ever launches it.
    @discardableResult
    private func plantMarkerTool(_ name: String) throws -> URL {
        let url = root.appending(path: "bin/\(name)")
        try? FileManager.default.removeItem(at: url)
        try Data("#!/bin/sh\ntouch '\(marker.path)'\necho /tmp/planted/v10\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func copyOfSystemBinary(named name: String) throws -> URL {
        let url = root.appending(path: "bin/\(name)")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/env"), to: url)
        return url
    }

    private var pathEnvironment: [String: String] { ["PATH": root.appending(path: "bin").path + ":/usr/bin:/bin"] }

    func testUnconfirmedToolOnPathIsNeverSpawned() async throws {
        try plantMarkerTool("go")
        try plantMarkerTool("pnpm")
        let registry = ConfirmedToolRegistry(store: InMemoryConfirmedToolStore())

        let go = await GoCacheLocations.confirmedQuery(registry: registry)()
        let pnpm = await PnpmStoreLocator.activeStore(home: root, registry: registry)
        let direct = await ToolCommandRunner().captureConfirmed(
            .go, arguments: [], registry: registry, baseEnvironment: pathEnvironment
        )

        XCTAssertNil(go)
        XCTAssertNil(pnpm, "unconfirmed pnpm behaves as absent, so the cleanup pnpm arm refuses")
        XCTAssertNil(direct)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "nothing found on PATH may run")
    }

    func testConfirmedThenReplacedBinaryIsNotSpawned() async throws {
        let tool = try copyOfSystemBinary(named: "go")
        let store = InMemoryConfirmedToolStore()
        let registry = ConfirmedToolRegistry(store: store)
        _ = try registry.confirm(.go, path: tool.path)
        let confirmedLaunch = await registry.launchURL(for: .go)
        XCTAssertNotNil(confirmedLaunch)

        try FileManager.default.removeItem(at: tool)
        try plantMarkerTool("go")

        let launch = await registry.launchURL(for: .go)
        let output = await ToolCommandRunner().captureConfirmed(.go, arguments: [], registry: registry)
        let state = await registry.state(for: .go, environment: pathEnvironment)
        XCTAssertNil(launch)
        XCTAssertNil(output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "a swapped binary must not run")
        XCTAssertEqual(state, .rejected(path: root.appending(path: "bin/go").path, reason: .script))
        XCTAssertNotNil(store.saved[.go], "the stale confirmation stays until the user acts, so Settings can say it changed")
    }

    func testRewrittenInPlaceIsUnconfirmed() async throws {
        let tool = try copyOfSystemBinary(named: "uv")
        let registry = ConfirmedToolRegistry(store: InMemoryConfirmedToolStore())
        _ = try registry.confirm(.uv, path: tool.path)

        let handle = try FileHandle(forWritingTo: tool)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()

        let launch = await registry.launchURL(for: .uv)
        let state = await registry.state(for: .uv, environment: pathEnvironment)
        let resolved = try XCTUnwrap(realpathString(tool.path))
        XCTAssertNil(launch)
        XCTAssertEqual(state, .available(path: resolved, changed: true))
    }

    func testConfirmedToolRunsWithSanitizedEnvironment() async throws {
        // Copies of system binaries are killed on launch, so the confirmed tool is a symlink to the real one.
        let link = root.appending(path: "bin/go")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/usr/bin/env"))
        let registry = ConfirmedToolRegistry(store: InMemoryConfirmedToolStore())
        let confirmed = try registry.confirm(.go, path: link.path)
        XCTAssertEqual(confirmed.path, "/usr/bin/env", "the resolved path is stored and launched, not the symlink")

        let output = await ToolCommandRunner().captureConfirmed(
            .go,
            arguments: [],
            registry: registry,
            environment: ["NODE_OPTIONS": "--require /tmp/evil.js", "PARE_KEEP": "1"],
            baseEnvironment: [
                "PATH": "/usr/bin:/bin",
                "NODE_PATH": "/tmp/evil",
                "DYLD_FRAMEWORK_PATH": "/tmp/evil",
                "GOTOOLCHAIN": "go1.99.0",
            ]
        )

        let lines = Set(try XCTUnwrap(output).split(separator: "\n").map(String.init))
        XCTAssertTrue(lines.contains("GOTOOLCHAIN=local"))
        XCTAssertTrue(lines.contains("PARE_KEEP=1"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("NODE_") || $0.hasPrefix("DYLD_") }, "\(lines)")
    }

    func testScriptIsRejectedWhateverItsInterpreter() throws {
        let registry = ConfirmedToolRegistry(store: InMemoryConfirmedToolStore())
        for (name, shebang) in [("pnpm", "#!/usr/bin/env node"), ("uv", "#!/bin/sh")] {
            let url = root.appending(path: "bin/\(name)")
            try Data("\(shebang)\nexit 0\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            XCTAssertThrowsError(try registry.confirm(ConfirmableTool(rawValue: name)!, path: url.path), shebang) {
                XCTAssertEqual($0 as? ToolRejection, .script)
            }
        }
    }

    func testMissingOrNonExecutableIsRejected() throws {
        let plain = root.appending(path: "bin/go")
        try Data("not a program".utf8).write(to: plain)
        XCTAssertEqual(rejection(ToolVetting.vet(path: root.appending(path: "missing").path)), .notFound)
        XCTAssertEqual(rejection(ToolVetting.vet(path: plain.path)), .notExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: plain.path)
        XCTAssertEqual(rejection(ToolVetting.vet(path: plain.path)), .notMachO)
    }

    func testUnreadableStoreMeansNothingIsConfirmed() async throws {
        let fingerprint = try XCTUnwrap(ExecutableFingerprint.current(atPath: "/usr/bin/env"))
        let registry = ConfirmedToolRegistry(store: InMemoryConfirmedToolStore(
            [.go: ConfirmedTool(path: "/usr/bin/env", fingerprint: fingerprint)],
            loadError: KeychainStoreError(status: -25293)  // errSecAuthFailed
        ))
        let launch = await registry.launchURL(for: .go)
        XCTAssertNil(launch)
    }

    func testSlowStoreReadTimesOutAsUnconfirmed() async throws {
        let fingerprint = try XCTUnwrap(ExecutableFingerprint.current(atPath: "/usr/bin/env"))
        let registry = ConfirmedToolRegistry(store: InMemoryConfirmedToolStore(
            [.go: ConfirmedTool(path: "/usr/bin/env", fingerprint: fingerprint)], loadDelay: 3
        ))
        let started = Date()
        let launch = await registry.launchURL(for: .go, timeout: 0.2)
        XCTAssertNil(launch, "a read stuck on a Keychain prompt must not hold up the scan")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testForgetKeepsOtherConfirmations() async throws {
        let store = InMemoryConfirmedToolStore()
        let registry = ConfirmedToolRegistry(store: store)
        _ = try registry.confirm(.go, path: "/usr/bin/env")
        _ = try registry.confirm(.uv, path: "/usr/bin/env")
        try registry.forget(.go)

        XCTAssertEqual(Set(store.saved.keys), [.uv])
        let go = await registry.launchURL(for: .go)
        let uv = await registry.launchURL(for: .uv)
        XCTAssertNil(go)
        XCTAssertEqual(uv?.path, "/usr/bin/env")
    }

    func testStoredItemRoundTripsAndDropsUnknownTools() throws {
        let fingerprint = try XCTUnwrap(ExecutableFingerprint.current(atPath: "/usr/bin/env"))
        let tool = ConfirmedTool(path: "/usr/bin/env", fingerprint: fingerprint)
        let data = try ConfirmedToolCoding.encode([.pnpm: tool])
        XCTAssertEqual(try ConfirmedToolCoding.decode(data), [.pnpm: tool])

        var keyed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        keyed["cargo"] = keyed["pnpm"]
        let withUnknown = try JSONSerialization.data(withJSONObject: keyed)
        XCTAssertEqual(try ConfirmedToolCoding.decode(withUnknown), [.pnpm: tool])
    }

    func testSanitizedEnvironmentStripsLoaderHooksAndPinsGoToolchain() {
        let sanitized = ToolSpawnEnvironment.sanitized([
            "HOME": "/Users/x",
            "NODE_OPTIONS": "--require x",
            "NODE_PATH": "/x",
            "DYLD_INSERT_LIBRARIES": "/x.dylib",
            "DYLD_LIBRARY_PATH": "/x",
            "GOTOOLCHAIN": "auto",
        ])
        XCTAssertEqual(sanitized, ["HOME": "/Users/x", "GOTOOLCHAIN": "local"])
    }

    private func rejection(_ result: Result<ConfirmedTool, ToolRejection>) -> ToolRejection? {
        if case .failure(let reason) = result { return reason }
        return nil
    }

    private func realpathString(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }
}
