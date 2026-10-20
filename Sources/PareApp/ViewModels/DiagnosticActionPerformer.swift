import AppKit
import PareCore

/// Carries out a diagnostic note's button. Every action only opens something; nothing is changed.
@MainActor
struct DiagnosticActionPerformer {
    static let activityMonitorBundleID = "com.apple.ActivityMonitor"

    var openFirst: ([URL]) -> Void = Self.openFirstAvailable
    var reveal: (String) -> Void
    /// Activity Monitor until the Processes tab can take a filter.
    var showProcesses: ([Int32]) -> Void = { _ in Self.openActivityMonitor() }

    func perform(_ action: DiagnosticAction) {
        switch action {
        case .showProcesses(let pids): showProcesses(pids)
        case .openLoginItems: openFirst(SystemSettingsLinks.loginItems)
        case .revealInFinder(let path): reveal(path)
        case .openICloudStorage: openFirst(SystemSettingsLinks.iCloudStorage)
        }
    }

    static func title(for action: DiagnosticAction) -> String {
        switch action {
        case .showProcesses: return "Activity Monitor"
        case .openLoginItems: return "Login Items"
        case .revealInFinder: return "Show in Finder"
        case .openICloudStorage: return "iCloud Storage"
        }
    }

    private static func openFirstAvailable(_ urls: [URL]) {
        for url in urls where NSWorkspace.shared.open(url) { return }
    }

    private static func openActivityMonitor() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: activityMonitorBundleID) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
