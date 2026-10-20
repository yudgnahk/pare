import Foundation

/// Files deleted while a process still has them open keep their space until that process exits.
/// One `lsof +L1` run, deduplicated by device and inode, summed per holding command. Explain-only:
/// the space comes back by restarting the holder, never by deleting anything.
public struct DeletedOpenFilesRule: ScanRule {
    public let id = "deleted-open-files"
    public let title = "Deleted Files Still Open"
    public let reason = "Deleted files still held open by a running process"
    public let category: ScanCategory = .diagnostics
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.9

    /// Holders keeping less than this are noise (every process maps a few small deleted caches).
    public static let minimumReportedBytes: Int64 = 10 * 1024 * 1024
    static let lsofPath = "/usr/sbin/lsof"
    /// Listing every process takes about a second; past this the detector reports nothing.
    static let timeoutSeconds: TimeInterval = 10

    /// Returns `lsof +L1 -F` output, or nil when lsof is unavailable, failed or timed out.
    public typealias Listing = @Sendable () async -> String?
    /// A process's executable path, or nil when unknown; used to tell macOS processes from apps.
    public typealias ExecutablePath = @Sendable (Int32) -> String?

    private let listing: Listing
    private let executablePath: ExecutablePath

    public init(listing: Listing? = nil, executablePath: @escaping ExecutablePath = ProcessPolicy.executablePath(pid:)) {
        self.executablePath = executablePath
        self.listing = listing ?? {
            await ToolCommandRunner(timeoutSeconds: Self.timeoutSeconds).capture(
                executable: URL(fileURLWithPath: Self.lsofPath),
                arguments: ["+L1", "-n", "-P", "-w", "-FpcDisn"]
            )
        }
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        guard let output = await listing() else { return [] }
        return Self.findings(fromLsofOutput: output, executablePath: executablePath)
    }

    // MARK: - Parsing

    private struct OpenDeletedFile {
        let pid: Int32
        let command: String
        let key: String
        let size: Int64
        let path: String
    }

    private struct Holder {
        var pids = Set<Int32>()
        var bytes: Int64 = 0
        var keys: [String] = []
        var largestPath = ""
        var largestSize: Int64 = -1
    }

    /// One finding per command holding at least `minimumReportedBytes`, largest first.
    /// Each deleted file counts once, for the first command seen holding it.
    static func findings(fromLsofOutput output: String, executablePath: ExecutablePath = { _ in nil }) -> [ScanFinding] {
        let files = parse(output)
        var commandsByKey: [String: Set<String>] = [:]
        for file in files { commandsByKey[file.key, default: []].insert(file.command) }

        var claimed = Set<String>()
        var holders: [String: Holder] = [:]
        var order: [String] = []
        for file in files where claimed.insert(file.key).inserted {
            if holders[file.command] == nil { order.append(file.command) }
            var holder = holders[file.command] ?? Holder()
            holder.bytes += file.size
            holder.pids.insert(file.pid)
            holder.keys.append(file.key)
            if file.size > holder.largestSize {
                holder.largestSize = file.size
                holder.largestPath = file.path
            }
            holders[file.command] = holder
        }

        return order
            .compactMap { command -> (String, Holder)? in
                guard let holder = holders[command], holder.bytes >= minimumReportedBytes else { return nil }
                return (command, holder)
            }
            .sorted { $0.1.bytes > $1.1.bytes }
            .map { command, holder in
                let others = Set(holder.keys.flatMap { commandsByKey[$0] ?? [] }).subtracting([command]).sorted()
                return finding(command: command, holder: holder, otherCommands: others, executablePath: executablePath)
            }
    }

    private static func finding(
        command: String, holder: Holder, otherCommands: [String], executablePath: ExecutablePath
    ) -> ScanFinding {
        let pids = holder.pids.sorted()
        let paths = pids.compactMap(executablePath)
        // An unknown path counts as an app, so the holder is still named and offered.
        let isSystem = !paths.isEmpty && paths.allSatisfy(ProcessPolicy.isSystemExecutable(path:))
        let name = paths.lazy.compactMap(ProcessPolicy.appDisplayName(path:)).first ?? command
        let size = ByteCountFormatter.string(fromByteCount: holder.bytes, countStyle: .file)
        let shared = otherCommands.isEmpty ? "" : " (also held by \(otherCommands.joined(separator: ", ")))"
        let identity = DeletedFilesHolder(command: command, displayName: name, pids: pids, isSystem: isSystem)
        return ScanFinding(
            category: .diagnostics,
            riskLevel: .advanced,
            reason: "\(size) held by deleted files — restart \(name) to reclaim it\(shared)",
            path: holder.largestPath,
            sizeBytes: holder.bytes,
            lastUsed: nil,
            confidence: 0.9,
            annotations: [.explainOnly(action: "Restart \(name) to reclaim the space"), .deletedFilesHolder(identity)]
                + (isSystem ? [] : [.noteAction(.showProcesses(pids: pids))])
        )
    }

    /// `-F` records: `p` starts a process, `c` names it, `f` starts a file with `D` device,
    /// `i` inode, `s` size and `n` name. Files without a size are skipped.
    private static func parse(_ output: String) -> [OpenDeletedFile] {
        var files: [OpenDeletedFile] = []
        var pid: Int32?
        var command: String?
        var device = ""
        var inode = ""
        var size: Int64?
        var name = ""
        var inFile = false

        func flush() {
            defer { inFile = false; device = ""; inode = ""; size = nil; name = "" }
            guard inFile, let pid, let command, let size, name.hasPrefix("/") else { return }
            let key = inode.isEmpty ? "path:\(name)" : "\(device):\(inode)"
            files.append(OpenDeletedFile(pid: pid, command: command, key: key, size: size, path: name))
        }

        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                flush()
                pid = Int32(value)
                command = nil
            case "c":
                command = value
            case "f":
                flush()
                inFile = true
            case "D":
                device = value
            case "i":
                inode = value
            case "s":
                size = Int64(value)
            case "n":
                name = LsofFieldName.unescaped(value)
            default:
                continue
            }
        }
        flush()
        return files
    }
}
