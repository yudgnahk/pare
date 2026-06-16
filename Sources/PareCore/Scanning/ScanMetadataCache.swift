import Foundation

/// Incremental scan cache. Persists a directory → mtime index so that directories whose
/// contents haven't changed since the last scan can be skipped on subsequent runs.
///
/// File results are held **in-memory only**. The persisted mtime index is used solely to
/// detect whether a directory has changed; if the app restarts the traversal reruns but
/// immediately repopulates the in-memory cache for the session.
public actor ScanMetadataCache {

    // MARK: - Persisted manifest

    private struct Manifest: Codable {
        var profileFingerprint: String
        var entries: [String: Date]

        init(profileFingerprint: String = "", entries: [String: Date] = [:]) {
            self.profileFingerprint = profileFingerprint
            self.entries = entries
        }
    }

    // MARK: - State

    private var manifest: Manifest
    private var fileCache: [String: [ScannedFile]] = [:]
    private let persistURL: URL

    // MARK: - Init

    public init(persistURL: URL? = nil) {
        let url = persistURL ?? ScanMetadataCache.defaultURL()
        self.persistURL = url

        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(Manifest.self, from: data) {
            self.manifest = loaded
        } else {
            self.manifest = Manifest()
        }
    }

    // MARK: - Profile

    /// Call before each scan. Clears all cached data when the profile changes.
    public func setProfile(_ fingerprint: String) {
        guard manifest.profileFingerprint != fingerprint else { return }
        manifest = Manifest(profileFingerprint: fingerprint)
        fileCache = [:]
        save()
    }

    // MARK: - Cache API

    /// Returns `true` when the directory's mtime matches what was stored on the last scan.
    public func isFresh(directory: URL, currentMtime: Date) -> Bool {
        guard let stored = manifest.entries[directory.path] else { return false }
        return stored == currentMtime
    }

    /// Returns previously collected files for this directory, or `nil` if the in-memory
    /// cache is empty (cold start, profile change, or forced invalidation).
    public func cachedFiles(for directory: URL) -> [ScannedFile]? {
        fileCache[directory.path]
    }

    /// Records the traversal result and persists the mtime.
    public func store(directory: URL, mtime: Date, files: [ScannedFile]) {
        manifest.entries[directory.path] = mtime
        fileCache[directory.path] = files
        save()
    }

    /// Clears all cached state — next scan will be a full traversal.
    public func invalidate() {
        manifest = Manifest()
        fileCache = [:]
        save()
    }

    // MARK: - Persistence

    static func defaultURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("App B/scan-cache.json")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        let dir = persistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: persistURL)
    }
}
