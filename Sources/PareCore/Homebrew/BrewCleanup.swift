import Foundation

/// One path `brew cleanup -n` says it would remove.
public struct BrewCleanupItem: Sendable, Equatable {
    public let path: String
    public let fileCount: Int?
    public let bytes: Int64
}

/// What `brew cleanup` would remove, parsed from `brew cleanup -n`. Unknown lines are ignored.
public struct BrewCleanupPreview: Sendable, Equatable {
    public let items: [BrewCleanupItem]
    /// Homebrew's own "would free approximately X" figure, when it prints one.
    public let reportedTotalBytes: Int64?

    public var totalBytes: Int64 { reportedTotalBytes ?? items.reduce(0) { $0 + $1.bytes } }
    public var isEmpty: Bool { items.isEmpty }

    /// Parses `Would remove: <path> (<N files, >size)` lines and the `would free approximately <size>` summary.
    public static func parse(_ output: String) -> BrewCleanupPreview {
        var items: [BrewCleanupItem] = []
        var reported: Int64?
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let item = item(from: line) {
                items.append(item)
            } else if let range = line.range(of: "would free approximately ") {
                let token = line[range.upperBound...].prefix { !$0.isWhitespace }
                reported = bytes(fromHomebrewSize: String(token)) ?? reported
            }
        }
        return BrewCleanupPreview(items: items, reportedTotalBytes: reported)
    }

    private static func item(from line: String) -> BrewCleanupItem? {
        let prefix = "Would remove: "
        guard line.hasPrefix(prefix), line.hasSuffix(")"),
              let open = line.range(of: " (", options: .backwards) else { return nil }
        let path = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<open.lowerBound])
        let details = line[open.upperBound..<line.index(before: line.endIndex)]
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard path.hasPrefix("/"), let sizeToken = details.last, let size = bytes(fromHomebrewSize: sizeToken) else { return nil }
        // "1,234 files, 60.1MB" splits on the thousands comma too; the count is everything before the size.
        let countText = details.dropLast().joined().replacingOccurrences(of: " files", with: "")
            .replacingOccurrences(of: " file", with: "")
        return BrewCleanupItem(path: path, fileCount: Int(countText), bytes: size)
    }

    /// Homebrew's `disk_usage_readable` sizes: `64B`, `1.2KB`, `60.1MB`, `1.2GB`, `1TB` (powers of 1024).
    static func bytes(fromHomebrewSize token: String) -> Int64? {
        let units: [(suffix: String, multiplier: Double)] = [
            ("TB", 1_099_511_627_776), ("GB", 1_073_741_824), ("MB", 1_048_576), ("KB", 1024), ("B", 1),
        ]
        for unit in units where token.hasSuffix(unit.suffix) {
            guard let value = Double(token.dropLast(unit.suffix.count)), value >= 0 else { return nil }
            return Int64(value * unit.multiplier)
        }
        return nil
    }
}

public enum BrewCleanupError: Error, LocalizedError, Equatable {
    case notConfirmed
    case nothingToClean
    case timedOut(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case .notConfirmed: return "Homebrew cleanup needs confirmation first."
        case .nothingToClean: return "Homebrew has nothing to clean up."
        case .timedOut(let seconds): return "Homebrew did not finish within \(seconds) seconds and was stopped."
        }
    }
}

/// Previews and runs `brew cleanup` with Homebrew's default download age; never `--prune=all`, never sudo.
public struct BrewCleanupAction: Sendable {
    public static let previewArguments = ["cleanup", "-n"]
    public static let cleanupArguments = ["cleanup"]
    /// A preview stuck on Homebrew's lock or a dead network mount is stopped after this.
    public static let defaultPreviewTimeoutSeconds: TimeInterval = 120
    public static let defaultCleanupTimeoutSeconds: TimeInterval = 600

    private let runner: BrewRunner
    private let previewTimeoutSeconds: TimeInterval
    private let cleanupTimeoutSeconds: TimeInterval

    public init(
        runner: BrewRunner = .shared,
        previewTimeoutSeconds: TimeInterval = BrewCleanupAction.defaultPreviewTimeoutSeconds,
        cleanupTimeoutSeconds: TimeInterval = BrewCleanupAction.defaultCleanupTimeoutSeconds
    ) {
        self.runner = runner
        self.previewTimeoutSeconds = previewTimeoutSeconds
        self.cleanupTimeoutSeconds = cleanupTimeoutSeconds
    }

    public func preview() async throws -> BrewCleanupPreview {
        let runner = runner
        return try await Self.withTimeout(seconds: previewTimeoutSeconds) {
            BrewCleanupPreview.parse(try await runner.run(Self.previewArguments))
        }
    }

    /// Only with explicit confirmation: re-runs the preview, refuses when nothing is left, then streams
    /// `brew cleanup`. Returns the preview it acted on, for the "about X freed" estimate.
    /// Cancelling the calling task or hitting the timeout terminates brew and throws.
    public func run(confirmed: Bool, onLine: @escaping @Sendable (String) -> Void) async throws -> BrewCleanupPreview {
        guard confirmed else { throw BrewCleanupError.notConfirmed }
        let fresh = try await preview()
        guard !fresh.isEmpty else { throw BrewCleanupError.nothingToClean }
        let runner = runner
        try await Self.withTimeout(seconds: cleanupTimeoutSeconds) {
            for try await line in runner.stream(Self.cleanupArguments) {
                onLine(line)
            }
            // A cancelled stream just ends; that is not a finished cleanup.
            try Task.checkCancellation()
        }
        return fresh
    }

    /// Races `operation` against a timer; the loser is cancelled, which terminates a running brew.
    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw BrewCleanupError.timedOut(seconds: Int(seconds.rounded()))
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }
}
