import Foundation

/// Sizes recorded after one scan, so the next scan can say what grew.
/// Per category (findings carry no rule id) and per finding path above `minimumPathBytes`.
public struct GrowthSnapshot: Codable, Sendable, Equatable {
    public let takenAt: Date
    /// `ScanCategory.rawValue` → reclaimable bytes.
    public let perCategory: [String: Int64]
    /// Canonical, lowercased finding path → bytes.
    public let perPath: [String: Int64]

    /// Smaller findings are not tracked per path; they only count in their category.
    public static let minimumPathBytes: Int64 = 100 * 1024 * 1024

    public init(takenAt: Date, perCategory: [String: Int64], perPath: [String: Int64]) {
        self.takenAt = takenAt
        self.perCategory = perCategory
        self.perPath = perPath
    }

    public init(report: ScanReport, takenAt: Date = Date()) {
        var perPath: [String: Int64] = [:]
        for finding in report.findings where finding.sizeBytes >= Self.minimumPathBytes {
            perPath[Self.key(finding.path), default: 0] += finding.sizeBytes
        }
        self.init(
            takenAt: takenAt,
            perCategory: Dictionary(report.summaries.map { ($0.category.rawValue, $0.reclaimableBytes) }, uniquingKeysWith: +),
            perPath: perPath
        )
    }

    /// `/var/…` and `/private/var/…`, and differently cased spellings, land on one key.
    public static func key(_ path: String) -> String {
        ScanPolicy.canonicalPathURL(URL(fileURLWithPath: path)).path.lowercased()
    }
}

/// What grew between two snapshots, largest growth first.
public struct GrowthDelta: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let key: String
        public let grewBy: Int64
        public let currentBytes: Int64
    }

    public let categories: [Entry]
    public let paths: [Entry]

    /// Changes smaller than this are noise between two scans.
    public static let noiseFloorBytes: Int64 = 50 * 1024 * 1024

    public var isEmpty: Bool { categories.isEmpty && paths.isEmpty }

    /// Growth only: shrinkage, changes under the noise floor and keys gone from `current` are ignored;
    /// a key new in `current` grew from zero.
    public static func compute(
        previous: GrowthSnapshot,
        current: GrowthSnapshot,
        noiseFloor: Int64 = GrowthDelta.noiseFloorBytes
    ) -> GrowthDelta {
        GrowthDelta(
            categories: grown(previous.perCategory, current.perCategory, noiseFloor: noiseFloor),
            paths: grown(previous.perPath, current.perPath, noiseFloor: noiseFloor)
        )
    }

    private static func grown(_ before: [String: Int64], _ after: [String: Int64], noiseFloor: Int64) -> [Entry] {
        after
            .compactMap { key, bytes -> Entry? in
                let delta = bytes - (before[key] ?? 0)
                return delta >= noiseFloor ? Entry(key: key, grewBy: delta, currentBytes: bytes) : nil
            }
            .sorted { $0.grewBy != $1.grewBy ? $0.grewBy > $1.grewBy : $0.key < $1.key }
    }
}

/// Keeps the last `retainedCount` snapshots as JSON files in one directory.
public struct GrowthSnapshotStore: Sendable {
    public static let retainedCount = 30

    public static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appending(path: "Pare/growth")
    }

    private let directory: URL
    private let retainedCount: Int

    public init(directory: URL = GrowthSnapshotStore.defaultDirectory, retainedCount: Int = GrowthSnapshotStore.retainedCount) {
        self.directory = directory
        self.retainedCount = retainedCount
    }

    /// Writes atomically, then prunes all but the newest `retainedCount` snapshot files.
    public func save(_ snapshot: GrowthSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let name = String(format: "growth-%013lld.json", Int64(snapshot.takenAt.timeIntervalSince1970 * 1000))
        try encoder.encode(snapshot).write(to: directory.appending(path: name), options: .atomic)
        for stale in snapshotFiles().dropLast(retainedCount) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// The newest readable snapshot; corrupt files are skipped.
    public func latest() -> GrowthSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        for file in snapshotFiles().reversed() {
            if let data = try? Data(contentsOf: file), let snapshot = try? decoder.decode(GrowthSnapshot.self, from: data) {
                return snapshot
            }
        }
        return nil
    }

    /// Snapshot files, oldest first (names sort by time).
    func snapshotFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("growth-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
