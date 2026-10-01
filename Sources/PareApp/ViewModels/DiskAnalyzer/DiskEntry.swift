import Foundation
import UniformTypeIdentifiers
import PareCore

/// Row identity compared by exact UTF-8 bytes: `String ==` treats NFC and NFD names (both possible on exFAT/SMB) as equal.
struct DiskEntryID: Hashable, Sendable, ExpressibleByStringLiteral {
    let path: String

    init(_ path: String) {
        self.path = path
    }

    init(stringLiteral value: String) {
        self.init(value)
    }

    static func == (lhs: DiskEntryID, rhs: DiskEntryID) -> Bool {
        lhs.path.utf8.elementsEqual(rhs.path.utf8)
    }

    func hash(into hasher: inout Hasher) {
        var bytes = path
        bytes.withUTF8 { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
    }
}

/// One row in the Disk Analyzer table for a real file or folder.
struct DiskEntry: Identifiable, Sendable, Hashable {
    let id: DiskEntryID
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let sizeBytes: Int64
    let itemCount: Int
    let modified: Date?
    let creationDate: Date?
    let hasPartialSize: Bool
    /// A mounted volume listed from its parent; its size is only measured once the user opens it.
    let isSeparateVolume: Bool
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
        hasPartialSize: Bool = false,
        isSeparateVolume: Bool = false
    ) {
        self.id = DiskEntryID(id)
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.sizeBytes = sizeBytes
        self.itemCount = itemCount
        self.modified = modified
        self.creationDate = creationDate
        self.hasPartialSize = hasPartialSize
        self.isSeparateVolume = isSeparateVolume
        self.kind = kind
    }

    /// Row identity: canonical `/private` spelling but the leaf left unresolved, so a symlink never shares its target's id.
    static func standardizedID(for url: URL) -> String {
        ScanPolicy.canonicalPathURL(url, normalizingFirmlinks: false).path
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
