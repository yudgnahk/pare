import Foundation

/// Size filter buckets for the Disk Analyzer's Size picker.
enum DiskSizeFloor: CaseIterable, Sendable {
    case any
    case oneMB
    case oneHundredMB
    case oneGB

    /// Minimum bytes an entry must reach to pass this floor.
    var minimumBytes: Int64 {
        switch self {
        case .any: return 0
        case .oneMB: return 1_000_000
        case .oneHundredMB: return 100_000_000
        case .oneGB: return 1_000_000_000
        }
    }
}

/// Column the Disk Analyzer table can be sorted by.
enum DiskSortField: CaseIterable, Sendable {
    case name, size, items, modified, kind
}

/// One sort key plus direction; `DiskTableQuery` always appends a name tiebreak after this.
struct DiskSortDescriptor: Sendable, Hashable {
    var field: DiskSortField
    var ascending: Bool

    static let nameAscending = DiskSortDescriptor(field: .name, ascending: true)
}

/// Pure filter/sort pipeline for one Disk Analyzer level's rows.
enum DiskTableQuery {
    /// Filters and sorts `entries`, then re-appends the remainder row last — it ignores every filter.
    static func apply(
        entries: [DiskEntry],
        search: String,
        kind: DiskKind?,
        sizeFloor: DiskSizeFloor,
        sortOrder: DiskSortDescriptor
    ) -> [DiskEntry] {
        let remainder = entries.filter(\.isRemainder)
        let candidates = entries.filter { !$0.isRemainder }

        let normalizedSearch = normalize(search)
        let filtered = candidates.filter { entry in
            matchesSearch(entry, normalizedSearch: normalizedSearch)
                && matchesKind(entry, kind: kind)
                && entry.sizeBytes >= sizeFloor.minimumBytes
        }

        return filtered.sorted { compare($0, $1, by: sortOrder) } + remainder
    }

    private static func matchesSearch(_ entry: DiskEntry, normalizedSearch: String) -> Bool {
        guard !normalizedSearch.isEmpty else { return true }
        return normalize(entry.name).contains(normalizedSearch)
    }

    private static func matchesKind(_ entry: DiskEntry, kind: DiskKind?) -> Bool {
        guard let kind else { return true }
        return entry.kind == kind
    }

    /// Case- and diacritic-insensitive folding for name search and the name tiebreak.
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func compare(_ lhs: DiskEntry, _ rhs: DiskEntry, by order: DiskSortDescriptor) -> Bool {
        let primary = primaryOrdering(lhs, rhs, field: order.field)
        if primary != .orderedSame {
            return order.ascending ? primary == .orderedAscending : primary == .orderedDescending
        }
        return normalize(lhs.name) < normalize(rhs.name)
    }

    /// Also used by `DiskColumnComparator` (SwiftUI Table header sort state) to avoid duplicating field-ordering logic.
    static func primaryOrdering(_ lhs: DiskEntry, _ rhs: DiskEntry, field: DiskSortField) -> ComparisonResult {
        switch field {
        case .name:
            return compareStrings(normalize(lhs.name), normalize(rhs.name))
        case .size:
            return compareInt64(lhs.sizeBytes, rhs.sizeBytes)
        case .items:
            return compareInt64(Int64(lhs.itemCount), Int64(rhs.itemCount))
        case .modified:
            return compareDates(lhs.modified, rhs.modified)
        case .kind:
            return compareStrings(lhs.kind.rawValue, rhs.kind.rawValue)
        }
    }

    private static func compareStrings(_ a: String, _ b: String) -> ComparisonResult {
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }

    private static func compareInt64(_ a: Int64, _ b: Int64) -> ComparisonResult {
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }

    /// A `nil` modified date sorts as oldest, regardless of direction.
    private static func compareDates(_ a: Date?, _ b: Date?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (l?, r?):
            if l == r { return .orderedSame }
            return l < r ? .orderedAscending : .orderedDescending
        }
    }
}
