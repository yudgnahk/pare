import Foundation

/// Section order in the owner browser.
public enum OwnerKind: Int, Sendable, CaseIterable, Comparable {
    case app, project, tool, macOS, other

    public static func < (lhs: OwnerKind, rhs: OwnerKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Who a scan folder belongs to: an app, a project, a developer tool, macOS itself, or nobody known.
public struct FolderOwner: Hashable, Sendable {
    public let kind: OwnerKind
    /// Stable identity: `app:<id>`, `tool:<id>`, `project:<abs root>`, `macos`, `other`.
    public let key: String
    public let displayName: String
    public let projectRoot: String?

    public init(kind: OwnerKind, key: String, displayName: String, projectRoot: String? = nil) {
        self.kind = kind
        self.key = key
        self.displayName = displayName
        self.projectRoot = projectRoot
    }

    public static let macOS = FolderOwner(kind: .macOS, key: "macos", displayName: "macOS")
    public static let other = FolderOwner(kind: .other, key: "other", displayName: "Other")

    public static func project(_ ref: ProjectRef) -> FolderOwner {
        FolderOwner(kind: .project, key: "project:\(ref.root)", displayName: ref.name, projectRoot: ref.root)
    }

    /// Donut slice label: one slice per app, shared slices for projects and tools.
    public var chartLabel: String {
        switch kind {
        case .app: return displayName
        case .project: return "Projects"
        case .tool: return "Developer tools"
        case .macOS: return "macOS"
        case .other: return "Other"
        }
    }
}

public protocol OwnerResolving: Sendable {
    func owner(forFolderPath path: String) -> FolderOwner
}

public struct ProjectRef: Hashable, Sendable {
    public let root: String
    public let name: String

    public init(root: String, name: String) {
        self.root = root
        self.name = name
    }
}

/// Phase A stub: detection arrives in a later phase, so nothing is a project yet.
public struct ProjectIndex: Sendable {
    public static let empty = ProjectIndex()

    public init() {}

    public func project(containing folderPath: String) -> ProjectRef? { nil }
}
