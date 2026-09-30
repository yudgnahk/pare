import SwiftUI

#if DEBUG
import AppKit
import PareCore

/// DEBUG-only: `PARE_SNAPSHOT_DIR=<dir> PareApp` renders key screens to PNG in light + dark, then quits.
@MainActor
enum SnapshotRenderer {
    static let environmentKey = "PARE_SNAPSHOT_DIR"
    private static let size = CGSize(width: 1240, height: 800)

    struct Scene {
        let name: String
        let destination: AppDestination
        /// Long enough for appear springs and count-ups to settle before capture.
        var settleSeconds: Double = 2.4
        var height: CGFloat = 800
        let prepare: @MainActor (AppModelStore) -> Void
    }

    static func runIfRequested() -> Bool {
        guard let dir = ProcessInfo.processInfo.environment[environmentKey] else { return false }
        PermissionCoachingModel.snapshotStatusOverride = .granted
        Task { @MainActor in
            await renderAll(to: URL(fileURLWithPath: dir, isDirectory: true))
            NSApp.terminate(nil)
        }
        return true
    }

    private static func renderAll(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let only = ProcessInfo.processInfo.environment["PARE_SNAPSHOT_ONLY"]?.split(separator: ",").map(String.init)
        for scene in scenes where only?.contains(where: { scene.name.hasPrefix($0) }) ?? true {
            for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let store = SnapshotFixtures.makeModelStore()
                scene.prepare(store)
                let url = directory.appendingPathComponent("\(scene.name)-\(suffix).png")
                await render(store: store, scene: scene, appearance: appearanceName, to: url)
            }
        }
    }

    private static func render(
        store: AppModelStore,
        scene: Scene,
        appearance: NSAppearance.Name,
        to url: URL
    ) async {
        let size = CGSize(width: Self.size.width, height: scene.height)
        let root = MainShellView(selection: .constant(scene.destination), models: store)
        let wrapped = DisplayScaleReader { root }
            .environmentObject(TextZoomController())
            .environment(\.isSnapshotRendering, true)
            .frame(width: size.width, height: size.height)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        let host = NSHostingView(rootView: wrapped)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()

        try? await Task.sleep(nanoseconds: UInt64(scene.settleSeconds * 1_000_000_000))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: rep)
        }
        if let data = rep.representation(using: .png, properties: [:]) {
            do {
                try data.write(to: url)
            } catch {
                NSLog("Snapshot write failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        window.orderOut(nil)
    }
}

// MARK: - Scenes

extension SnapshotRenderer {
    static var scenes: [Scene] {
        [
            Scene(name: "01-smart-scan-idle", destination: .smartScan) { _ in },
            Scene(name: "02-smart-scan-scanning", destination: .smartScan) { store in
                store.scan.applySnapshotScanning(step: 2, completed: 21, total: 36, title: "Browser caches…")
            },
            Scene(name: "03-smart-scan-results", destination: .smartScan) { store in
                store.scan.applySnapshotResults(SnapshotFixtures.scanReport)
            },
            Scene(name: "03b-smart-scan-results-full", destination: .smartScan, height: 1500) { store in
                store.scan.applySnapshotResults(SnapshotFixtures.scanReport)
            },
            Scene(name: "04-smart-scan-cleaned", destination: .smartScan) { store in
                store.scan.applySnapshotResults(SnapshotFixtures.scanReport)
                store.scan.cleanup.applySnapshotState(.done(bytesFreed: 12_884_901_888, skippedCount: 0))
            },
            Scene(name: "05-disk-analyzer-empty", destination: .disk) { _ in },
            Scene(name: "05b-disk-analyzer-folder", destination: .disk, settleSeconds: 5) { store in
                store.scan.applySnapshotResults(SnapshotFixtures.scanReport)
                store.disk.open(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            },
            Scene(name: "06-apps", destination: .apps, settleSeconds: 10) { _ in },
            Scene(name: "07-maintenance", destination: .maintenance) { _ in },
            Scene(name: "08-history", destination: .history) { store in
                store.history.applySnapshotTransactions(SnapshotFixtures.historyTransactions())
            },
            Scene(name: "09-settings", destination: .settings) { _ in },
            Scene(name: "10-homebrew", destination: .homebrew, settleSeconds: 10) { _ in }
        ]
    }
}
#endif

// MARK: - Environment flag (present in release so views compile unconditionally)

private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True only inside the DEBUG snapshot renderer; swaps live AppKit materials for opaque fills.
    var isSnapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}
