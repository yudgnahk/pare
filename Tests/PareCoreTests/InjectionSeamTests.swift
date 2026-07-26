import XCTest
@testable import PareCore

// MARK: - StubProcessRunner

/// Scriptable `ProcessRunning` stub. Records every invocation and replays a
/// fixed result / line sequence without spawning real processes.
final class StubProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executablePath: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var _invocations: [Invocation] = []

    var invocations: [Invocation] { lock.withLock { _invocations } }

    let result: ProcessResult
    let lines: [ProcessOutputLine]
    let streamError: ProcessRunnerError?

    init(
        result: ProcessResult = ProcessResult(standardOutput: "", standardError: "", exitCode: 0),
        lines: [ProcessOutputLine] = [],
        streamError: ProcessRunnerError? = nil
    ) {
        self.result = result
        self.lines = lines
        self.streamError = streamError
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> ProcessResult {
        lock.withLock {
            _invocations.append(Invocation(executablePath: executablePath, arguments: arguments))
        }
        return result
    }

    func streamLines(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessOutputLine, Error> {
        lock.withLock {
            _invocations.append(Invocation(executablePath: executablePath, arguments: arguments))
        }
        let lines = self.lines
        let streamError = self.streamError
        return AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            if let streamError {
                continuation.finish(throwing: streamError)
            } else {
                continuation.finish()
            }
        }
    }
}

// MARK: - ProcessRunning seam: BrewRunner

final class BrewRunnerSeamTests: XCTestCase {

    func testRunReturnsStdoutAndInvokesInjectedRunner() async throws {
        let stub = StubProcessRunner(
            result: ProcessResult(standardOutput: "wget 1.0\n", standardError: "", exitCode: 0)
        )
        let runner = BrewRunner(brewPath: "/fake/bin/brew", processRunner: stub)

        let output = try await runner.run(["list", "--versions"])

        XCTAssertEqual(output, "wget 1.0\n")
        XCTAssertEqual(stub.invocations, [
            .init(executablePath: "/fake/bin/brew", arguments: ["list", "--versions"])
        ])
    }

    func testRunThrowsFailedOnNonZeroExit() async {
        let stub = StubProcessRunner(
            result: ProcessResult(standardOutput: "", standardError: "boom", exitCode: 1)
        )
        let runner = BrewRunner(brewPath: "/fake/bin/brew", processRunner: stub)

        do {
            _ = try await runner.run(["upgrade"])
            XCTFail("Expected BrewError.failed")
        } catch let BrewError.failed(exitCode, stderr) {
            XCTAssertEqual(exitCode, 1)
            XCTAssertEqual(stderr, "boom")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRunThrowsNotInstalledWhenBrewPathMissing() async {
        let stub = StubProcessRunner()
        let runner = BrewRunner(brewPath: nil, processRunner: stub)

        do {
            _ = try await runner.run(["list"])
            XCTFail("Expected BrewError.notInstalled")
        } catch BrewError.notInstalled {
            XCTAssertTrue(stub.invocations.isEmpty, "No process must be spawned without a brew path")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(runner.isInstalled)
    }

    func testStreamYieldsStdoutAndStderrInterleaved() async throws {
        let stub = StubProcessRunner(lines: [
            .stdout("==> Upgrading wget"),
            .stderr("Warning: slow mirror"),
            .stdout("done"),
        ])
        let runner = BrewRunner(brewPath: "/fake/bin/brew", processRunner: stub)

        var collected: [String] = []
        for try await line in runner.stream(["upgrade", "wget"]) {
            collected.append(line)
        }

        XCTAssertEqual(collected, ["==> Upgrading wget", "Warning: slow mirror", "done"])
    }

    func testStreamMapsNonZeroExitToBrewError() async {
        let stub = StubProcessRunner(
            lines: [.stdout("partial")],
            streamError: .nonZeroExit(exitCode: 2, stderr: "broken tap")
        )
        let runner = BrewRunner(brewPath: "/fake/bin/brew", processRunner: stub)

        var collected: [String] = []
        do {
            for try await line in runner.stream(["upgrade"]) {
                collected.append(line)
            }
            XCTFail("Expected BrewError.failed")
        } catch let BrewError.failed(exitCode, _) {
            XCTAssertEqual(exitCode, 2)
            XCTAssertEqual(collected, ["partial"], "Lines before the failure must still be yielded")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - ProcessRunning seam: BrewOutdatedChecker

final class BrewOutdatedCheckerSeamTests: XCTestCase {

    func testCheckParsesStubbedOutdatedJSON() async throws {
        let json = """
        {
          "formulae": [
            {"name": "wget", "installed_versions": ["1.21"], "current_version": "1.24", "pinned": false}
          ],
          "casks": [
            {"name": "firefox", "installed_versions": "124.0", "current_version": "125.0", "auto_updates": true}
          ]
        }
        """
        let stub = StubProcessRunner(
            result: ProcessResult(standardOutput: json, standardError: "", exitCode: 0)
        )
        let checker = BrewOutdatedChecker(runner: BrewRunner(brewPath: "/fake/bin/brew", processRunner: stub))

        let packages = try await checker.check()

        XCTAssertEqual(packages.count, 2)
        XCTAssertEqual(stub.invocations.first?.arguments, ["outdated", "--json=v2", "--greedy"])

        let firefox = try XCTUnwrap(packages.first { $0.name == "firefox" })
        XCTAssertFalse(firefox.isFormula)
        XCTAssertTrue(firefox.isAutoUpdate)
        XCTAssertEqual(firefox.installedVersions, ["124.0"])
        XCTAssertEqual(firefox.currentVersion, "125.0")

        let wget = try XCTUnwrap(packages.first { $0.name == "wget" })
        XCTAssertTrue(wget.isFormula)
        XCTAssertFalse(wget.pinned)
        XCTAssertEqual(wget.installedVersions, ["1.21"])
    }
}

// MARK: - ProcessRunning seam: MaintenanceRunner

final class MaintenanceRunnerSeamTests: XCTestCase {

    func testFlushDNSRunsBothStepsThroughInjectedRunner() async throws {
        let stub = StubProcessRunner(lines: [.stdout("ok")])
        let runner = MaintenanceRunner(processRunner: stub)

        var collected: [String] = []
        for try await line in runner.run(action: MaintenanceCatalog.flushDNS) {
            collected.append(line)
        }

        XCTAssertEqual(stub.invocations, [
            .init(executablePath: "/usr/bin/dscacheutil", arguments: ["-flushcache"]),
            .init(executablePath: "/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"]),
        ])
        XCTAssertEqual(collected.first, "→ Flushing DNS cache…")
        XCTAssertEqual(collected.last, "✓ DNS cache flushed successfully.")
        XCTAssertTrue(collected.contains("ok"))
    }

    func testStderrOnlyOutputIsNotYieldedAsProgress() async throws {
        let stub = StubProcessRunner(lines: [.stderr("noise")])
        let runner = MaintenanceRunner(processRunner: stub)

        var collected: [String] = []
        for try await line in runner.run(action: MaintenanceCatalog.restartFinder) {
            collected.append(line)
        }

        XCTAssertFalse(collected.contains("noise"), "stderr lines must not surface as progress output")
        XCTAssertEqual(collected.last, "✓ Finder restarted. It will relaunch automatically.")
    }

    func testNonZeroExitMapsToMaintenanceError() async {
        let stub = StubProcessRunner(streamError: .nonZeroExit(exitCode: 3, stderr: "denied"))
        let runner = MaintenanceRunner(processRunner: stub)

        do {
            for try await _ in runner.run(action: MaintenanceCatalog.restartFinder) {}
            XCTFail("Expected MaintenanceError.nonZeroExit")
        } catch let MaintenanceError.nonZeroExit(code, stderr) {
            XCTAssertEqual(code, 3)
            XCTAssertEqual(stderr, "denied")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingExecutableMapsToMaintenanceError() async {
        let stub = StubProcessRunner(streamError: .executableNotFound("/usr/bin/killall"))
        let runner = MaintenanceRunner(processRunner: stub)

        do {
            for try await _ in runner.run(action: MaintenanceCatalog.restartFinder) {}
            XCTFail("Expected MaintenanceError.executableNotFound")
        } catch let MaintenanceError.executableNotFound(path) {
            XCTAssertEqual(path, "/usr/bin/killall")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Clock injection

final class ClockInjectionTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "ClockInjectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testPassesUnusedAgeWithInjectedClock() throws {
        // Freshly created file — no attribute back-dating.
        let file = tempDir.appending(path: "fresh.bin")
        try Data([0x01]).write(to: file)

        let sevenDays: TimeInterval = 7 * 86_400

        XCTAssertFalse(
            ScanPolicy.passesUnusedAge(for: file, minimumAgeSeconds: sevenDays, now: Date()),
            "A file written just now must fail a 7-day gate with the real clock"
        )
        XCTAssertTrue(
            ScanPolicy.passesUnusedAge(for: file, minimumAgeSeconds: sevenDays, now: Date().addingTimeInterval(8 * 86_400)),
            "Shifting the injected clock 8 days forward must pass the 7-day gate"
        )
    }

    func testPassesMinimumAgeWithInjectedClock() throws {
        let file = tempDir.appending(path: "fresh2.bin")
        try Data([0x02]).write(to: file)
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .isDirectoryKey])

        XCTAssertFalse(
            ScanPolicy.passesMinimumAge(for: values, minimumAgeSeconds: 86_400, now: Date())
        )
        XCTAssertTrue(
            ScanPolicy.passesMinimumAge(for: values, minimumAgeSeconds: 86_400, now: Date().addingTimeInterval(2 * 86_400))
        )
        // nil threshold always passes regardless of clock.
        XCTAssertTrue(ScanPolicy.passesMinimumAge(for: values, minimumAgeSeconds: nil, now: .distantPast))
    }

    func testCleanupEngineAgeRecheckUsesInjectedClock() async throws {
        // Fresh file under a /Library/Logs/ path: passes the safety policy, is not
        // a reconstructible cache (those have no multi-day age gate), and carries
        // the 1-day logs age gate — so it fails on the real clock.
        let logsDir = tempDir.appending(path: "Library/Logs/com.pare.clock-test")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let file = logsDir.appending(path: "fresh.log")
        try Data(repeating: 0x41, count: 64).write(to: file)

        let finding = ScanFinding(
            category: .logsAndCrashReports,
            riskLevel: .safe,
            reason: "Fresh log file",
            path: file.path,
            sizeBytes: 64,
            lastUsed: nil,
            confidence: 1.0
        )
        let storeDir = tempDir.appending(path: "store")
        let store = CleanupTransactionStore(directory: storeDir)

        // Real clock: the fresh file is younger than the cache minimum age → skipped.
        let realClockEngine = CleanupEngine(store: store)
        let skippedResult = try await realClockEngine.clean(
            findings: [finding], profileName: "test", dryRun: true
        )
        XCTAssertEqual(skippedResult.succeeded.count, 0)
        XCTAssertEqual(skippedResult.skipped.count, 1)

        // Clock shifted 30 days forward: the same file now passes the age gate.
        let shifted = Date().addingTimeInterval(30 * 86_400)
        let shiftedClockEngine = CleanupEngine(store: store, now: { shifted })
        let cleanedResult = try await shiftedClockEngine.clean(
            findings: [finding], profileName: "test", dryRun: true
        )
        XCTAssertEqual(cleanedResult.succeeded.count, 1)
        XCTAssertEqual(cleanedResult.skipped.count, 0)
    }
}

// MARK: - URLProtocol stubbing seam

/// Serves canned responses for stubbed URLs; fails any unexpected request.
final class StubURLProtocol: URLProtocol {
    /// URL absoluteString (or prefix) → response body.
    nonisolated(unsafe) static var responses: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let urlString = request.url?.absoluteString ?? ""
        if let match = Self.responses.first(where: { urlString.hasPrefix($0.key) }) {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: match.value)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        }
    }

    override func stopLoading() {}
}

final class OutdatedCheckerURLStubTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "OutdatedCheckerStub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        StubURLProtocol.responses = [:]
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        StubURLProtocol.responses = [:]
    }

    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testMASUpdateCheckUsesInjectedSession() async throws {
        let lookupJSON = """
        {"results": [
            {"bundleId": "com.example.masapp", "version": "2.5.0", "trackId": 12345}
        ]}
        """
        StubURLProtocol.responses["https://itunes.apple.com/lookup"] = Data(lookupJSON.utf8)

        let app = InstalledApp(
            name: "MAS App",
            bundleID: "com.example.masapp",
            version: "1.0.0",
            buildVersion: "100",
            path: tempDir.appending(path: "MAS App.app").path,
            sizeBytes: 0,
            installDate: nil,
            lastUsed: nil,
            isMAS: true,
            isSystemApp: false
        )

        let checker = OutdatedChecker(session: makeStubbedSession())
        let updates = await checker.checkAll([app])

        let info = try XCTUnwrap(updates["com.example.masapp"])
        XCTAssertEqual(info.availableVersion, "2.5.0")
        XCTAssertEqual(info.installedVersion, "1.0.0")
        XCTAssertEqual(info.channel, .mas)
        XCTAssertTrue(info.hasUpdate)
        XCTAssertEqual(info.updateURL?.absoluteString, "macappstore://apps.apple.com/app/id12345")
    }

    func testSparkleUpdateCheckUsesInjectedSession() async throws {
        // Fake .app bundle whose Info.plist advertises a Sparkle feed.
        let appBundle = tempDir.appending(path: "Sparkly.app")
        let contents = appBundle.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.sparkly",
            "SUFeedURL": "https://stub.invalid/appcast.xml",
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appending(path: "Info.plist"))

        let appcast = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <enclosure url="https://stub.invalid/Sparkly-300.zip" sparkle:version="300" />
            </item>
          </channel>
        </rss>
        """
        StubURLProtocol.responses["https://stub.invalid/appcast.xml"] = Data(appcast.utf8)

        let app = InstalledApp(
            name: "Sparkly",
            bundleID: "com.example.sparkly",
            version: "2.0",
            buildVersion: "200",
            path: appBundle.path,
            sizeBytes: 0,
            installDate: nil,
            lastUsed: nil,
            isMAS: false,
            isSystemApp: false
        )

        let checker = OutdatedChecker(session: makeStubbedSession())
        let updates = await checker.checkAll([app])

        let info = try XCTUnwrap(updates["com.example.sparkly"])
        XCTAssertEqual(info.availableVersion, "300")
        XCTAssertEqual(info.installedVersion, "200")
        XCTAssertEqual(info.channel, .sparkle)
        XCTAssertTrue(info.hasUpdate)
        XCTAssertEqual(info.updateURL?.absoluteString, "https://stub.invalid/Sparkly-300.zip")
    }
}

// MARK: - Safe fallback for FileManager.urls

final class DefaultStoreURLFallbackTests: XCTestCase {

    /// The four previously crash-prone `.first!` call sites now use the
    /// `?? temporaryDirectory` fallback. On a normal system the lookup still
    /// resolves; these constructors must simply never trap.
    func testDefaultInitializersDoNotTrap() {
        _ = ExclusionStore()
        _ = CleanupTransactionStore()
        _ = ProjectRootDiscovery()
        _ = MigrationAdvisor()
    }
}
