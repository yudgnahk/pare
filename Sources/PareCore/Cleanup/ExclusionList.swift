import Foundation

// MARK: - ExclusionEntry

/// A single path exclusion entry.  `prefix` entries match any path that starts with
/// the recorded path (directory exclusion); `exact` entries match only the exact path.
public struct ExclusionEntry: Codable, Sendable, Identifiable {
    public enum MatchType: String, Codable, Sendable {
        case exact
        case prefix
    }

    public let id: UUID
    /// Absolute path to exclude (normalised to lowercase for comparison).
    public let path: String
    public let matchType: MatchType
    /// Optional user-supplied note describing why this path is excluded.
    public let note: String
    /// When the entry was added.
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        path: String,
        matchType: MatchType = .prefix,
        note: String = "",
        addedAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.matchType = matchType
        self.note = note
        self.addedAt = addedAt
    }

    /// Returns true when this entry covers `candidatePath`.
    public func matches(_ candidatePath: String) -> Bool {
        let lhs = path.lowercased()
        let rhs = candidatePath.lowercased()
        switch matchType {
        case .exact:
            return lhs == rhs
        case .prefix:
            return rhs.hasPrefix(lhs)
        }
    }
}

// MARK: - ExclusionList

/// An in-memory set of user-defined path exclusions.
/// Load from / save to disk via `ExclusionStore`.
public struct ExclusionList: Codable, Sendable {
    public private(set) var entries: [ExclusionEntry]

    public init(entries: [ExclusionEntry] = []) {
        self.entries = entries
    }

    /// Returns true when at least one entry matches `path`.
    public func isExcluded(_ path: String) -> Bool {
        entries.contains { $0.matches(path) }
    }

    /// Adds an entry (no-op if an equivalent entry already exists).
    public mutating func add(_ entry: ExclusionEntry) {
        guard !entries.contains(where: { $0.path.lowercased() == entry.path.lowercased() && $0.matchType == entry.matchType }) else {
            return
        }
        entries.append(entry)
    }

    /// Removes all entries whose `id` matches.
    public mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public static var empty: ExclusionList { ExclusionList() }
}

// MARK: - ExclusionStore

/// Persists a single `ExclusionList` as JSON at
/// `~/Library/Application Support/Pare/exclusions.json`.
public final class ExclusionStore: Sendable {
    public static let shared = ExclusionStore()

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = appSupport
                .appending(path: "Pare")
                .appending(path: "exclusions.json")
        }
    }

    // MARK: Read

    public func load() throws -> ExclusionList {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExclusionList.self, from: data)
    }

    // MARK: Write

    public func save(_ list: ExclusionList) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(list)
        try data.write(to: fileURL, options: .atomicWrite)
    }

    // MARK: Convenience mutators

    /// Loads, adds `entry`, and saves.
    public func addEntry(_ entry: ExclusionEntry) throws {
        var list = try load()
        list.add(entry)
        try save(list)
    }

    /// Loads, removes the entry with the given `id`, and saves.
    public func removeEntry(id: UUID) throws {
        var list = try load()
        list.remove(id: id)
        try save(list)
    }
}
