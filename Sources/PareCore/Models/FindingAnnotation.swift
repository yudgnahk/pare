import Foundation

/// Extra facts about a finding that change how it should be presented, not whether it was found.
public enum FindingAnnotation: Sendable, Equatable {
    /// A tool-managed cache in active use; `selfTrimDays` is how long the tool keeps unused entries (nil = never trims).
    case workingSet(selfTrimDays: Int?)
    /// Nothing for Pare to delete; `action` tells the user how to reclaim the space themselves.
    case explainOnly(action: String)
    /// A process keeping deleted files open; lets the app fold every holder into one note.
    case deletedFilesHolder(DeletedFilesHolder)
    /// The one place a diagnostic note's button takes the user.
    case noteAction(DiagnosticAction)
}

/// A process holding deleted files open, named the way the user knows it.
public struct DeletedFilesHolder: Sendable, Equatable {
    public let command: String
    /// The outermost `.app` name when there is one, else the command.
    public let displayName: String
    public let pids: [Int32]
    /// Part of macOS: only a restart of the Mac releases it.
    public let isSystem: Bool

    public init(command: String, displayName: String, pids: [Int32], isSystem: Bool) {
        self.command = command
        self.displayName = displayName
        self.pids = pids
        self.isSystem = isSystem
    }
}

/// Where a diagnostic note sends the user; Pare itself never changes anything.
public enum DiagnosticAction: Sendable, Equatable {
    /// Empty `pids` means every process.
    case showProcesses(pids: [Int32])
    case openLoginItems
    case revealInFinder(path: String)
    case openICloudStorage
}
