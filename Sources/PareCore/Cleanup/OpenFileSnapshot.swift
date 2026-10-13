import Foundation

/// Open files from one `lsof -F pcn` run, indexed by canonical path and every ancestor directory,
/// so "is anything open at or under this finding" is one dictionary lookup.
public struct OpenFileSnapshot: Sendable {
    /// Canonical, lowercased path → "command (pid N)" of the first process seen holding it.
    private let holders: [String: String]

    /// Parses `-F` field output: `p` starts a process, `c` names it, `n` is an open file's name.
    public init(lsofFieldOutput: String) {
        var holders: [String: String] = [:]
        var pid = ""
        var command = ""
        for line in lsofFieldOutput.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = value
                command = ""
            case "c":
                command = value
            case "n" where value.hasPrefix("/"):
                let holder = "\(command.isEmpty ? "process" : command) (pid \(pid))"
                // Ancestors of an indexed key are already indexed, so stop at the first hit.
                for key in Self.selfAndAncestors(ScanPolicy.canonicalPathKey(value)) {
                    guard holders[key] == nil else { break }
                    holders[key] = holder
                }
            default:
                continue
            }
        }
        self.holders = holders
    }

    /// True when the output has at least one `p<pid>` record; anything else is not a usable listing.
    static func isRecognizedFieldOutput(_ output: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { line in
            line.first == "p" && line.count > 1 && line.dropFirst().allSatisfy(\.isNumber)
        }
    }

    /// The process holding a file at `path` or anywhere beneath it.
    public func holder(atOrUnder path: String) -> String? {
        holders[ScanPolicy.canonicalPathKey(path)]
    }

    /// `/a/b/c` → `/a/b/c`, `/a/b`, `/a`; the root itself is never a key.
    private static func selfAndAncestors(_ path: String) -> [String] {
        var keys: [String] = []
        var current = Substring(path)
        while current.count > 1 {
            keys.append(String(current))
            guard let slash = current.lastIndex(of: "/") else { break }
            current = current[..<slash]
        }
        return keys
    }
}

/// Takes a snapshot of every open file; nil when the snapshot is unavailable.
public protocol OpenFileSnapshotProviding: Sendable {
    func snapshot() async -> OpenFileSnapshot?
}

/// One global `lsof` run per cleanup batch: `+D` per finding is far slower on large trees.
public struct LsofOpenFileSnapshotProvider: OpenFileSnapshotProviding {
    static let lsofPath = "/usr/sbin/lsof"
    /// A full listing takes about a second; past this the snapshot counts as unavailable.
    public static let defaultTimeoutSeconds: TimeInterval = 10

    private let runner: ToolCommandRunner
    private let executable: URL

    public init(timeoutSeconds: TimeInterval = LsofOpenFileSnapshotProvider.defaultTimeoutSeconds) {
        self.init(executable: URL(fileURLWithPath: Self.lsofPath), timeoutSeconds: timeoutSeconds)
    }

    /// Tests point `executable` at a script that times out, fails or prints garbage.
    init(executable: URL, timeoutSeconds: TimeInterval) {
        self.executable = executable
        runner = ToolCommandRunner(timeoutSeconds: timeoutSeconds)
    }

    public func snapshot() async -> OpenFileSnapshot? {
        // -n/-P skip DNS and port lookups, -w drops warnings for processes we cannot inspect.
        guard let output = await runner.capture(executable: executable, arguments: ["-n", "-P", "-w", "-Fpcn"]),
              // Output without a single process record would read as "nothing is open" and fail open everywhere.
              OpenFileSnapshot.isRecognizedFieldOutput(output) else { return nil }
        return OpenFileSnapshot(lsofFieldOutput: output)
    }
}
