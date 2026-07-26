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
    /// `true` when the manifest has mutations not yet flushed to disk.
    private var isDirty = false
    /// Incremented on every manifest mutation. Lets `flush()` detect writes that
    /// raced with new mutations (actor reentrancy) and keep the dirty flag set.
    private var generation: UInt64 = 0

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
        markDirty()
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

    /// Records the traversal result in memory and marks the manifest dirty.
    /// The mtime index reaches disk on the next `flush()` — call sites on the
    /// scan hot path no longer pay a full manifest rewrite per directory.
    public func store(directory: URL, mtime: Date, files: [ScannedFile]) {
        manifest.entries[directory.path] = mtime
        fileCache[directory.path] = files
        markDirty()
    }

    /// Clears all cached state — next scan will be a full traversal.
    public func invalidate() {
        manifest = Manifest()
        fileCache = [:]
        markDirty()
    }

    // MARK: - Persistence

    static func defaultURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Pare/scan-cache.json")
    }

    private func markDirty() {
        isDirty = true
        generation &+= 1
    }

    /// Writes the manifest to disk once, if anything changed since the last flush.
    ///
    /// Called by `ScanRunner` at the end of each scan (previously every `store`
    /// rewrote the full manifest — O(N²) bytes per scan). The file write runs on
    /// a detached task so the actor stays responsive to `isFresh`/`store` calls.
    public func flush() async {
        guard isDirty else { return }
        guard let data = try? JSONEncoder().encode(manifest) else { return }

        let url = persistURL
        let generationAtEncode = generation
        let wrote = await Task.detached(priority: .utility) { () -> Bool in
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }.value

        // Only clear the dirty flag when the write succeeded AND no mutation
        // arrived while the actor was suspended on the detached write.
        if wrote && generation == generationAtEncode {
            isDirty = false
        }
    }
}
