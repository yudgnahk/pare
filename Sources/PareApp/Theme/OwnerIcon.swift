import PareCore

/// SF Symbols for tool/app groups, donut owners and owner-browser headers.
enum OwnerIcon {
    /// Symbol for a tool-group or owner name; unknown names get a generic app glyph.
    static func symbol(forName name: String) -> String {
        switch name {
        case "Xcode": return "hammer.fill"
        case "VS Code", "Cursor", "Windsurf": return "chevron.left.forwardslash.chevron.right"
        case "JetBrains", "Android Studio": return "j.circle.fill"
        case "Docker": return "shippingbox.fill"
        case "Safari": return "safari.fill"
        case "Chrome", "Chromium", "Brave", "Edge", "Opera", "Arc": return "globe"
        case "Firefox": return "flame.fill"
        case "Package Managers", "npm", "pnpm", "Yarn", "Bun", "CocoaPods", "SwiftPM", "Cargo", "rustup",
             "Gradle", "Maven", "Ivy", "uv", "pip", "Poetry", "pyenv", "RubyGems", "Bundler", "rbenv", "Go",
             "node-gyp", "Electron", "TypeScript", "Android SDK":
            return "shippingbox"
        case "Homebrew": return "mug.fill"
        case "Developer tools": return "wrench.and.screwdriver.fill"
        case "Projects": return "folder.fill"
        case "macOS", "System Logs": return "applelogo"
        case "Temp Files": return "clock.arrow.circlepath"
        case "Slack", "Discord", "Teams", "Telegram", "WhatsApp", "Signal": return "message.fill"
        case "Zoom": return "video.fill"
        case "Spotify": return "music.note"
        case "OpenCode", "Codex": return "terminal"
        case "Claude", "ChatGPT": return "brain.head.profile"
        case "Figma", "Sketch", "Adobe": return "paintbrush.pointed.fill"
        case "DaVinci Resolve", "Final Cut Pro": return "film.fill"
        case "Other": return "questionmark.folder"
        default: return "app.fill"
        }
    }

    /// Owner kinds without a named symbol fall back to a kind glyph.
    static func symbol(for owner: FolderOwner) -> String {
        switch owner.kind {
        case .project: return "folder.fill"
        case .macOS: return "applelogo"
        case .other: return "questionmark.folder"
        case .tool:
            let named = symbol(forName: owner.displayName)
            return named == "app.fill" ? "wrench.and.screwdriver.fill" : named
        case .app: return symbol(forName: owner.displayName)
        }
    }
}
