import Foundation

public enum MaintenanceError: Error, LocalizedError {
    case unknownAction(String)
    case executableNotFound(String)
    case nonZeroExit(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .unknownAction(let id):
            return "Unknown maintenance action: \(id)"
        case .executableNotFound(let path):
            return "Executable not found: \(path)"
        case .nonZeroExit(let code, let stderr):
            return stderr.isEmpty
                ? "Process exited with code \(code)"
                : "Process exited with code \(code): \(stderr)"
        }
    }
}

/// Executes maintenance actions and streams output lines as they arrive.
/// Subprocess execution goes through an injected `ProcessRunning` seam
/// (real `SystemProcessRunner` by default; tests inject a stub).
public struct MaintenanceRunner: Sendable {
    public static let shared = MaintenanceRunner()

    private let processRunner: any ProcessRunning
    private let homeDirectory: URL
    private let freeSpace: any FreeSpaceProviding
    private let runningApps: any RunningAppChecking

    public init(
        processRunner: any ProcessRunning = SystemProcessRunner(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        freeSpace: any FreeSpaceProviding = StatfsFreeSpace(),
        runningApps: any RunningAppChecking = WorkspaceRunningApps()
    ) {
        self.processRunner = processRunner
        self.homeDirectory = homeDirectory
        self.freeSpace = freeSpace
        self.runningApps = runningApps
    }

    // MARK: - Docker availability

    public var dockerExecutable: String? {
        ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Returns `true` when the Docker daemon is reachable (`docker info` exit 0).
    public func isDockerRunning() async -> Bool {
        guard let docker = dockerExecutable else { return false }
        let result = try? await processRunner.run(
            executablePath: docker,
            arguments: ["info"],
            environment: nil
        )
        return result?.exitCode == 0
    }

    // MARK: - Dispatch

    public func run(action: MaintenanceAction) -> AsyncThrowingStream<String, Error> {
        switch action.id {
        case MaintenanceCatalog.flushDNS.id:
            return runFlushDNS()
        case MaintenanceCatalog.restartFinder.id:
            return runRestartFinder()
        case MaintenanceCatalog.vacuumDatabases.id:
            return runVacuumDatabases()
        case MaintenanceCatalog.dockerPrune.id:
            return runDockerPrune()
        case MaintenanceCatalog.dockerBuilderPrune7d.id:
            return runDockerBuilderPrune(untilHours: 168, label: "7 days")
        case MaintenanceCatalog.dockerBuilderPrune1d.id:
            return runDockerBuilderPrune(untilHours: 24, label: "1 day")
        default:
            return AsyncThrowingStream { $0.finish(throwing: MaintenanceError.unknownAction(action.id)) }
        }
    }

    // MARK: - Action implementations

    private func runFlushDNS() -> AsyncThrowingStream<String, Error> {
        sequence([
            Step(label: "Flushing DNS cache…",
                 executable: "/usr/bin/dscacheutil", args: ["-flushcache"]),
            Step(label: "Restarting mDNSResponder…",
                 executable: "/usr/bin/killall", args: ["-HUP", "mDNSResponder"]),
        ], doneMessage: "DNS cache flushed successfully.")
    }

    private func runRestartFinder() -> AsyncThrowingStream<String, Error> {
        sequence([
            Step(label: "Restarting Finder…",
                 executable: "/usr/bin/killall", args: ["Finder"]),
        ], doneMessage: "Finder restarted. It will relaunch automatically.")
    }

    private func runVacuumDatabases() -> AsyncThrowingStream<String, Error> {
        let vacuum = SQLiteVacuumRunner(processRunner: processRunner, freeSpace: freeSpace, runningApps: runningApps)
        let targets = Self.vacuumTargets(homeDirectory: homeDirectory)
        return AsyncThrowingStream { continuation in
            Task {
                let sqlite3 = SQLiteVacuumRunner.defaultSQLite3Path
                guard FileManager.default.fileExists(atPath: sqlite3) else {
                    continuation.finish(throwing: MaintenanceError.executableNotFound(sqlite3))
                    return
                }
                guard !targets.isEmpty else {
                    continuation.yield("No databases found.")
                    continuation.finish()
                    return
                }
                await vacuum.vacuum(targets) { continuation.yield($0) }
                continuation.yield("Vacuum complete.")
                continuation.finish()
            }
        }
    }

    /// Mail's envelope index (any `V*` version) and Safari history. Messages' `chat.db` is never
    /// included: a system daemon keeps it open even when Messages is quit.
    static func vacuumTargets(homeDirectory home: URL) -> [SQLiteVacuumTarget] {
        var targets: [SQLiteVacuumTarget] = []
        let mailBase = home.appending(path: "Library/Mail")
        let versionDirs = (try? FileManager.default.contentsOfDirectory(
            at: mailBase,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for versionDir in versionDirs.sorted(by: { $0.path < $1.path }) where versionDir.lastPathComponent.hasPrefix("V") {
            let envelope = versionDir.appending(path: "MailData/Envelope Index")
            if FileManager.default.fileExists(atPath: envelope.path) {
                targets.append(SQLiteVacuumTarget(
                    label: "Mail Envelope Index",
                    path: envelope.path,
                    ownerBundleIdentifier: "com.apple.mail",
                    ownerName: "Mail"
                ))
            }
        }
        let safariHistory = home.appending(path: "Library/Safari/History.db")
        if FileManager.default.fileExists(atPath: safariHistory.path) {
            targets.append(SQLiteVacuumTarget(
                label: "Safari History",
                path: safariHistory.path,
                ownerBundleIdentifier: "com.apple.Safari",
                ownerName: "Safari"
            ))
        }
        return targets
    }

    /// Docker prune arguments. **Must never include `--volumes`** — volumes hold user
    /// databases and app data. Do not add volume flags here.
    static let dockerSystemPruneArguments: [String] = ["system", "prune", "-f"]

    /// Age-filtered build-cache prune args. `untilHours`: 168 (7d default) or 24 (low disk).
    static func dockerBuilderPruneArguments(untilHours: Int) -> [String] {
        ["builder", "prune", "-f", "--filter", "until=\(untilHours)h"]
    }

    private func runDockerPrune() -> AsyncThrowingStream<String, Error> {
        guard let docker = dockerExecutable else {
            return AsyncThrowingStream { $0.finish(throwing: MaintenanceError.executableNotFound("docker")) }
        }
        // Belt-and-suspenders: refuse if args ever gain a volumes flag.
        let args = Self.dockerSystemPruneArguments
        precondition(
            !args.contains(where: { $0 == "--volumes" || $0 == "-v" }),
            "Docker prune must never pass --volumes"
        )
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield("→ Running docker system prune -f (volumes NOT removed)…")
                continuation.yield("  Note: only unused Docker objects; named volumes are preserved.")
                let stream = shellStream(docker, args)
                do {
                    for try await line in stream {
                        continuation.yield(line)
                    }
                    continuation.yield("Docker prune complete (volumes preserved).")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Age-filtered build-cache prune. Prefer 168h (7d); use 24h when disk is low.
    /// Never touches named volumes or the Docker.raw VM disk.
    private func runDockerBuilderPrune(untilHours: Int, label: String) -> AsyncThrowingStream<String, Error> {
        guard let docker = dockerExecutable else {
            return AsyncThrowingStream { $0.finish(throwing: MaintenanceError.executableNotFound("docker")) }
        }
        let args = Self.dockerBuilderPruneArguments(untilHours: untilHours)
        let filter = "until=\(untilHours)h"
        precondition(
            !args.contains(where: { $0 == "--volumes" || $0 == "-v" }),
            "Docker builder prune must never pass --volumes"
        )
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield("→ Running docker builder prune -f --filter \(filter)…")
                continuation.yield("  Removes image build cache older than \(label). Volumes and Docker.raw are not touched.")
                let stream = shellStream(docker, args)
                do {
                    for try await line in stream {
                        continuation.yield(line)
                    }
                    continuation.yield("Docker build-cache prune complete (>\(label) removed).")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private helpers

    private struct Step {
        let label: String
        let executable: String
        let args: [String]
    }

    /// Runs a sequence of shell steps, yielding the step label before each,
    /// then a final done message. Any step failure aborts the sequence.
    private func sequence(
        _ steps: [Step],
        doneMessage: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for step in steps {
                    continuation.yield("→ \(step.label)")
                    let stream = shellStream(step.executable, step.args)
                    do {
                        for try await line in stream where !line.isEmpty {
                            continuation.yield(line)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.yield("✓ \(doneMessage)")
                continuation.finish()
            }
        }
    }

    /// Runs an executable and streams stdout lines through the injected runner.
    /// stderr is collected by the runner and surfaced on a non-zero exit.
    private func shellStream(_ executable: String, _ args: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let lines = processRunner.streamLines(
                        executablePath: executable,
                        arguments: args,
                        environment: nil
                    )
                    for try await line in lines {
                        if case .stdout(let text) = line {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch let error as ProcessRunnerError {
                    switch error {
                    case .executableNotFound(let path):
                        continuation.finish(throwing: MaintenanceError.executableNotFound(path))
                    case .nonZeroExit(let code, let stderr):
                        continuation.finish(throwing: MaintenanceError.nonZeroExit(code, stderr))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
