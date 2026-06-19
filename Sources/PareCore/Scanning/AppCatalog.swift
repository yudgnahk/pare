import Foundation

/// A single app entry in the bundled `app-catalog.json`.
public struct AppCatalogEntry: Decodable, Sendable {
    /// Unique identifier used in rule logic.
    public let id: String
    /// Human-readable name shown in the UI.
    public let displayName: String
    /// Logical grouping (e.g. "ai"). Matches the filter key used by rules.
    public let category: String
    /// Cache subdirectories relative to `~/Library/` (e.g. "Application Support/Cursor/Cache").
    public let libraryPaths: [String]
    /// Cache subdirectories relative to `~/` (e.g. ".continue/cache").
    public let homePaths: [String]

    private enum CodingKeys: String, CodingKey {
        case id, displayName, category, libraryPaths, homePaths
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        category = try c.decode(String.self, forKey: .category)
        libraryPaths = try c.decodeIfPresent([String].self, forKey: .libraryPaths) ?? []
        homePaths = try c.decodeIfPresent([String].self, forKey: .homePaths) ?? []
    }
}

/// Decoded representation of `app-catalog.json`, bundled inside PareCore resources.
/// Use `AppCatalog.shared` everywhere — the catalog is loaded once at first access.
public struct AppCatalog: Decodable, Sendable {
    public let version: Int
    public let entries: [AppCatalogEntry]

    /// Process-lifetime singleton — JSON is parsed once and cached.
    public static let shared: AppCatalog = {
        guard let url = Bundle.module.url(forResource: "app-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(AppCatalog.self, from: data) else {
            return AppCatalog(version: 1, entries: [])
        }
        return catalog
    }()

    /// Returns all entries matching the given category string.
    public func entries(forCategory category: String) -> [AppCatalogEntry] {
        entries.filter { $0.category == category }
    }

    public init(version: Int, entries: [AppCatalogEntry]) {
        self.version = version
        self.entries = entries
    }
}
