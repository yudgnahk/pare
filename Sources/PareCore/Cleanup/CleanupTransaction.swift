import Foundation

// MARK: - CleanupItem

/// One file that was moved to Trash (or would be, in dry-run mode).
public struct CleanupItem: Codable, Sendable {
    /// Original absolute path before the move.
    public let originalPath: String
    /// Absolute path inside the Trash after the move. Nil for dry-run items.
    public let trashedPath: String?
    /// File size at the time of cleanup.
    public let sizeBytes: Int64
    /// Human-readable reason the file was flagged (from the matching `ScanRule`).
    public let reason: String
    /// Risk level at the time of cleanup.
    public let riskLevelRaw: String

    public var riskLevel: RiskLevel {
        RiskLevel(rawValue: riskLevelRaw) ?? .safe
    }

    public init(originalPath: String, trashedPath: String?, sizeBytes: Int64, reason: String, riskLevel: RiskLevel) {
        self.originalPath = originalPath
        self.trashedPath = trashedPath
        self.sizeBytes = sizeBytes
        self.reason = reason
        self.riskLevelRaw = riskLevel.rawValue
    }
}

// MARK: - CleanupTransaction

/// A timestamped record of a single cleanup operation (one or more files moved to Trash).
public struct CleanupTransaction: Codable, Sendable, Identifiable {
    public let id: UUID
    /// ISO-8601 timestamp when the cleanup ran.
    public let timestamp: Date
    /// Profile name used for the scan that produced these findings.
    public let profileName: String
    /// Whether this was a dry-run (no actual files were moved).
    public let isDryRun: Bool
    /// All items included in this transaction.
    public let items: [CleanupItem]

    public var totalBytesFreed: Int64 {
        isDryRun ? 0 : items.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalBytesCandidates: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        profileName: String,
        isDryRun: Bool,
        items: [CleanupItem]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.profileName = profileName
        self.isDryRun = isDryRun
        self.items = items
    }
}

// MARK: - CleanupTransactionStore

/// Persists and retrieves `CleanupTransaction` records as JSON files under
/// `~/Library/Application Support/Pare/transactions/`.
public final class CleanupTransactionStore: Sendable {
    public static let shared = CleanupTransactionStore()

    private let transactionsDirectory: URL

    public init(directory: URL? = nil) {
        if let directory {
            transactionsDirectory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            transactionsDirectory = appSupport
                .appending(path: "Pare")
                .appending(path: "transactions")
        }
    }

    // MARK: Write

    public func save(_ transaction: CleanupTransaction) throws {
        try FileManager.default.createDirectory(at: transactionsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(transaction)
        let file = transactionsDirectory.appending(path: "\(transaction.id.uuidString).json")
        try data.write(to: file, options: .atomicWrite)
    }

    // MARK: Read

    public func loadAll() throws -> [CleanupTransaction] {
        guard FileManager.default.fileExists(atPath: transactionsDirectory.path) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = try FileManager.default.contentsOfDirectory(
            at: transactionsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(CleanupTransaction.self, from: data)
        }.sorted { $0.timestamp > $1.timestamp }
    }

    /// Removes a single transaction record (no-op when absent).
    public func delete(id: UUID) throws {
        let file = transactionsDirectory.appending(path: "\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: transactionsDirectory.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(
            at: transactionsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }

    public func load(id: UUID) throws -> CleanupTransaction? {
        let file = transactionsDirectory.appending(path: "\(id.uuidString).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CleanupTransaction.self, from: data)
    }
}
