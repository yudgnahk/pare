import Foundation

// MARK: - Row / group models

/// Lightweight folder row for the category browser.
/// **No path lists** — underlying file paths stay private so UI layers never hold 10k+ strings per row.
public struct CategoryFolderRow: Identifiable, Equatable, Sendable {
    public let id: String
    /// Path used for Finder reveal (the rolled-up folder).
    public let folderPath: String
    /// Full user-visible path (`~/…`).
    public let displayPath: String
    public let totalBytes: Int64
    /// Number of underlying scan findings rolled into this folder.
    public let itemCount: Int
    /// Worst risk among members (safe < review < advanced).
    public let riskLevel: RiskLevel
    public let isSelectable: Bool
    /// Tool/app label (same as donut chart) for nested grouping.
    public let toolName: String

    public var isSafeFolder: Bool { riskLevel == .safe }

    public init(
        id: String,
        folderPath: String,
        displayPath: String,
        totalBytes: Int64,
        itemCount: Int,
        riskLevel: RiskLevel,
        isSelectable: Bool,
        toolName: String
    ) {
        self.id = id
        self.folderPath = folderPath
        self.displayPath = displayPath
        self.totalBytes = totalBytes
        self.itemCount = itemCount
        self.riskLevel = riskLevel
        self.isSelectable = isSelectable
        self.toolName = toolName
    }
}

/// Intermediate browser level: category → **tool** (JetBrains, Package Managers, …) → folders.
public struct CategoryToolGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let category: ScanCategory
    public let toolName: String
    public let totalBytes: Int64
    public let folderCount: Int
    public let itemCount: Int
    public let riskLevel: RiskLevel
    /// Folder row ids in this tool group (for bulk select).
    public let folderIds: Set<String>
    public let isSelectable: Bool

    public var isSafeGroup: Bool { riskLevel == .safe }

    public init(
        id: String,
        category: ScanCategory,
        toolName: String,
        totalBytes: Int64,
        folderCount: Int,
        itemCount: Int,
        riskLevel: RiskLevel,
        folderIds: Set<String>,
        isSelectable: Bool
    ) {
        self.id = id
        self.category = category
        self.toolName = toolName
        self.totalBytes = totalBytes
        self.folderCount = folderCount
        self.itemCount = itemCount
        self.riskLevel = riskLevel
        self.folderIds = folderIds
        self.isSelectable = isSelectable
    }
}

/// Precomputed size/count for a folder id (selection metrics without expanding paths).
public struct FolderMeta: Equatable, Sendable {
    public let itemCount: Int
    public let bytes: Int64
    public let reviewCount: Int
    public let isSafe: Bool

    public init(itemCount: Int, bytes: Int64, reviewCount: Int, isSafe: Bool) {
        self.itemCount = itemCount
        self.bytes = bytes
        self.reviewCount = reviewCount
        self.isSafe = isSafe
    }
}

/// Result of rolling findings into folder rows + private path maps.
public struct FolderAggregate: Sendable {
    public var rowsByCategory: [ScanCategory: [CategoryFolderRow]] = [:]
    public var toolGroupsByCategory: [ScanCategory: [CategoryToolGroup]] = [:]
    /// Folder id → finding paths (only used at clean time).
    public var pathsByFolderId: [String: [String]] = [:]
    public var folderIdByPath: [String: String] = [:]
    public var metaByFolderId: [String: FolderMeta] = [:]
    public var safeFolderIds: Set<String> = []
    public var safeFolderIdsByCategory: [ScanCategory: Set<String>] = [:]

    public init() {}
}

/// Per-tool share of reclaimable space (donut chart rows).
public struct ToolRollup: Identifiable, Equatable, Sendable {
    public let id: String
    public let app: String
    public let totalBytes: Int64
    public let fileCount: Int
    public let share: Double

    public init(rollup: AppRollup, total: Int64) {
        self.id = rollup.app
        self.app = rollup.app
        self.totalBytes = rollup.totalBytes
        self.fileCount = rollup.fileCount
        self.share = total > 0 ? Double(rollup.totalBytes) / Double(total) : 0
    }
}

// MARK: - FolderRollup

/// Pure post-scan aggregation: rolls raw findings up into folder rows, tool groups,
/// and per-tool rollups. No UI dependencies — safe to run off the main actor.
public enum FolderRollup {
    /// Hard cap on folder rows rendered per category (largest first).
    /// Higher than before so monorepos (many per-project `.next`/`target`) list as folders, not one root.
    public static let defaultMaxRowsPerCategory = 120

    public static func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home || path.hasPrefix(home.hasSuffix("/") ? home : home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Collapse only **known deep caches** into one row (npm, browser, Library/Caches).
    ///
    /// Project trees are different: a monorepo root like
    /// `/Users/…/Projects/…/akzonobel` is **not** reclaimable as a whole just because
    /// a few child apps have `.next` / `target` / `.cache`. Those claimable folders
    /// must stay separate rows with their full paths — never merge into the monorepo root.
    public static func rollupFolderPath(for path: String) -> String {
        let parts = URL(fileURLWithPath: path).pathComponents.filter { $0 != "/" }
        guard !parts.isEmpty else { return path }

        // Package manager / tool cache roots — one row per root, not per blob.
        let singleSegmentRoots = [
            "_cacache", "_npx", "Yarn", "pnpm", "CocoaPods", "org.swift.swiftpm",
            "pip", "opencode", "Homebrew", "electron", "typescript",
        ]
        for root in singleSegmentRoots {
            if let i = parts.firstIndex(of: root) {
                return "/" + parts[0...i].joined(separator: "/")
            }
        }

        // Cargo / Gradle / Maven trees
        if let i = parts.firstIndex(of: "registry"), i > 0, parts[i - 1] == ".cargo" {
            return "/" + parts[0...i].joined(separator: "/")
        }
        if let i = parts.firstIndex(of: "git"), i > 0, parts[i - 1] == ".cargo" {
            return "/" + parts[0...i].joined(separator: "/")
        }
        if let i = parts.firstIndex(of: "caches"), i > 0, parts[i - 1] == ".gradle" {
            return "/" + parts[0...i].joined(separator: "/")
        }
        if let i = parts.firstIndex(of: "repository"), i > 0, parts[i - 1] == ".m2" {
            return "/" + parts[0...i].joined(separator: "/")
        }

        // ~/Library/Caches/<App> → stop at app name
        if let i = parts.firstIndex(of: "Caches"),
           i > 0, parts[i - 1] == "Library",
           i + 1 < parts.count {
            return "/" + parts[0...(i + 1)].joined(separator: "/")
        }

        // Browser Application Support profile trees — stop at profile (Default, Profile 1, …)
        let browserMarkers = [
            "Google", "Chromium", "BraveSoftware", "Microsoft Edge",
            "com.operasoftware.Opera", "Arc", "Firefox", "com.apple.Safari",
        ]
        for marker in browserMarkers {
            if let i = parts.firstIndex(of: marker) {
                if let def = parts.firstIndex(of: "Default"), def > i {
                    return "/" + parts[0...def].joined(separator: "/")
                }
                if let prof = parts.firstIndex(of: "Profiles"), prof + 1 < parts.count, prof > i {
                    return "/" + parts[0...(prof + 1)].joined(separator: "/")
                }
                let end = min(i + 2, parts.count - 1)
                return "/" + parts[0...end].joined(separator: "/")
            }
        }

        // Project-local reclaimable folders (.next, target, .cache, dist, …):
        // stop at the artifact segment so each project under a monorepo is its own row.
        // Example: …/akzonobel/app-a/.next  →  that path, NOT …/akzonobel
        let artifactNames = ScanPolicy.projectLocalArtifactDirectoryNames
        if let i = parts.lastIndex(where: { artifactNames.contains($0.lowercased()) }) {
            return "/" + parts[0...i].joined(separator: "/")
        }

        // Xcode / IDE style build products often appear as full directory findings.
        let buildProductNames: Set<String> = [
            "deriveddata", "archives", "ios device support", "watchos device support",
            "coresimulator", "modulecache.noindex", "documentationcache",
        ]
        if let i = parts.lastIndex(where: { buildProductNames.contains($0.lowercased()) }) {
            return "/" + parts[0...i].joined(separator: "/")
        }

        // Default: keep the finding path (or its parent if the leaf looks like a file).
        // Do **not** apply a shallow depth cap — that merges monorepo children into the root
        // and falsely presents a large tree as “6 items”.
        let last = parts[parts.count - 1]
        let lastLower = last.lowercased()
        let isArtifactLike = artifactNames.contains(lastLower) || last.hasPrefix(".")
        if !isArtifactLike, last.contains("."), parts.count > 1 {
            // e.g. …/Cache/f_000001 → parent folder
            return "/" + parts.dropLast().joined(separator: "/")
        }
        return "/" + parts.joined(separator: "/")
    }

    public static func buildAggregate(
        from findings: [ScanFinding],
        maxRowsPerCategory: Int = defaultMaxRowsPerCategory
    ) -> FolderAggregate {
        struct Acc {
            var bytes: Int64 = 0
            var count: Int = 0
            var reviewCount: Int = 0
            var paths: [String] = []
            var worstRisk: RiskLevel = .safe
        }

        var byCategory: [ScanCategory: [String: Acc]] = [:]

        for finding in findings {
            guard finding.riskLevel != .advanced else { continue }
            let folderPath = rollupFolderPath(for: finding.path)
            var catMap = byCategory[finding.category] ?? [:]
            var acc = catMap[folderPath] ?? Acc()
            acc.bytes += finding.sizeBytes
            acc.count += 1
            acc.paths.append(finding.path)
            if finding.riskLevel == .review {
                acc.reviewCount += 1
                acc.worstRisk = .review
            }
            catMap[folderPath] = acc
            byCategory[finding.category] = catMap
        }

        var aggregate = FolderAggregate()
        for (category, map) in byCategory {
            let sorted = map
                .map { folderPath, acc -> (String, Acc, String) in
                    let id = "\(category.rawValue)|\(folderPath)"
                    return (folderPath, acc, id)
                }
                .sorted { $0.1.bytes > $1.1.bytes }

            var rows: [CategoryFolderRow] = []
            rows.reserveCapacity(min(sorted.count, maxRowsPerCategory))

            for (index, entry) in sorted.enumerated() {
                let (folderPath, acc, id) = entry
                // Keep path maps for every aggregate (needed for clean), but only publish top N rows.
                aggregate.pathsByFolderId[id] = acc.paths
                for p in acc.paths {
                    aggregate.folderIdByPath[p] = id
                }
                aggregate.metaByFolderId[id] = FolderMeta(
                    itemCount: acc.count,
                    bytes: acc.bytes,
                    reviewCount: acc.reviewCount,
                    isSafe: acc.worstRisk == .safe
                )
                if acc.worstRisk == .safe {
                    aggregate.safeFolderIds.insert(id)
                    aggregate.safeFolderIdsByCategory[category, default: []].insert(id)
                }
                // Attribute once from the rolled-up folder path (same chart labels).
                // Majority-vote over every file path was O(files × pattern checks) and
                // dominated finalize time on large developer caches.
                let toolName = ScanReportAnnotator.sourceApp(forPath: folderPath)
                if index < maxRowsPerCategory {
                    rows.append(
                        CategoryFolderRow(
                            id: id,
                            folderPath: folderPath,
                            displayPath: abbreviatePath(folderPath),
                            totalBytes: acc.bytes,
                            itemCount: acc.count,
                            riskLevel: acc.worstRisk,
                            isSelectable: !acc.paths.isEmpty,
                            toolName: toolName
                        )
                    )
                }
            }
            aggregate.rowsByCategory[category] = rows
            aggregate.toolGroupsByCategory[category] = makeToolGroups(
                category: category,
                rows: rows
            )
        }
        return aggregate
    }

    public static func makeToolGroups(
        category: ScanCategory,
        rows: [CategoryFolderRow]
    ) -> [CategoryToolGroup] {
        let grouped = Dictionary(grouping: rows, by: \.toolName)
        return grouped.map { toolName, toolRows in
            let folderIds = Set(toolRows.map(\.id))
            let totalBytes = toolRows.reduce(Int64(0)) { $0 + $1.totalBytes }
            let itemCount = toolRows.reduce(0) { $0 + $1.itemCount }
            let hasReview = toolRows.contains { $0.riskLevel == .review }
            let selectable = toolRows.contains(where: \.isSelectable)
            return CategoryToolGroup(
                id: "\(category.rawValue)|tool|\(toolName)",
                category: category,
                toolName: toolName,
                totalBytes: totalBytes,
                folderCount: toolRows.count,
                itemCount: itemCount,
                riskLevel: hasReview ? .review : .safe,
                folderIds: folderIds,
                isSelectable: selectable
            )
        }
        .sorted { $0.totalBytes > $1.totalBytes }
    }

    public static func makeToolRollups(from findings: [ScanFinding]) -> [ToolRollup] {
        // Chart is about reclaimable space — exclude advanced (e.g. Docker.raw attribution noise).
        let reclaimable = findings.filter { $0.riskLevel != .advanced }
        let rollups = ScanReportAnnotator.appRollups(from: reclaimable)
        let total = rollups.reduce(0) { $0 + $1.totalBytes }
        return rollups.map { ToolRollup(rollup: $0, total: total) }
    }
}
