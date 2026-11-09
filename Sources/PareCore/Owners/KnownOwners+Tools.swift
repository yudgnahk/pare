import Foundation

extension KnownOwners {
    static let devTools: [KnownOwner] = [
        tool("npm", "npm", home: [".npm"]),
        tool("pnpm", "pnpm",
             home: ["Library/pnpm", ".local/share/pnpm", "Library/Caches/pnpm", ".cache/pnpm"]),
        tool("yarn", "Yarn", home: ["Library/Caches/Yarn", ".yarn", ".cache/yarn"]),
        tool("bun", "Bun", home: [".bun"]),
        tool("cargo", "Cargo", home: [".cargo"]),
        tool("rustup", "rustup", home: [".rustup"]),
        tool("homebrew", "Homebrew", home: ["Library/Caches/Homebrew"]),
        tool("cocoapods", "CocoaPods", home: ["Library/Caches/CocoaPods", ".cocoapods"]),
        tool("swiftpm", "SwiftPM",
             home: ["Library/Caches/org.swift.swiftpm", "Library/org.swift.swiftpm", ".swiftpm"]),
        tool("gradle", "Gradle", home: [".gradle"]),
        tool("maven", "Maven", home: [".m2"]),
        tool("ivy", "Ivy", home: [".ivy2"]),
        tool("uv", "uv", home: [".cache/uv", "Library/Caches/uv"]),
        tool("pip", "pip", home: [".cache/pip", "Library/Caches/pip"]),
        tool("poetry", "Poetry", home: [".cache/pypoetry", "Library/Caches/pypoetry"]),
        tool("pyenv", "pyenv", home: [".pyenv"]),
        tool("rubygems", "RubyGems", home: [".gem"]),
        tool("bundler", "Bundler", home: [".bundle"]),
        tool("rbenv", "rbenv", home: [".rbenv"]),
        tool("go", "Go", home: [".cache/go-build", "Library/Caches/go-build", "go/pkg"]),
        tool("node-gyp", "node-gyp", home: [".node-gyp", "Library/Caches/node-gyp"]),
        tool("electron", "Electron", home: ["Library/Caches/electron", ".cache/electron"]),
        tool("typescript", "TypeScript", home: ["Library/Caches/typescript"]),
        tool("android-sdk", "Android SDK", home: [".android", "Library/Android"]),
    ]
}
