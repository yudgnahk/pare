import Foundation

/// Extra facts about a finding that change how it should be presented, not whether it was found.
public enum FindingAnnotation: Sendable, Equatable {
    /// A tool-managed cache in active use; `selfTrimDays` is how long the tool keeps unused entries (nil = never trims).
    case workingSet(selfTrimDays: Int?)
    /// Nothing for Pare to delete; `action` tells the user how to reclaim the space themselves.
    case explainOnly(action: String)
}
