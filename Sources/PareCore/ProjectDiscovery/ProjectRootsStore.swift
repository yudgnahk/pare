import Foundation

/// Codable model persisted to ~/Library/Application Support/Pare/project-roots.json.
struct ProjectRootsStore: Codable {
    /// Auto-discovered roots the user has not excluded.
    var confirmed: [String]
    /// Auto-discovered roots the user has explicitly opted out of.
    var excluded: [String]
    /// Paths the user added manually via "Add Folder…".
    var manual: [String]
    /// When the last Spotlight discovery pass ran (nil = never).
    var lastDiscoveredAt: Date?
}
