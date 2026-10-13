import XCTest
@testable import PareCore

/// Real-git checks of the ignore/tracked evidence behind the `build`/`dist`/`target` gate.
final class GitArtifactInspectorTests: XCTestCase {

    private var root: URL!
    private var git: URL!

    override func setUp() async throws {
        guard let located = await GitLocator().locate() else {
            throw XCTSkip("git is not installed")
        }
        git = located
        root = FileManager.default.temporaryDirectory.appending(path: "pare-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testIgnoredUntrackedDirectory() async throws {
        let repo = try makeRepo("app", gitignore: "dist/\n")
        let dist = try makeArtifact(repo, "dist")

        let statuses = await SystemGitArtifactInspector().statuses(for: [dist])

        XCTAssertEqual(statuses[dist.path], .ignoredUntracked)
    }

    func testNotIgnoredDirectory() async throws {
        let repo = try makeRepo("app", gitignore: "node_modules/\n")
        let build = try makeArtifact(repo, "build")

        let statuses = await SystemGitArtifactInspector().statuses(for: [build])

        XCTAssertEqual(statuses[build.path], .notIgnored)
    }

    func testForceAddedFileMarksDirectoryTracked() async throws {
        let repo = try makeRepo("app", gitignore: "dist/\n")
        let dist = try makeArtifact(repo, "dist")
        try runGit(["add", "-f", "dist/payload.bin"], in: repo)

        let statuses = await SystemGitArtifactInspector().statuses(for: [dist])

        XCTAssertEqual(statuses[dist.path], .containsTrackedFiles)
    }

    func testIgnoredParentCoversNestedArtifact() async throws {
        let repo = try makeRepo("app", gitignore: "android/\n")
        let build = try makeArtifact(repo, "android/build")

        let statuses = await SystemGitArtifactInspector().statuses(for: [build])

        XCTAssertEqual(statuses[build.path], .ignoredUntracked)
    }

    /// Committed-looking outputs in a monorepo whose `.gitignore` does not cover them.
    func testUnignoredNestedOutputsAreNotIgnored() async throws {
        let repo = try makeRepo("app", gitignore: "node_modules/\n")
        let androidBuild = try makeArtifact(repo, "android/build")
        let dashboardDist = try makeArtifact(repo, "dashboard/dist")

        let statuses = await SystemGitArtifactInspector().statuses(for: [androidBuild, dashboardDist])

        XCTAssertEqual(statuses[androidBuild.path], .notIgnored)
        XCTAssertEqual(statuses[dashboardDist.path], .notIgnored)
    }

    func testDirectoryOutsideAnyRepositoryIsNotInRepository() async throws {
        let build = try makeArtifact(root, "plain/build")

        let statuses = await SystemGitArtifactInspector().statuses(for: [build])

        XCTAssertEqual(statuses[build.path], .notInRepository)
    }

    func testInnerRepositoryUsesItsOwnIgnoreRules() async throws {
        let outer = try makeRepo("outer", gitignore: "build/\n")
        let inner = try makeRepo("outer/inner", gitignore: "out/\n")
        let outerBuild = try makeArtifact(outer, "build")
        let innerBuild = try makeArtifact(inner, "build")
        let innerOut = try makeArtifact(inner, "out")

        let statuses = await SystemGitArtifactInspector().statuses(for: [outerBuild, innerBuild, innerOut])

        XCTAssertEqual(statuses[outerBuild.path], .ignoredUntracked)
        XCTAssertEqual(statuses[innerBuild.path], .notIgnored)
        XCTAssertEqual(statuses[innerOut.path], .ignoredUntracked)
    }

    /// `rev-parse` reports the realpath; both spellings of a `/tmp` path must still resolve.
    func testTmpAndPrivateTmpSpellingsBothResolve() async throws {
        let base = URL(fileURLWithPath: "/tmp/pare-git-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = base.appending(path: "app")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: repo)
        try Data("dist/\n".utf8).write(to: repo.appending(path: ".gitignore"))
        _ = try makeArtifact(repo, "dist")
        let tmpSpelling = URL(fileURLWithPath: repo.path + "/dist")
        let privateSpelling = URL(fileURLWithPath: "/private" + repo.path + "/dist")

        let statuses = await SystemGitArtifactInspector().statuses(for: [tmpSpelling, privateSpelling])

        XCTAssertEqual(statuses[tmpSpelling.path], .ignoredUntracked)
        XCTAssertEqual(statuses[privateSpelling.path], .ignoredUntracked)
    }

    func testBatchesAreSplitToStayUnderArgumentLimit() async throws {
        let repo = try makeRepo("app", gitignore: "dist/\n")
        let ignored = try (0..<6).map { try makeArtifact(repo, "pkg\($0)/dist") }
        let visible = try makeArtifact(repo, "pkg-visible/build")
        try runGit(["add", "-f", "pkg5/dist/payload.bin"], in: repo)

        let inspector = SystemGitArtifactInspector(maxArgumentBytesPerCall: 32)
        let statuses = await inspector.statuses(for: ignored + [visible])

        for dist in ignored.dropLast() {
            XCTAssertEqual(statuses[dist.path], .ignoredUntracked, dist.path)
        }
        XCTAssertEqual(statuses[ignored[5].path], .containsTrackedFiles)
        XCTAssertEqual(statuses[visible.path], .notIgnored)
    }

    // MARK: - Helpers

    private func makeRepo(_ relative: String, gitignore: String) throws -> URL {
        let repo = root.appending(path: relative)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: repo)
        try Data(gitignore.utf8).write(to: repo.appending(path: ".gitignore"))
        return repo
    }

    private func makeArtifact(_ base: URL, _ relative: String) throws -> URL {
        let dir = base.appending(path: relative)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 64).write(to: dir.appending(path: "payload.bin"))
        return URL(fileURLWithPath: dir.path)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = git
        process.arguments = ["-C", directory.path] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " "))")
    }
}

/// Inspector paths that never reach a real git.
final class GitArtifactInspectorFailureTests: XCTestCase {

    private let dirs = [
        URL(fileURLWithPath: "/Users/u/Projects/app/build"),
        URL(fileURLWithPath: "/Users/u/Projects/app/dist"),
    ]

    func testMissingGitReportsGitUnavailable() async {
        let inspector = SystemGitArtifactInspector(locateGit: { nil })

        let statuses = await inspector.statuses(for: dirs)

        XCTAssertEqual(statuses, Dictionary(uniqueKeysWithValues: dirs.map { ($0.path, .gitUnavailable) }))
    }

    func testRunnerTimeoutReportsFailed() async {
        let inspector = SystemGitArtifactInspector(
            locateGit: { URL(fileURLWithPath: "/opt/homebrew/bin/git") },
            run: { _, _, _ in nil }
        )

        let statuses = await inspector.statuses(for: dirs)

        XCTAssertEqual(statuses, Dictionary(uniqueKeysWithValues: dirs.map { ($0.path, .failed) }))
    }

    func testUnexpectedExitCodeReportsFailed() async {
        let inspector = SystemGitArtifactInspector(
            locateGit: { URL(fileURLWithPath: "/opt/homebrew/bin/git") },
            run: { _, arguments, _ in
                arguments.contains("rev-parse")
                    ? (exitCode: 0, stdout: Data("/Users/u/Projects/app\n\n".utf8))
                    : (exitCode: 2, stdout: Data())
            }
        )

        let statuses = await inspector.statuses(for: dirs)

        XCTAssertEqual(statuses, Dictionary(uniqueKeysWithValues: dirs.map { ($0.path, .failed) }))
    }

    func testEmptyInputNeverLocatesGit() async {
        let located = LockedCounter()
        let inspector = SystemGitArtifactInspector(locateGit: {
            located.increment()
            return nil
        })

        let statuses = await inspector.statuses(for: [])

        XCTAssertTrue(statuses.isEmpty)
        XCTAssertEqual(located.value, 0)
    }
}

final class GitLocatorTests: XCTestCase {

    private let cltDirectory = "/Library/Developer/CommandLineTools"

    func testNeverReturnsUsrBinShimWhenDeveloperToolsAreMissing() async {
        let locator = GitLocator(
            environment: ["PATH": "/usr/bin:/bin"],
            isExecutable: { $0 == "/usr/bin/git" },
            developerDirectory: { nil }
        )

        let located = await locator.locate()

        XCTAssertNil(located)
    }

    func testUsesDeveloperDirectoryGitWhenXcodeSelectSucceeds() async {
        let cltGit = cltDirectory + "/usr/bin/git"
        let locator = GitLocator(
            environment: ["PATH": "/usr/bin:/bin"],
            isExecutable: { $0 == "/usr/bin/git" || $0 == cltGit },
            developerDirectory: { [cltDirectory] in cltDirectory }
        )

        let located = await locator.locate()

        XCTAssertEqual(located?.path, cltGit)
    }

    func testPrefersPathEntryAndSkipsXcodeSelect() async {
        let asked = LockedCounter()
        let locator = GitLocator(
            environment: ["PATH": "/usr/bin:/custom/bin"],
            isExecutable: { $0 == "/usr/bin/git" || $0 == "/custom/bin/git" },
            developerDirectory: {
                asked.increment()
                return nil
            }
        )

        let located = await locator.locate()

        XCTAssertEqual(located?.path, "/custom/bin/git")
        XCTAssertEqual(asked.value, 0)
    }

    func testFallsBackToHomebrewLocations() async {
        let locator = GitLocator(
            environment: [:],
            isExecutable: { $0 == "/opt/homebrew/bin/git" },
            developerDirectory: { nil }
        )

        let located = await locator.locate()

        XCTAssertEqual(located?.path, "/opt/homebrew/bin/git")
    }
}

final class ToolCommandRunnerRunTests: XCTestCase {

    func testReturnsExitCodeAndStdoutForNonZeroExit() async {
        let result = await ToolCommandRunner().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf hi; exit 3"]
        )

        XCTAssertEqual(result?.exitCode, 3)
        XCTAssertEqual(result.map { String(decoding: $0.stdout, as: UTF8.self) }, "hi")
    }

    func testEnvironmentIsAddedToInheritedEnvironment() async {
        let result = await ToolCommandRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [],
            environment: ["PARE_RUNNER_PROBE": "1"]
        )

        let output = result.map { String(decoding: $0.stdout, as: UTF8.self) } ?? ""
        XCTAssertTrue(output.contains("PARE_RUNNER_PROBE=1"))
        XCTAssertTrue(output.contains("PATH="), "inherited variables must survive")
    }

    func testTimeoutReturnsNil() async {
        let result = await ToolCommandRunner(timeoutSeconds: 0.5).run(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"]
        )

        XCTAssertNil(result)
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
