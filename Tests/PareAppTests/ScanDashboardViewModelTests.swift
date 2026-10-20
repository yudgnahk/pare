import XCTest
import PareCore
@testable import PareApp

@MainActor
final class ScanDashboardViewModelTests: XCTestCase {

    /// Other view models (Disk Analyzer) read scan findings through this snapshot;
    /// it must start empty rather than crash before any scan has run.
    func testLatestFindingsSnapshotStartsEmpty() {
        let vm = ScanDashboardViewModel()
        XCTAssertTrue(vm.latestFindingsSnapshot.isEmpty)
    }

    func testInjectedCleanupCoordinatorIsUsed() {
        let coordinator = CleanupCoordinator()
        let vm = ScanDashboardViewModel(cleanup: coordinator)
        XCTAssertTrue(vm.cleanup === coordinator)
    }

    /// One coordinator means one busy guard across Smart Scan and the Disk Analyzer.
    func testAppModelStoreSharesOneCleanupCoordinator() {
        let store = AppModelStore()
        XCTAssertTrue(store.scan.cleanup === store.cleanup)
        XCTAssertTrue(store.disk.coordinator === store.cleanup)
    }

    /// A Disk Analyzer request must never be confirmed (or cancelled) through Smart Scan's selection path.
    func testDashboardCannotConfirmDiskReviewRequest() {
        let coordinator = CleanupCoordinator()
        let vm = ScanDashboardViewModel(cleanup: coordinator)
        coordinator.request(.diskReview)

        XCTAssertNil(vm.pendingCleanup)
        vm.confirmPendingCleanup()
        vm.cancelPendingCleanup()
        vm.pendingCleanup = nil

        XCTAssertEqual(coordinator.pending, .diskReview)
        XCTAssertEqual(coordinator.state, .confirming)
    }

    func testFinalizeStateCapsProgressAndRelabelsUntilResultsApply() {
        let vm = ScanDashboardViewModel()
        vm.applySnapshotScanning(step: 3, completed: 36, total: 36, title: "Last rule")
        XCTAssertFalse(vm.isFinalizingScan)
        XCTAssertEqual(vm.scanProgress, ScanDashboardViewModel.finalizingProgressCap, accuracy: 0.0001)

        vm.beginFinalizingScan()

        XCTAssertTrue(vm.isFinalizingScan)
        XCTAssertTrue(vm.isScanning)
        XCTAssertEqual(vm.scanStepTitle, "Preparing results…")
        XCTAssertEqual(vm.scanProgress, ScanDashboardViewModel.finalizingProgressCap, accuracy: 0.0001)
        XCTAssertLessThan(vm.scanProgress, 1.0)

        vm.applySnapshotResults(ScanReport(findings: [], summaries: []))

        XCTAssertFalse(vm.isFinalizingScan)
        XCTAssertEqual(vm.state, .success)
    }

    func testProgressNeverExceedsCapBeforeResultsApply() {
        let vm = ScanDashboardViewModel()
        vm.applySnapshotScanning(step: 1, completed: 0, total: 36, title: "First rule")
        var previous = vm.scanProgress
        for completed in 1...36 {
            vm.applyRuleProgress(completed: completed, total: 36, title: "Rule \(completed)")
            XCTAssertGreaterThanOrEqual(vm.scanProgress, previous)
            XCTAssertLessThanOrEqual(vm.scanProgress, ScanDashboardViewModel.finalizingProgressCap)
            previous = vm.scanProgress
        }
        vm.beginFinalizingScan()
        XCTAssertEqual(vm.scanProgress, previous, accuracy: 0.0001)
    }

    func testLateRuleCallbackAfterFinalizeIsIgnored() {
        let vm = ScanDashboardViewModel()
        vm.applySnapshotScanning(step: 3, completed: 35, total: 36, title: "Almost")
        vm.applyRuleProgress(completed: 36, total: 36, title: "Last rule")
        vm.beginFinalizingScan()

        vm.applyRuleProgress(completed: 36, total: 36, title: "Late rule")

        XCTAssertEqual(vm.scanStepTitle, ScanDashboardViewModel.finalizingTitle)
        XCTAssertEqual(vm.scanStep, 3)
        XCTAssertEqual(vm.scanProgress, ScanDashboardViewModel.finalizingProgressCap, accuracy: 0.0001)
    }

    func testCancelClearsFinalizeState() {
        let vm = ScanDashboardViewModel()
        vm.applySnapshotScanning(step: 3, completed: 36, total: 36, title: "Last rule")
        vm.beginFinalizingScan()

        vm.cancelScan()

        XCTAssertFalse(vm.isFinalizingScan)
        XCTAssertEqual(vm.scanProgress, 0)
    }

    func testScanProgressWithoutRulesIsZero() {
        XCTAssertEqual(ScanDashboardViewModel().scanProgress, 0)
    }

    /// The floating action bar must not look clickable while a (re)scan makes its requests no-ops.
    func testCleanupActionsEnabledOnlyAfterSuccessfulScanWhenIdle() {
        let cases: [(name: String, state: ScanDashboardViewModel.ScanState, cleaning: Bool, undoing: Bool, expected: Bool)] = [
            ("success", .success, false, false, true),
            ("scanning", .scanning, false, false, false),
            ("idle", .idle, false, false, false),
            ("success while cleaning", .success, true, false, false),
            ("success while undoing", .success, false, true, false),
        ]
        for testCase in cases {
            let result = ScanDashboardViewModel.cleanupActionsEnabled(
                state: testCase.state, isCleaning: testCase.cleaning, isUndoing: testCase.undoing
            )
            XCTAssertEqual(result, testCase.expected, testCase.name)
        }
    }

    func testCanRequestCleanupIsFalseWhileScanning() {
        let vm = ScanDashboardViewModel()
        XCTAssertFalse(vm.canRequestCleanup)

        vm.applySnapshotScanning(step: 1, completed: 0, total: 1, title: "Scanning")

        XCTAssertFalse(vm.canRequestCleanup)
    }

    /// Escape nils the sheet binding before `onDismiss` runs; the state must still return to idle.
    func testEscapeDismissResetsSmartScanRequestToIdle() {
        for kind in [PendingCleanup.quick, .deep, .selected] {
            let coordinator = CleanupCoordinator()
            let vm = ScanDashboardViewModel(cleanup: coordinator)
            coordinator.request(kind)
            XCTAssertEqual(vm.pendingCleanup, kind)

            vm.pendingCleanup = nil
            vm.cancelPendingCleanup()

            XCTAssertNil(coordinator.pending, "\(kind)")
            XCTAssertEqual(coordinator.state, .idle, "\(kind)")
        }
    }

    func testIncompleteRuleProducesPartialResultsWarning() {
        let report = ScanReport(
            findings: [],
            summaries: [],
            incompleteRules: [ScanIncompleteRule(
                ruleID: "project-artifacts-v2",
                ruleTitle: "Project Local Build Caches",
                message: "Stopped after 60 s, 3 of 9 project folders fully scanned."
            )]
        )

        let warnings = ScanDashboardViewModel.makeScanWarnings(from: report)

        XCTAssertEqual(warnings, [
            "Project Local Build Caches: scan incomplete, results are partial. Stopped after 60 s, 3 of 9 project folders fully scanned."
        ])
    }

    /// Explain-only diagnostics surface a short headline and their action in the app, not only in the CLI.
    func testDiagnosticNotesComeFromDiagnosticsOnly() {
        let diagnostic = ScanFinding(
            category: .diagnostics, riskLevel: .advanced, reason: "Desktop isn't backed up: 9.8 GB stuck — iCloud storage is full",
            path: "/Users/u/Library/Application Support/CloudDocs", sizeBytes: 0, lastUsed: nil, confidence: 0.8,
            annotations: [.explainOnly(action: "Free up iCloud storage"), .noteAction(.openICloudStorage)]
        )
        let cache = ScanFinding(
            category: .userCaches, riskLevel: .safe, reason: "cache",
            path: "/Users/u/Library/Caches/x", sizeBytes: 1_000, lastUsed: nil, confidence: 1
        )
        let vm = ScanDashboardViewModel()
        vm.applySnapshotResults(ScanReport(findings: [cache, diagnostic], summaries: []))

        XCTAssertEqual(vm.diagnosticNotes.map(\.headline), ["Desktop isn't backed up: 9.8 GB stuck"])
        XCTAssertEqual(vm.diagnosticNotes.first?.action, "Free up iCloud storage")
        XCTAssertEqual(vm.diagnosticNotes.first?.button, .openICloudStorage)
    }
}
