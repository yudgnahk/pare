import Foundation

extension KnownOwners {
    static let browsers: [KnownOwner] = [
        app("chrome", "Chrome",
            // Folder rollup stops at Caches/Google, so that bare folder is Chrome's too.
            home: ["Library/Application Support/Google/Chrome", "Library/Caches/Google"],
            bundle: ["com.google.chrome"]),
        app("chromium", "Chromium",
            home: ["Library/Application Support/Chromium", "Library/Caches/Chromium"],
            bundle: ["org.chromium.chromium"]),
        app("safari", "Safari", home: ["Library/Safari"], bundle: ["com.apple.safari"]),
        app("firefox", "Firefox",
            home: ["Library/Application Support/Firefox", "Library/Caches/Firefox", "Library/Caches/Mozilla"],
            bundle: ["org.mozilla.firefox"]),
        app("brave", "Brave",
            home: ["Library/Application Support/BraveSoftware", "Library/Caches/BraveSoftware"],
            bundle: ["com.brave.browser"]),
        app("edge", "Edge",
            home: ["Library/Application Support/Microsoft Edge", "Library/Caches/Microsoft Edge"],
            bundle: ["com.microsoft.edgemac"]),
        app("arc", "Arc",
            home: ["Library/Application Support/Arc", "Library/Caches/Arc"],
            bundle: ["company.thebrowser.browser"]),
        app("opera", "Opera", bundle: ["com.operasoftware.opera"]),
    ]

    static let communication: [KnownOwner] = [
        app("slack", "Slack", home: ["Library/Application Support/Slack"], bundle: ["com.tinyspeck.slackmacgap"]),
        app("zoom", "Zoom", home: ["Library/Application Support/zoom.us"], bundle: ["us.zoom.xos"]),
        app("discord", "Discord", home: ["Library/Application Support/discord"], bundle: ["com.hnc.discord"]),
        app("teams", "Teams",
            home: ["Library/Application Support/Microsoft/Teams", "Library/Application Support/Teams"],
            bundle: ["com.microsoft.teams", "com.microsoft.teams2"]),
        app("telegram", "Telegram",
            home: ["Library/Application Support/Telegram", "Library/Application Support/Telegram Desktop"],
            bundle: ["ru.keepcoder.telegram"]),
        app("whatsapp", "WhatsApp", bundle: ["net.whatsapp.whatsapp"]),
        app("signal", "Signal", home: ["Library/Application Support/Signal"]),
        app("notion", "Notion",
            home: ["Library/Application Support/Notion", "Library/Caches/notion.id"]),
        app("spotify", "Spotify", home: ["Library/Application Support/Spotify"], bundle: ["com.spotify.client"]),
        app("1password", "1Password",
            home: ["Library/Application Support/1Password"], bundle: ["com.1password", "com.agilebits"]),
        app("steam", "Steam", home: ["Library/Application Support/Steam"]),
        app("raycast", "Raycast", bundle: ["com.raycast.macos"]),
        app("obsidian", "Obsidian", home: ["Library/Application Support/obsidian"], bundle: ["md.obsidian"]),
    ]

    static let editors: [KnownOwner] = [
        app("vscode", "VS Code",
            home: ["Library/Application Support/Code", "Library/Application Support/Code - Insiders", ".vscode"],
            bundle: ["com.microsoft.vscode", "com.visualstudio.code"]),
        app("cursor", "Cursor",
            home: ["Library/Application Support/Cursor", "Library/Caches/Cursor", ".cursor"],
            bundle: ["com.todesktop.230313mzl4w4u92"]),
        app("windsurf", "Windsurf",
            home: ["Library/Application Support/Windsurf", "Library/Caches/Windsurf", ".windsurf"]),
        app("jetbrains", "JetBrains",
            home: [
                "Library/Application Support/JetBrains", "Library/Caches/JetBrains",
                "Library/Logs/JetBrains", "Library/Preferences/JetBrains",
            ],
            bundle: [
                "com.jetbrains", "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.webstorm",
                "com.jetbrains.goland", "com.jetbrains.rider", "com.jetbrains.clion", "com.jetbrains.datagrip",
                "com.jetbrains.rubymine", "com.jetbrains.phpstorm", "com.jetbrains.rustrover",
            ]),
        app("androidstudio", "Android Studio",
            home: [
                "Library/Application Support/Google/AndroidStudio*", "Library/Caches/Google/AndroidStudio*",
                "Library/Logs/Google/AndroidStudio*",
            ],
            bundle: ["com.google.android.studio"]),
        app("xcode", "Xcode",
            home: [
                "Library/Developer/Xcode", "Library/Developer/CoreSimulator",
                "Library/Developer/XCTestDevices", "Library/Developer/Toolchains",
            ],
            bundle: ["com.apple.dt.xcode"]),
        app("postman", "Postman",
            home: ["Library/Application Support/Postman", "Library/Caches/Postman"],
            bundle: ["com.postmanlabs.mac"]),
        app("docker", "Docker",
            home: [
                "Library/Application Support/Docker Desktop", "Library/Caches/Docker",
                "Library/Group Containers/group.com.docker", ".docker",
            ],
            bundle: ["com.docker.docker"]),
    ]

    static let creative: [KnownOwner] = [
        app("figma", "Figma", home: ["Library/Application Support/Figma"], bundle: ["com.figma.desktop"]),
        app("sketch", "Sketch", bundle: ["com.bohemiancoding.sketch3"]),
        app("adobe", "Adobe",
            home: ["Library/Application Support/Adobe", "Library/Caches/Adobe", "Library/Logs/Adobe"],
            root: ["Library/Application Support/Adobe"],
            bundle: ["com.adobe"]),
        app("davinci", "DaVinci Resolve",
            home: ["Library/Application Support/Blackmagic Design", "Library/Caches/Blackmagic Design"],
            bundle: ["com.blackmagic-design.davinciresolve", "com.blackmagicdesign"]),
        app("finalcut", "Final Cut Pro",
            home: ["Library/Application Support/Final Cut Pro"],
            bundle: ["com.apple.finalcut"]),
    ]

    static let aiTools: [KnownOwner] = [
        app("claude", "Claude",
            home: ["Library/Application Support/Claude", "Library/Caches/Claude", "Library/Logs/Claude", ".claude"],
            bundle: ["com.anthropic.claudefordesktop"]),
        app("chatgpt", "ChatGPT", bundle: ["com.openai.chat"]),
        app("codex", "Codex", home: [".codex"], bundle: ["com.openai.codex"]),
        app("opencode", "OpenCode",
            home: [".cache/opencode", ".local/share/opencode", "Library/Caches/opencode", ".opencode"]),
    ]
}
