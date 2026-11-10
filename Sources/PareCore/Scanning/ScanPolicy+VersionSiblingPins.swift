import Foundation

// MARK: - Version siblings: alias pins (`default`, `current`, `aliases/*`)

extension ScanPolicy {

    /// Files a version manager writes to select the active version (fnm `default`, pyenv `version`, …).
    static let versionSiblingAliasFileNames: Set<String> = [
        "default", "current", "latest", "stable", "active", "global", "version", ".version",
    ]
    /// Directories holding one alias per entry (fnm `aliases/`, nvm `alias/`).
    static let versionSiblingAliasDirectoryNames: Set<String> = ["alias", "aliases"]
    /// An alias file holds a version or a path; only this much is read.
    static let versionSiblingAliasMaxBytes = 1024

    /// True when a symlink or alias file in the group's parent or grandparent selects one of its members.
    /// Unreadable or unparseable aliases count as pins, so a manager's group is never offered.
    public static func isPinnedVersionSiblingGroup(_ members: [URL]) -> Bool {
        guard let first = members.first else { return false }
        let parent = first.deletingLastPathComponent()
        let memberPaths = Set(members.map(\.standardizedFileURL.path))
        return [parent, parent.deletingLastPathComponent()].contains { directory in
            let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return entries.contains { entry in
                !memberPaths.contains(entry.standardizedFileURL.path)
                    && aliasPinsMember(entry, members: members, insideAliasDirectory: false)
            }
        }
    }

    private static func aliasPinsMember(_ entry: URL, members: [URL], insideAliasDirectory: Bool) -> Bool {
        let name = entry.lastPathComponent.lowercased()
        let isAliasName = insideAliasDirectory || versionSiblingAliasFileNames.contains(name)
        guard let values = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else {
            return isAliasName || versionSiblingAliasDirectoryNames.contains(name)
        }
        if values.isSymbolicLink == true { return resolves(entry, intoAnyOf: members) }
        if values.isDirectory == true {
            guard !insideAliasDirectory, versionSiblingAliasDirectoryNames.contains(name) else { return false }
            guard let children = try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil) else {
                return true
            }
            return children.contains { aliasPinsMember($0, members: members, insideAliasDirectory: true) }
        }
        return isAliasName && aliasFile(entry, selectsAnyOf: members)
    }

    private static func aliasFile(_ file: URL, selectsAnyOf members: [URL]) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return true }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: versionSiblingAliasMaxBytes) ?? Data(),
              let text = String(data: data, encoding: .utf8) else { return true }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") {
            let target = value.hasPrefix("/")
                ? URL(fileURLWithPath: value)
                : file.deletingLastPathComponent().appending(path: value)
            return resolves(target, intoAnyOf: members)
        }
        let bare = value.hasPrefix("v") ? String(value.dropFirst()) : value
        // `lts/*`, `system`, `stable`…: syntax we can't map to a member counts as a pin.
        guard !bare.isEmpty, bare.allSatisfy({ $0.isNumber || $0 == "." }) else { return true }
        return members.contains { member in
            guard let version = VersionedName(member.lastPathComponent)?.version else { return false }
            let text = "\(version.major).\(version.minor).\(version.patch)"
            return text == bare || text.hasPrefix(bare + ".")
        }
    }

    private static func resolves(_ url: URL, intoAnyOf members: [URL]) -> Bool {
        let target = canonicalPathURL(url.resolvingSymlinksInPath())
        return members.contains { isEqualToOrDescendant(candidate: target, root: canonicalPathURL($0.resolvingSymlinksInPath())) }
    }
}
