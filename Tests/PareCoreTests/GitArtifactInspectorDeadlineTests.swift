import XCTest
@testable import PareCore

/// One `statuses(for:)` call stays bounded however many projects it is handed, and fails closed past its deadline.
final class GitArtifactInspectorDeadlineTests: XCTestCase {

    private let git = URL(fileURLWithPath: "/opt/homebrew/bin/git")

    func testDirectoriesPastTheDeadlineFailClosedWithoutRunningGit() async {
        let clock = GitClock()
        let calls = LockedCounter()
        let inspector = SystemGitArtifactInspector(
            locateGit: { [git] in git },
            run: { _, _, _ in
                calls.increment()
                clock.advance(by: 3)
                return (exitCode: 128, stdout: Data())
            },
            totalDeadline: 20,
            now: clock.now
        )
        let dirs = (0..<300).map { URL(fileURLWithPath: "/Users/u/Projects/p\($0)/build") }

        let statuses = await inspector.statuses(for: dirs)

        XCTAssertEqual(calls.value, 7, "one rev-parse per 3 s until 20 s have passed")
        XCTAssertEqual(statuses.count, dirs.count)
        XCTAssertEqual(dirs.prefix(7).map { statuses[$0.path] }, Array(repeating: .notInRepository, count: 7))
        XCTAssertEqual(Set(dirs.dropFirst(7).map { statuses[$0.path] }), [.failed])
    }

    func testDeadlinePassedDuringLookupSkipsCheckIgnore() async {
        let clock = GitClock()
        let calls = LockedCounter()
        let inspector = SystemGitArtifactInspector(
            locateGit: { [git] in git },
            run: { _, _, _ in
                calls.increment()
                clock.advance(by: 3)
                return (exitCode: 0, stdout: Data("/Users/u/Projects/app\n\n".utf8))
            },
            totalDeadline: 2,
            now: clock.now
        )
        let build = URL(fileURLWithPath: "/Users/u/Projects/app/build")

        let statuses = await inspector.statuses(for: [build])

        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(statuses, [build.path: .failed])
    }

    func testFoldersOfOneRepositoryShareOneLookupButNestedRepositoriesGetTheirOwn() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "pare_gitgroup_\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let repo = tmp.appending(path: "repo")
        let nested = repo.appending(path: "nested")
        for dir in [repo.appending(path: ".git"), nested.appending(path: ".git"), repo.appending(path: "a/build"),
                    repo.appending(path: "b/c/build"), nested.appending(path: "build")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let recorder = ArgumentRecorder()
        let inspector = SystemGitArtifactInspector(
            locateGit: { [git] in git },
            run: { [repo = repo.path, nested = nested.path] _, arguments, _ in
                recorder.record(arguments)
                let directory = arguments[arguments.firstIndex(of: "-C")! + 1]
                if arguments.contains("rev-parse") {
                    let top = directory.hasPrefix(nested) ? nested : repo
                    let prefix = directory == top ? "" : String(directory.dropFirst(top.count + 1)) + "/"
                    return (exitCode: 0, stdout: Data("\(top)\n\(prefix)\n".utf8))
                }
                if arguments.contains("check-ignore") {
                    let paths = arguments.drop { $0 != "--" }.dropFirst()
                    return (exitCode: 0, stdout: Data(paths.joined(separator: "\n").utf8))
                }
                return (exitCode: 0, stdout: Data())
            }
        )
        let dirs = [repo.appending(path: "a/build"), repo.appending(path: "b/c/build"), nested.appending(path: "build")]
            .map { URL(fileURLWithPath: $0.path) }

        let statuses = await inspector.statuses(for: dirs)

        XCTAssertEqual(recorder.calls.filter { $0.contains("rev-parse") }.count, 2)
        XCTAssertEqual(Set(dirs.map { statuses[$0.path] }), [.ignoredUntracked])
        let repoCheck = recorder.calls.first { $0.contains("check-ignore") && $0.contains(repo.path) }
        XCTAssertEqual(repoCheck.map { Set($0.drop { $0 != "--" }.dropFirst()) }, ["a/build", "b/c/build"])
    }
}

/// A clock that only moves when told to.
private final class GitClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)

    var now: @Sendable () -> Date {
        { [self] in lock.withLock { current } }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

private final class ArgumentRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []

    var calls: [[String]] { lock.withLock { recorded } }

    func record(_ arguments: [String]) {
        lock.withLock { recorded.append(arguments) }
    }
}
