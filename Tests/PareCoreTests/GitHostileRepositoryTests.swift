import Darwin
import XCTest
@testable import PareCore

/// The git the inspector really runs. CI must exercise these tests, so a missing git fails there instead of skipping.
enum RealGit {
    private struct MissingOnCI: Error {}

    static func locate() async throws -> URL {
        if let git = await GitLocator().locate() { return git }
        if ProcessInfo.processInfo.environment["CI"] != nil { throw MissingOnCI() }
        throw XCTSkip("git is not installed")
    }
}

/// Real-git checks with repositories that try to run code or hide what they track. Payloads only touch a marker file.
final class GitHostileRepositoryTests: XCTestCase {

    private var root: URL!
    private var git: URL!
    private var marker: URL { root.appending(path: "marker") }
    private var markerFired: Bool { FileManager.default.fileExists(atPath: marker.path) }
    private var payload: String { "touch '\(marker.path)'; false" }

    override func setUp() async throws {
        git = try await RealGit.locate()
        root = FileManager.default.temporaryDirectory.appending(path: "pare-hostile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - Nothing a repository names may run

    func testLazyFetchOfMissingIgnoreFileNeverRunsConfiguredSshCommand() async throws {
        let repo = try makeRepoWithMissingIgnoreBlob("lazy-ssh")
        try config(repo, "remote.origin.url", "ssh://nobody@127.0.0.1/x.git")
        try config(repo, "core.sshCommand", payload)
        let dist = try makeArtifact(repo, "dist")

        let statuses = await SystemGitArtifactInspector().statuses(for: [dist])

        XCTAssertFalse(markerFired, "a scanned repo's config ran a program")
        XCTAssertEqual(statuses[dist.path], .notIgnored, "an unreadable ignore file proves nothing is ignored")
    }

    func testLazyFetchNeverRunsRemoteHelperFromInheritedPath() async throws {
        let repo = try makeRepoWithMissingIgnoreBlob("lazy-helper")
        try config(repo, "remote.origin.vcs", "pareprobe")
        try config(repo, "remote.origin.url", "x")
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(bin.appending(path: "git-remote-pareprobe"), body: "touch '\(marker.path)'")
        let dist = try makeArtifact(repo, "dist")
        let path = bin.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")

        _ = await withInheritedEnvironment(["PATH": path]) {
            await SystemGitArtifactInspector().statuses(for: [dist])
        }

        XCTAssertFalse(markerFired, "a remote helper named by the repo ran")
    }

    func testFsmonitorHooksPagerFiltersAndIncludesNeverRun() async throws {
        let repo = try makeRepo("config-vectors", ignoring: "dist/\n")
        let script = root.appending(path: "payload.sh")
        try writeExecutable(script, body: "touch '\(marker.path)'")

        let included = root.appending(path: "included.cfg")
        try Data("[core]\n\tfsmonitor = \(script.path)\n\tpager = \(payload)\n".utf8).write(to: included)
        let hooks = repo.appending(path: "custom-hooks")
        for directory in [hooks, repo.appending(path: ".git/hooks")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for hook in ["post-index-change", "reference-transaction", "post-checkout", "fsmonitor-watchman"] {
            try writeExecutable(hooks.appending(path: hook), body: "touch '\(marker.path)'")
            try writeExecutable(repo.appending(path: ".git/hooks/\(hook)"), body: "touch '\(marker.path)'")
        }
        try Data("* filter=evil diff=evil\n".utf8).write(to: repo.appending(path: ".gitattributes"))
        let settings = [
            ("core.fsmonitor", script.path), ("core.hooksPath", hooks.path), ("core.pager", payload),
            ("pager.check-ignore", payload), ("pager.ls-files", payload), ("pager.rev-parse", payload),
            ("filter.evil.clean", payload), ("filter.evil.smudge", payload), ("filter.evil.process", payload),
            ("filter.evil.required", "true"), ("diff.evil.command", payload), ("diff.evil.textconv", payload),
            ("diff.external", payload), ("include.path", included.path), ("credential.helper", "!\(payload)"),
            ("core.askPass", script.path), ("core.gitProxy", script.path), ("core.editor", payload),
            ("alias.check-ignore", "!\(payload)"), ("alias.ls-files", "!\(payload)"), ("alias.rev-parse", "!\(payload)"),
        ]
        for (key, value) in settings { try config(repo, key, value) }
        let dist = try makeArtifact(repo, "dist")

        let statuses = await SystemGitArtifactInspector().statuses(for: [dist])

        XCTAssertFalse(markerFired)
        XCTAssertEqual(statuses[dist.path], .ignoredUntracked)
    }

    // MARK: - The inherited environment has no say

    func testInheritedGitDirCannotHideTrackedFiles() async throws {
        let repo = try makeRepoTrackingDependencies("inherited-dir")
        let dependency = repo.appending(path: "node_modules")

        let statuses = await withInheritedEnvironment(["GIT_DIR": root.appending(path: "nowhere").path]) {
            await SystemGitArtifactInspector().statuses(for: [dependency])
        }

        XCTAssertEqual(statuses[dependency.path], .containsTrackedFiles)
    }

    func testInheritedCeilingCannotHideTheRepository() async throws {
        let repo = try makeRepoTrackingDependencies("inherited-ceiling")
        let dependency = repo.appending(path: "packages/app/node_modules")

        let statuses = await withInheritedEnvironment(["GIT_CEILING_DIRECTORIES": repo.path]) {
            await SystemGitArtifactInspector().statuses(for: [dependency])
        }

        XCTAssertEqual(statuses[dependency.path], .containsTrackedFiles)
    }

    // MARK: - Only positive evidence means "no repository"

    func testDamagedRepositoryIsNeverReadAsNoRepository() async throws {
        let damages: [(String, (URL) throws -> Void)] = [
            ("corrupt-config", { try Data("not [valid\n".utf8).write(to: $0.appending(path: ".git/config")) }),
            ("unknown-extension", { [self] repo in
                try config(repo, "core.repositoryformatversion", "1")
                try config(repo, "extensions.parebogus", "x")
            }),
            ("future-format", { [self] in try config($0, "core.repositoryformatversion", "99") }),
            ("stale-gitfile", { [self] repo in
                try FileManager.default.removeItem(at: repo.appending(path: ".git"))
                try Data("gitdir: \(root.path)/gone\n".utf8).write(to: repo.appending(path: ".git"))
            }),
            ("garbage-gitfile", { repo in
                try FileManager.default.removeItem(at: repo.appending(path: ".git"))
                try Data("garbage\n".utf8).write(to: repo.appending(path: ".git"))
            }),
            ("empty-git-dir", { repo in
                try FileManager.default.removeItem(at: repo.appending(path: ".git"))
                try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: false)
            }),
            ("no-head", { try FileManager.default.removeItem(at: $0.appending(path: ".git/HEAD")) }),
        ]
        for (name, damage) in damages {
            let repo = try makeRepoTrackingDependencies(name)
            try damage(repo)
            // Beside the `.git`, and with the `.git` above the project folder.
            let dependencies = [repo.appending(path: "node_modules"), repo.appending(path: "packages/app/node_modules")]

            let statuses = await SystemGitArtifactInspector().statuses(for: dependencies)

            for dependency in dependencies {
                XCTAssertEqual(statuses[dependency.path], .failed, "\(name): \(dependency.path)")
                XCTAssertFalse(ScanPolicy.gitEvidenceAllows(dependency: dependency, status: statuses[dependency.path]), name)
            }
        }
    }

    func testUnreadableGitDirectoryIsNotNoRepository() async throws {
        let repo = try makeRepoTrackingDependencies("unreadable")
        let gitDirectory = repo.appending(path: ".git")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: gitDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gitDirectory.path) }
        let dependencies = [repo.appending(path: "node_modules"), repo.appending(path: "packages/app/node_modules")]

        let statuses = await SystemGitArtifactInspector().statuses(for: dependencies)

        for dependency in dependencies {
            XCTAssertEqual(statuses[dependency.path], .failed, dependency.path)
        }
    }

    func testUnreadableAncestorIsNotNoRepository() async throws {
        let locked = root.appending(path: "locked")
        let dependency = try makeArtifact(locked, "app/node_modules")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let statuses = await SystemGitArtifactInspector().statuses(for: [dependency])

        XCTAssertEqual(statuses[dependency.path], .failed)
    }

    func testInsideBareRepositoryOrGitDirectoryIsNotNoRepository() async throws {
        let bare = root.appending(path: "bare.git")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try runGit(["init", "-q", "--bare"], in: bare)
        let inBare = try makeArtifact(bare, "app/node_modules")
        let repo = try makeRepoTrackingDependencies("inside-git")
        let inGit = try makeArtifact(repo, ".git/app/node_modules")

        let statuses = await SystemGitArtifactInspector().statuses(for: [inBare, inGit])

        XCTAssertEqual(statuses[inBare.path], .failed)
        XCTAssertEqual(statuses[inGit.path], .failed)
    }

    func testMissingDirectoryIsNotNoRepository() async {
        let gone = root.appending(path: "does/not/exist/node_modules")

        let statuses = await SystemGitArtifactInspector().statuses(for: [gone])

        XCTAssertEqual(statuses[gone.path], .failed)
    }

    func testSymlinkIntoDamagedRepositoryIsNotNoRepository() async throws {
        let repo = try makeRepoTrackingDependencies("symlink-target")
        try Data("not [valid\n".utf8).write(to: repo.appending(path: ".git/config"))
        let plain = root.appending(path: "plain")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        let link = plain.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo.appending(path: "packages/app"))
        let dependency = URL(fileURLWithPath: link.path + "/node_modules")

        let statuses = await SystemGitArtifactInspector().statuses(for: [dependency])

        XCTAssertEqual(statuses[dependency.path], .failed)
    }

    func testFolderThatIsItselfARepositoryIsNeverAdmitted() async throws {
        let outsideRepo = try makeArtifact(root, "plain/app/node_modules")
        try FileManager.default.createDirectory(at: outsideRepo.appending(path: ".git"), withIntermediateDirectories: true)
        let ignoring = try makeRepo("ignores-nested", ignoring: "node_modules/\n")
        let insideRepo = try makeArtifact(ignoring, "node_modules")
        try runGit(["init", "-q"], in: insideRepo)

        let statuses = await SystemGitArtifactInspector().statuses(for: [outsideRepo, insideRepo])

        XCTAssertEqual(statuses[outsideRepo.path], .failed, "a nested .git is not 'no repository'")
        XCTAssertEqual(statuses[insideRepo.path], .failed, "ignored by the outer repo, but it is its own repository")
        XCTAssertFalse(ScanPolicy.gitEvidenceAllows(dependency: insideRepo, status: statuses[insideRepo.path]))
    }

    func testTrackedFolderIsNotIgnoredWhenCoreWorktreePointsAtAnotherRepository() async throws {
        let tracking = try makeRepoTrackingDependencies("worktree-redirected")
        let other = try makeRepo("worktree-other", ignoring: "node_modules/\n")
        _ = try makeArtifact(other, "node_modules")
        try config(tracking, "core.worktree", other.path)
        let dependency = URL(fileURLWithPath: tracking.path + "/node_modules")

        let statuses = await SystemGitArtifactInspector().statuses(for: [dependency])

        XCTAssertEqual(statuses[dependency.path], .failed, "the other repo's ignore rules say nothing about this folder")
    }

    func testPlainFolderIsStillNotInRepository() async throws {
        let dependency = try makeArtifact(root, "plain/app/node_modules")

        let statuses = await SystemGitArtifactInspector().statuses(for: [dependency])

        XCTAssertEqual(statuses[dependency.path], .notInRepository)
        XCTAssertTrue(ScanPolicy.gitEvidenceAllows(dependency: dependency, status: statuses[dependency.path]))
    }

    // MARK: - Helpers

    private func withInheritedEnvironment<T>(_ variables: [String: String], _ body: () async -> T) async -> T {
        let saved: [(String, String?)] = variables.keys.map { key in (key, getenv(key).map { String(cString: $0) }) }
        for (key, value) in variables { setenv(key, value, 1) }
        defer {
            for (key, value) in saved {
                if let value { setenv(key, value, 1) } else { unsetenv(key) }
            }
        }
        return await body()
    }

    private func makeRepo(_ name: String, ignoring ignore: String) throws -> URL {
        let repo = root.appending(path: name)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: repo)
        try Data(ignore.utf8).write(to: repo.appending(path: ".gitignore"))
        try runGit(["add", ".gitignore"], in: repo)
        try runGit(["commit", "-qm", "init"], in: repo)
        return repo
    }

    private func makeRepoTrackingDependencies(_ name: String) throws -> URL {
        let repo = try makeRepo(name, ignoring: "")
        _ = try makeArtifact(repo, "node_modules")
        _ = try makeArtifact(repo, "packages/app/node_modules")
        try runGit(["add", "-f", "node_modules", "packages"], in: repo)
        try runGit(["commit", "-qm", "track dependencies"], in: repo)
        return repo
    }

    /// A partial clone whose committed `.gitignore` is neither on disk nor in the object store, so reading it needs a fetch.
    private func makeRepoWithMissingIgnoreBlob(_ name: String) throws -> URL {
        let repo = try makeRepo(name, ignoring: "dist/\n")
        let blob = try runGit(["rev-parse", ":.gitignore"], in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["update-index", "--skip-worktree", ".gitignore"], in: repo)
        try FileManager.default.removeItem(at: repo.appending(path: ".gitignore"))
        try FileManager.default.removeItem(at: repo.appending(path: ".git/objects/\(blob.prefix(2))/\(blob.dropFirst(2))"))
        try config(repo, "core.repositoryformatversion", "1")
        try config(repo, "extensions.partialClone", "origin")
        try config(repo, "remote.origin.promisor", "true")
        return repo
    }

    private func makeArtifact(_ base: URL, _ relative: String) throws -> URL {
        let directory = base.appending(path: relative)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 64).write(to: directory.appending(path: "payload.bin"))
        return URL(fileURLWithPath: directory.path)
    }

    private func writeExecutable(_ url: URL, body: String) throws {
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func config(_ repo: URL, _ key: String, _ value: String) throws {
        try runGit(["config", key, value], in: repo)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = git
        process.arguments = ["-c", "user.name=pare", "-c", "user.email=pare@example.invalid", "-c", "commit.gpgsign=false",
                             "-c", "core.hooksPath=/dev/null", "-C", directory.path] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " "))")
        return String(decoding: data, as: UTF8.self)
    }
}

/// Git older than 2.45 rejects `--no-lazy-fetch` with exit 129; that must never read as "no repository".
final class OldGitTests: XCTestCase {
    private let git = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/git")
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appending(path: "pare-oldgit-\(UUID().uuidString)").resolvingSymlinksInPath()
        for name in ["a", "b"] {
            try FileManager.default.createDirectory(at: base.appending(path: "\(name)/node_modules"), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func inspector(version: String?, versionCalls: LockedCounter) -> SystemGitArtifactInspector {
        SystemGitArtifactInspector(locateGit: { [git] in git }, run: { _, arguments, _ in
            if arguments == ["--version"] {
                versionCalls.increment()
                return version.map { (exitCode: 0, stdout: Data($0.utf8)) }
            }
            return (exitCode: 129, stdout: Data())
        })
    }

    func testGitBelow245ReadsTooOldAndIsAskedForItsVersionOnce() async {
        let calls = LockedCounter()
        let dirs = ["a", "b"].map { base.appending(path: "\($0)/node_modules") }

        let statuses = await inspector(version: "git version 2.39.5 (Apple Git-154)\n", versionCalls: calls).statuses(for: dirs)

        XCTAssertEqual(Set(dirs.map { statuses[$0.path] }), [.gitTooOld])
        XCTAssertEqual(calls.value, 1)
    }

    func testExit129FromACurrentOrUnknownGitStaysFailed() async {
        let dirs = [base.appending(path: "a/node_modules")]
        for version in ["git version 2.54.0 (Apple Git-157)\n", "git version 3.0.0\n", "garbage", nil] {
            let statuses = await inspector(version: version, versionCalls: LockedCounter()).statuses(for: dirs)
            XCTAssertEqual(statuses[dirs[0].path], .failed, String(describing: version))
        }
    }

    func testVersionParsing() {
        XCTAssertEqual(GitVersion(output: "git version 2.54.0 (Apple Git-157)\n"), GitVersion(major: 2, minor: 54))
        XCTAssertEqual(GitVersion(output: "git version 2.45.0"), GitVersion.noLazyFetchSupport)
        XCTAssertTrue(GitVersion(major: 2, minor: 44) < GitVersion.noLazyFetchSupport)
        XCTAssertFalse(GitVersion(major: 10, minor: 0) < GitVersion.noLazyFetchSupport)
        XCTAssertNil(GitVersion(output: "git version"))
        XCTAssertNil(GitVersion(output: "hg 6.1"))
    }
}

/// What every git call carries, whatever repository it runs in.
final class GitInvocationTests: XCTestCase {

    func testEveryCallIsolatesGitFromLazyFetchAndTheInheritedEnvironment() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appending(path: "pare-invocation-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: repo) }
        try FileManager.default.createDirectory(at: repo.appending(path: "build"), withIntermediateDirectories: true)
        let recorder = GitCallRecorder()
        let inspector = SystemGitArtifactInspector(
            locateGit: { URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/git") },
            run: { _, arguments, environment in
                recorder.record(arguments, environment)
                return arguments.contains("rev-parse")
                    ? (exitCode: 0, stdout: Data("\(repo.path)\n\n".utf8))
                    : (exitCode: 0, stdout: Data())
            }
        )

        _ = await inspector.statuses(for: [repo.appending(path: "build")])

        XCTAssertEqual(recorder.calls.count, 3, "rev-parse, check-ignore, ls-files")
        for call in recorder.calls {
            XCTAssertTrue(call.arguments.contains("--no-lazy-fetch"), "\(call.arguments)")
            XCTAssertTrue(call.arguments.contains("--no-pager"), "\(call.arguments)")
            XCTAssertTrue(call.arguments.contains("core.fsmonitor=false"), "\(call.arguments)")
            XCTAssertEqual(call.environment["GIT_ALLOW_PROTOCOL"], "none")
            XCTAssertEqual(call.environment["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
            XCTAssertEqual(
                Set(call.environment.keys).subtracting(["HOME"]),
                ["PATH", "LC_ALL", "GIT_OPTIONAL_LOCKS", "GIT_TERMINAL_PROMPT", "GIT_ALLOW_PROTOCOL"]
            )
        }
    }
}

private final class GitCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(arguments: [String], environment: [String: String])] = []

    var calls: [(arguments: [String], environment: [String: String])] { lock.withLock { recorded } }

    func record(_ arguments: [String], _ environment: [String: String]) {
        lock.withLock { recorded.append((arguments, environment)) }
    }
}
