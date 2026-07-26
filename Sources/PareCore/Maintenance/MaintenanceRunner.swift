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

/// Executes maintenance actions and streams output lines as they arrive
/// via the shared `ProcessStreamer`.
public struct MaintenanceRunner: Sendable {
    public static let shared = MaintenanceRunner()
    public init() {}

    // MARK: - Docker availability

    public var dockerExecutable: String? {
        ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Returns `true` when the Docker daemon is reachable (`docker info` exit 0).
    public func isDockerRunning() async -> Bool {
        guard let docker = dockerExecutable else { return false }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: docker)
            process.arguments = ["info"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus == 0)
            }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }

    // MARK: - Dispatch

    public func run(action: MaintenanceAction) -> AsyncThrowingStream<String, Error> {
        switch action.id {
        case MaintenanceCatalog.flushDNS.id:
            return runFlushDNS()
        case MaintenanceCatalog.rebuildLaunchServices.id:
            return runRebuildLaunchServices()
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

    private func runRebuildLaunchServices() -> AsyncThrowingStream<String, Error> {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework" +
            "/Versions/A/Frameworks/LaunchServices.framework" +
            "/Versions/A/Support/lsregister"
        return sequence([
            Step(label: "Rebuilding Launch Services database…",
                 executable: lsregister,
                 args: ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"]),
        ], doneMessage: "Launch Services database rebuilt.")
    }

    private func runRestartFinder() -> AsyncThrowingStream<String, Error> {
        sequence([
            Step(label: "Restarting Finder…",
                 executable: "/usr/bin/killall", args: ["Finder"]),
        ], doneMessage: "Finder restarted. It will relaunch automatically.")
    }

    private func runVacuumDatabases() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let sqlite3 = "/usr/bin/sqlite3"
                guard FileManager.default.fileExists(atPath: sqlite3) else {
                    continuation.finish(throwing: MaintenanceError.executableNotFound(sqlite3))
                    return
                }

                var dbPaths: [(String, String)] = []

                // Mail — version directory varies (V9, V10, …)
                let mailBase = home.appending(path: "Library/Mail")
                if let vDirs = try? FileManager.default.contentsOfDirectory(
                    at: mailBase,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for vDir in vDirs where vDir.lastPathComponent.hasPrefix("V") {
                        let envelope = vDir.appending(path: "MailData/Envelope Index")
                        if FileManager.default.fileExists(atPath: envelope.path) {
                            dbPaths.append(("Mail Envelope Index", envelope.path))
                        }
                    }
                }

                // Safari
                let safariHistory = home.appending(path: "Library/Safari/History.db")
                if FileManager.default.fileExists(atPath: safariHistory.path) {
                    dbPaths.append(("Safari History", safariHistory.path))
                }

                // Messages
                let messages = home.appending(path: "Library/Messages/chat.db")
                if FileManager.default.fileExists(atPath: messages.path) {
                    dbPaths.append(("Messages", messages.path))
                }

                if dbPaths.isEmpty {
                    continuation.yield("No databases found.")
                    continuation.finish()
                    return
                }

                for (label, path) in dbPaths {
                    continuation.yield("→ Vacuuming \(label)…")
                    let stream = shellStream(sqlite3, [path, "VACUUM"])
                    do {
                        for try await line in stream where !line.isEmpty {
                            continuation.yield(line)
                        }
                        continuation.yield("  ✓ \(label) done.")
                    } catch let err as MaintenanceError {
                        // sqlite3 VACUUM on a locked db exits non-zero; treat as warning
                        continuation.yield("  ⚠ \(label): \(err.localizedDescription)")
                    }
                }

                continuation.yield("Vacuum complete.")
                continuation.finish()
            }
        }
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

    /// Runs an executable and streams stdout lines via the shared `ProcessStreamer`.
    /// stderr is captured and surfaced through `MaintenanceError.nonZeroExit`.
    private func shellStream(_ executable: String, _ args: [String]) -> AsyncThrowingStream<String, Error> {
        guard FileManager.default.fileExists(atPath: executable) else {
            return AsyncThrowingStream {
                $0.finish(throwing: MaintenanceError.executableNotFound(executable))
            }
        }
        return ProcessStreamer.stream(
            executable: URL(fileURLWithPath: executable),
            arguments: args,
            yieldsStderr: false,
            makeExitError: { code, stderr in
                MaintenanceError.nonZeroExit(code, stderr)
            }
        )
    }
}
