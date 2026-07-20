import Foundation
import AppKit

/// Errors raised while detaching a cask from Homebrew without deleting the app.
public enum CaskLeaveError: Error, LocalizedError, Equatable {
    case appsRunning([String])
    case stageFailed(path: String, message: String)
    case uninstallFailed(message: String)
    case restoreFailed(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .appsRunning(let names):
            let list = names.joined(separator: ", ")
            return "Quit \(list) before leaving Homebrew, or choose Force Quit."
        case .stageFailed(let path, let message):
            return "Could not stage \(path): \(message)"
        case .uninstallFailed(let message):
            return "Homebrew uninstall failed: \(message)"
        case .restoreFailed(let path, let message):
            return "Could not restore \(path): \(message)"
        }
    }
}

/// Result of a successful leave operation.
public struct CaskLeaveResult: Sendable, Equatable {
    public let token: String
    /// Absolute paths of `.app` bundles that were preserved on disk.
    public let preservedAppPaths: [String]
    public let messages: [String]

    public init(token: String, preservedAppPaths: [String], messages: [String]) {
        self.token = token
        self.preservedAppPaths = preservedAppPaths
        self.messages = messages
    }
}

/// Detaches a Homebrew cask while keeping its installed application(s).
///
/// Inverse of `brew install --cask --adopt`:
/// 1. Stage each installed `.app` aside
/// 2. `brew uninstall --cask <token>` (never `--zap`)
/// 3. Restore the app(s) to their original paths
///
/// Orphaned casks (receipt but no app) skip stage/restore and only uninstall.
public struct CaskLeaveHomebrew {

    public static let defaultApplicationSearchPaths: [String] = [
        "/Applications",
        "\(NSHomeDirectory())/Applications"
    ]

    public typealias UninstallRunner = @Sendable (String) async throws -> Void
    public typealias RunningAppsProvider = @Sendable () -> [String]

    private let applicationSearchPaths: [String]
    private let fileManager: FileManager
    private let uninstall: UninstallRunner
    private let runningAppPaths: RunningAppsProvider

    /// Production initializer — uses `BrewRunner` and `NSWorkspace`.
    public init(
        applicationSearchPaths: [String] = CaskLeaveHomebrew.defaultApplicationSearchPaths,
        fileManager: FileManager = .default
    ) {
        self.applicationSearchPaths = applicationSearchPaths
        self.fileManager = fileManager
        self.uninstall = { token in
            _ = try await BrewRunner.shared.run(["uninstall", "--cask", token])
        }
        self.runningAppPaths = {
            NSWorkspace.shared.runningApplications.compactMap { app in
                app.bundleURL?.path
            }
        }
    }

    /// Testable initializer with injectable dependencies.
    public init(
        applicationSearchPaths: [String],
        fileManager: FileManager,
        uninstall: @escaping UninstallRunner,
        runningAppPaths: @escaping RunningAppsProvider
    ) {
        self.applicationSearchPaths = applicationSearchPaths
        self.fileManager = fileManager
        self.uninstall = uninstall
        self.runningAppPaths = runningAppPaths
    }

    // MARK: - Path helpers (pure / testable)

    /// Resolves absolute paths for cask app artifacts under the search roots.
    public static func resolveInstalledAppPaths(
        appNames: [String],
        searchPaths: [String],
        fileManager: FileManager = .default
    ) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        for name in appNames {
            let normalized = name.hasSuffix(".app") ? name : "\(name).app"
            for root in searchPaths {
                let url = URL(fileURLWithPath: root).appendingPathComponent(normalized)
                let path = url.path
                guard fileManager.fileExists(atPath: path), !seen.contains(path) else { continue }
                seen.insert(path)
                found.append(url)
            }
        }
        return found
    }

    /// Whether any resolved app path is currently running.
    public static func runningApps(
        among appPaths: [URL],
        runningPaths: [String]
    ) -> [String] {
        let targets = Set(appPaths.map { $0.standardizedFileURL.path })
        var names: [String] = []
        for path in runningPaths {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            if targets.contains(standardized) {
                names.append(URL(fileURLWithPath: path).lastPathComponent)
            }
        }
        return names.sorted()
    }

    /// Copies each app into `stagingRoot`, returning original → staged pairs.
    public static func stageApps(
        appPaths: [URL],
        stagingRoot: URL,
        fileManager: FileManager = .default
    ) throws -> [(original: URL, staged: URL)] {
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        var pairs: [(original: URL, staged: URL)] = []
        for original in appPaths {
            let staged = stagingRoot.appendingPathComponent(original.lastPathComponent)
            if fileManager.fileExists(atPath: staged.path) {
                try fileManager.removeItem(at: staged)
            }
            do {
                try fileManager.copyItem(at: original, to: staged)
            } catch {
                throw CaskLeaveError.stageFailed(
                    path: original.path,
                    message: error.localizedDescription
                )
            }
            pairs.append((original, staged))
        }
        return pairs
    }

    /// Moves staged apps back to their original paths (replacing if Brew left nothing).
    public static func restoreApps(
        pairs: [(original: URL, staged: URL)],
        fileManager: FileManager = .default
    ) throws {
        for (original, staged) in pairs {
            do {
                if fileManager.fileExists(atPath: original.path) {
                    try fileManager.removeItem(at: original)
                }
                let parent = original.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parent.path) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try fileManager.moveItem(at: staged, to: original)
            } catch {
                throw CaskLeaveError.restoreFailed(
                    path: original.path,
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Leave

    /// Detach `cask` from Homebrew while preserving installed apps.
    ///
    /// - Parameters:
    ///   - cask: Cask inventory row.
    ///   - forceQuitRunning: When true, terminates running apps that match staged paths before leave.
    ///   - onProgress: Human-readable log lines for the operation sheet.
    public func leave(
        cask: BrewCask,
        forceQuitRunning: Bool = false,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> CaskLeaveResult {
        var messages: [String] = []

        let appPaths = Self.resolveInstalledAppPaths(
            appNames: cask.installedAppNames,
            searchPaths: applicationSearchPaths,
            fileManager: fileManager
        )

        // Orphaned or CLI-only: just drop the cask receipt.
        if appPaths.isEmpty {
            onProgress("No app bundle found for \(cask.token) — removing Homebrew record only…")
            messages.append("No app bundle found; uninstalling cask receipt only.")
            do {
                try await uninstall(cask.token)
            } catch {
                throw CaskLeaveError.uninstallFailed(message: error.localizedDescription)
            }
            onProgress("Left Homebrew: \(cask.token) (receipt removed).")
            messages.append("Cask \(cask.token) uninstalled from Homebrew.")
            return CaskLeaveResult(
                token: cask.token,
                preservedAppPaths: [],
                messages: messages
            )
        }

        let running = Self.runningApps(
            among: appPaths,
            runningPaths: runningAppPaths()
        )
        if !running.isEmpty {
            if forceQuitRunning {
                onProgress("Force-quitting: \(running.joined(separator: ", "))…")
                await quitApps(at: appPaths)
                // Re-check after quit attempt.
                let stillRunning = Self.runningApps(
                    among: appPaths,
                    runningPaths: runningAppPaths()
                )
                if !stillRunning.isEmpty {
                    throw CaskLeaveError.appsRunning(stillRunning)
                }
                messages.append("Force-quit: \(running.joined(separator: ", "))")
            } else {
                throw CaskLeaveError.appsRunning(running)
            }
        }

        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("pare-leave-\(cask.token)-\(UUID().uuidString)", isDirectory: true)

        onProgress("Staging \(appPaths.count) app(s) for \(cask.token)…")
        let pairs: [(original: URL, staged: URL)]
        do {
            pairs = try Self.stageApps(
                appPaths: appPaths,
                stagingRoot: stagingRoot,
                fileManager: fileManager
            )
        } catch let error as CaskLeaveError {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }

        for pair in pairs {
            onProgress("Staged \(pair.original.lastPathComponent)")
            messages.append("Staged \(pair.original.path)")
        }

        onProgress("Running brew uninstall --cask \(cask.token) (no zap)…")
        do {
            try await uninstall(cask.token)
            messages.append("brew uninstall --cask \(cask.token)")
        } catch {
            // Attempt to restore from stage even if uninstall failed.
            onProgress("Uninstall failed — restoring staged apps…")
            try? Self.restoreApps(pairs: pairs, fileManager: fileManager)
            try? fileManager.removeItem(at: stagingRoot)
            throw CaskLeaveError.uninstallFailed(message: error.localizedDescription)
        }

        onProgress("Restoring app(s) to original locations…")
        do {
            try Self.restoreApps(pairs: pairs, fileManager: fileManager)
        } catch let error as CaskLeaveError {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }

        try? fileManager.removeItem(at: stagingRoot)

        let preserved = pairs.map(\.original.path)
        for path in preserved {
            onProgress("Preserved \(path)")
            messages.append("Preserved \(path)")
        }
        onProgress("Left Homebrew: \(cask.token). App remains installed.")
        messages.append("Left Homebrew: \(cask.token)")

        return CaskLeaveResult(
            token: cask.token,
            preservedAppPaths: preserved,
            messages: messages
        )
    }

    // MARK: - Private

    @MainActor
    private func quitApps(at paths: [URL]) async {
        let targets = Set(paths.map { $0.standardizedFileURL.path })
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            guard let path = app.bundleURL?.standardizedFileURL.path else { return false }
            return targets.contains(path)
        }
        for app in apps {
            app.terminate()
        }
        // Brief wait for graceful quit.
        try? await Task.sleep(nanoseconds: 800_000_000)
        for app in apps where !app.isTerminated {
            app.forceTerminate()
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}
