import Foundation

/// Last complete size of each Go module cache, reused while its top two levels are unchanged.
/// Sizing `~/go/pkg/mod` walks hundreds of thousands of entries for a report-only finding.
public final class GoModuleCacheSizeStore: @unchecked Sendable {
    public static let shared = GoModuleCacheSizeStore()
    /// A stored size is measured again after this long, even when the fingerprint still matches.
    public static let maxAge: TimeInterval = 24 * 3600

    struct Entry: Codable, Equatable {
        let bytes: Int64
        let measuredAt: Date
        /// Relative path → modification time (seconds since 1970) of the root and its top two levels.
        let fingerprint: [String: Double]
    }

    private let storeURL: URL
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var entries: [String: Entry]?

    public init(storeURL: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.storeURL = storeURL ?? Self.defaultURL()
        self.now = now
    }

    /// The stored size when it is younger than `maxAge` and the cache's shape has not changed since.
    public func size(for root: URL) -> Int64? {
        let key = root.standardizedFileURL.path
        guard let entry = lock.withLock({ loadedEntries()[key] }) else { return nil }
        let age = now().timeIntervalSince(entry.measuredAt)
        guard age >= 0, age < Self.maxAge, entry.fingerprint == Self.fingerprint(of: root) else { return nil }
        return entry.bytes
    }

    /// Records a complete size measured just now.
    public func remember(_ bytes: Int64, for root: URL) {
        let key = root.standardizedFileURL.path
        let entry = Entry(bytes: bytes, measuredAt: now(), fingerprint: Self.fingerprint(of: root))
        let snapshot: [String: Entry] = lock.withLock {
            var updated = loadedEntries()
            updated[key] = entry
            entries = updated
            return updated
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // A failed write only costs a full re-measure on the next scan.
            NSLog("Pare: could not persist Go module cache size: \(error.localizedDescription)")
        }
    }

    /// New modules add or touch directories in the first two levels (`github.com/<org>`, `cache/download`).
    static func fingerprint(of root: URL) -> [String: Double] {
        var result: [String: Double] = [:]
        var pending: [(url: URL, relative: String, depth: Int)] = [(root, ".", 0)]
        while let next = pending.popLast() {
            let values = try? next.url.resourceValues(forKeys: [.contentModificationDateKey])
            result[next.relative] = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            guard next.depth < 2 else { continue }
            for child in subdirectories(of: next.url) {
                let relative = next.relative == "." ? child.lastPathComponent : next.relative + "/" + child.lastPathComponent
                pending.append((child, relative, next.depth + 1))
            }
        }
        return result
    }

    private static func subdirectories(of url: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let entries = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
        return entries.filter { entry in
            let values = try? entry.resourceValues(forKeys: Set(keys))
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
    }

    /// Call with `lock` held.
    private func loadedEntries() -> [String: Entry] {
        if let entries { return entries }
        let loaded = (try? Data(contentsOf: storeURL)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) }
        entries = loaded ?? [:]
        return entries ?? [:]
    }

    private static func defaultURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Pare/go-module-cache-size.json")
    }
}
