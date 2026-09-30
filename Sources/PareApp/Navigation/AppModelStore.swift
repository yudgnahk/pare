import Combine
import Foundation

/// App-level owner of every screen's view model.
///
/// Screens previously created their own `@StateObject` view models, and the
/// shell stamped `.id(selection)` on the detail pane — so every tab switch
/// destroyed the outgoing screen's state and re-ran its inventory scans.
/// Owning the models here keeps loaded lists, selections, and in-flight
/// operations alive across navigation. Construction is cheap: no model starts
/// scanning until its screen appears.
@MainActor
final class AppModelStore: ObservableObject {
    /// One coordinator for Smart Scan and the Disk Analyzer: one busy guard, and each refreshes after the other cleans.
    let cleanup: CleanupCoordinator
    let scan: ScanDashboardViewModel
    let history: HistoryViewModel
    let apps = AppManagerViewModel()
    let homebrew = HomebrewManagerViewModel()
    let maintenance = MaintenanceViewModel()
    lazy var disk = DiskAnalyzerViewModel(
        findingsProvider: { [scan] in scan.latestFindingsSnapshot },
        smartScanRunning: scan.$state.map { $0 == .scanning }.eraseToAnyPublisher(),
        coordinator: cleanup
    )

    /// Injectable so the DEBUG snapshot renderer can run on an engine that never touches real files.
    init(cleanup: CleanupCoordinator? = nil, history: HistoryViewModel? = nil) {
        let cleanup = cleanup ?? CleanupCoordinator()
        self.cleanup = cleanup
        self.scan = ScanDashboardViewModel(cleanup: cleanup)
        self.history = history ?? HistoryViewModel()
    }
}
