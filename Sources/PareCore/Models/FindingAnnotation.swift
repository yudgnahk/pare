import Foundation

/// Extra facts about a finding that change how it should be presented, not whether it was found.
public enum FindingAnnotation: Sendable, Equatable {
    /// Nothing for Pare to delete; `action` tells the user how to reclaim the space themselves.
    case explainOnly(action: String)
}
