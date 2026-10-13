import Foundation

/// Looks up Paseo agent sessions by id; any missing or malformed file just means "not a Paseo agent".
public struct PaseoAgentResolver: Sendable {
    /// Session files are a few KB; anything far larger is not one and is skipped unread.
    public static let maxFileBytes = 256 * 1024
    static let maxSlugDirectories = 2000
    static let missRetrySeconds: TimeInterval = 30

    public static var defaultAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".paseo/agents", isDirectory: true)
    }

    private struct Entry: Sendable {
        let url: URL
        let modified: Date
        let info: PaseoAgentInfo
    }

    private let agentsDirectory: URL
    private let now: @Sendable () -> Date
    private var entries: [UUID: Entry] = [:]
    private var misses: [UUID: Date] = [:]

    public init(agentsDirectory: URL = PaseoAgentResolver.defaultAgentsDirectory, now: @escaping @Sendable () -> Date = { Date() }) {
        self.agentsDirectory = agentsDirectory
        self.now = now
    }

    public mutating func resolve(_ id: UUID) -> PaseoAgentInfo? {
        if let missedAt = misses[id], now().timeIntervalSince(missedAt) < Self.missRetrySeconds { return nil }
        guard let url = entries[id]?.url ?? locate(id), let info = load(id, at: url) else {
            entries[id] = nil
            misses[id] = now()
            return nil
        }
        misses[id] = nil
        return info
    }

    /// Drops cached sessions whose processes have exited.
    public mutating func retain(only ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
        misses = misses.filter { ids.contains($0.key) }
    }

    private func locate(_ id: UUID) -> URL? {
        let fileName = id.uuidString.lowercased() + ".json"
        guard let slugs = try? FileManager.default.contentsOfDirectory(
            at: agentsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for slug in slugs.prefix(Self.maxSlugDirectories) {
            let candidate = slug.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private mutating func load(_ id: UUID, at url: URL) -> PaseoAgentInfo? {
        // attributesOfItem does not follow symlinks, so a linked file reads as non-regular and is skipped.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= Self.maxFileBytes
        else { return nil }
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        if let cached = entries[id], cached.url == url, cached.modified == modified { return cached.info }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SessionFile.self, from: data)
        else { return nil }
        let info = PaseoAgentInfo(
            title: file.title,
            cwd: file.cwd,
            lastStatus: file.lastStatus,
            lastUserMessageAt: file.lastUserMessageAt.flatMap(Self.parseDate)
        )
        entries[id] = Entry(url: url, modified: modified, info: info)
        return info
    }

    private struct SessionFile: Decodable {
        let title: String?
        let cwd: String?
        let lastStatus: String?
        let lastUserMessageAt: String?
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
