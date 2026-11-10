import AppKit
import SwiftUI
import PareCore

/// App icons by bundle path, each loaded from `NSWorkspace` once.
final class AppIconCache: @unchecked Sendable {
    static let shared = AppIconCache()

    private let lock = NSLock()
    private var icons: [String: NSImage] = [:]
    private let loader: (String) -> NSImage

    init(loader: @escaping (String) -> NSImage = { NSWorkspace.shared.icon(forFile: $0) }) {
        self.loader = loader
    }

    func cachedIcon(forPath path: String) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        return icons[path]
    }

    func icon(forPath path: String) -> NSImage {
        if let hit = cachedIcon(forPath: path) { return hit }
        let image = loader(path)
        lock.lock(); icons[path] = image; lock.unlock()
        return image
    }
}

/// Real app icon when the owner's app is installed, else the owner's SF Symbol. Loads in `.task`, never in `body`.
struct OwnerIconView: View {
    let owner: FolderOwner
    let appPath: String?
    var size: CGFloat = 18
    @State private var image: NSImage?
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: scale.scaled(size), height: scale.scaled(size))
            } else {
                Image(systemName: OwnerIcon.symbol(for: owner))
                    .font(scale.font(size * 0.72, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: scale.scaled(size), height: scale.scaled(size))
            }
        }
        .help(Self.help(for: owner))
        .accessibilityHidden(true)
        .task(id: appPath) {
            image = appPath.map { AppIconCache.shared.icon(forPath: $0) }
        }
    }

    static func help(for owner: FolderOwner) -> String {
        switch owner.kind {
        case .macOS: return "Owned by macOS"
        case .other: return "Owner unknown"
        case .app, .project, .tool: return owner.displayName
        }
    }
}
