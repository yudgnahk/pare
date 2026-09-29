import Foundation
import UniformTypeIdentifiers
import PareCore

/// One row in the Disk Analyzer table for a real file or folder.
struct DiskEntry: Identifiable, Sendable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let sizeBytes: Int64
    let itemCount: Int
    let modified: Date?
    let creationDate: Date?
    let hasPartialSize: Bool
    let kind: DiskKind

    init(
        id: String,
        url: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool,
        sizeBytes: Int64,
        itemCount: Int,
        modified: Date?,
        kind: DiskKind,
        creationDate: Date? = nil,
        hasPartialSize: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.sizeBytes = sizeBytes
        self.itemCount = itemCount
        self.modified = modified
        self.creationDate = creationDate
        self.hasPartialSize = hasPartialSize
        self.kind = kind
    }

    /// Row identity: canonical `/private` spelling but the leaf left unresolved, so a symlink never shares its target's id.
    static func standardizedID(for url: URL) -> String {
        ScanPolicy.canonicalPathURL(url).path
    }

}

/// Coarse file kind for the table's Kind column and filter, classified by `UTType` conformance.
enum DiskKind: String, CaseIterable, Sendable {
    case folder
    case application
    case image
    case video
    case audio
    case document
    case archive
    case diskImage
    case other

    /// Order matters: some UTTypes conform to more than one candidate (e.g. `.dmg` is both
    /// `.diskImage` and `.archive`), so more specific checks run first.
    init(isDirectory: Bool, isPackage: Bool, pathExtension: String) {
        if isPackage {
            self = Self.isApplicationExtension(pathExtension) ? .application : .folder
            return
        }
        if isDirectory {
            self = .folder
            return
        }
        self = Self.classifyFile(pathExtension: pathExtension)
    }

    /// Display name shared by the table's Kind column, the inspector and the Kind filter.
    var label: String {
        switch self {
        case .folder: return "Folder"
        case .application: return "Application"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Document"
        case .archive: return "Archive"
        case .diskImage: return "Disk Image"
        case .other: return "Other"
        }
    }

    private static func isApplicationExtension(_ pathExtension: String) -> Bool {
        UTType(filenameExtension: pathExtension)?.conforms(to: .application) ?? false
    }

    private static func classifyFile(pathExtension: String) -> DiskKind {
        guard let type = UTType(filenameExtension: pathExtension) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .diskImage) { return .diskImage }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .content) { return .document }
        return .other
    }
}
