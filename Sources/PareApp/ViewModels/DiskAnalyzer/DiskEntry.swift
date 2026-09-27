import Foundation
import UniformTypeIdentifiers

/// One row in the Disk Analyzer table: a real file/folder, or the synthetic "smaller items" remainder.
struct DiskEntry: Identifiable, Sendable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let sizeBytes: Int64
    let itemCount: Int
    let modified: Date?
    let kind: DiskKind
    /// Marks the folded "N smaller items" row; DiskTableQuery always sorts it last and exempts it from filters.
    let isRemainder: Bool

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
        isRemainder: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.sizeBytes = sizeBytes
        self.itemCount = itemCount
        self.modified = modified
        self.kind = kind
        self.isRemainder = isRemainder
    }

    /// `/private/var`-safe identity so a directory and its resolved symlink spelling never appear as two rows.
    static func standardizedID(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// Builds the folded row DiskLevelLoader appends after a level's top 200 children.
    static func remainder(count: Int, sizeBytes: Int64, in directory: URL) -> DiskEntry {
        let url = directory.appendingPathComponent("#pare-remainder")
        return DiskEntry(
            id: "\(standardizedID(for: directory))/#pare-remainder",
            url: url,
            name: count == 1 ? "1 smaller item" : "\(count) smaller items",
            isDirectory: false,
            isPackage: false,
            sizeBytes: sizeBytes,
            itemCount: count,
            modified: nil,
            kind: .other,
            isRemainder: true
        )
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
