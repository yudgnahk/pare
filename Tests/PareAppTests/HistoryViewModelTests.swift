import XCTest
import PareCore
@testable import PareApp

@MainActor
final class HistoryViewModelTests: XCTestCase {

    private var storeDir: URL!
    private var store: CleanupTransactionStore!

    override func setUpWithError() throws {
        storeDir = FileManager.default.temporaryDirectory
            .appending(path: "HistoryViewModelTests-\(UUID().uuidString)")
        store = CleanupTransactionStore(directory: storeDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDir)
    }

    private func makeTransaction(
        secondsAgo: TimeInterval,
        profileName: String = "test"
    ) -> CleanupTransaction {
        CleanupTransaction(
            timestamp: Date().addingTimeInterval(-secondsAgo),
            profileName: profileName,
            isDryRun: false,
            items: [
                CleanupItem(
                    originalPath: "/Users/test/Library/Caches/x.bin",
                    trashedPath: nil,
                    sizeBytes: 1024,
                    reason: "Test",
                    riskLevel: .safe
                ),
            ]
        )
    }

    // MARK: - Loading

    func testInitLoadsTransactionsNewestFirst() throws {
        try store.save(makeTransaction(secondsAgo: 3600, profileName: "older"))
        try store.save(makeTransaction(secondsAgo: 60, profileName: "newer"))

        let vm = HistoryViewModel(store: store)

        XCTAssertEqual(vm.transactions.map(\.profileName), ["newer", "older"])
    }

    func testLoadWithEmptyStoreYieldsNoTransactions() {
        let vm = HistoryViewModel(store: store)
        XCTAssertTrue(vm.transactions.isEmpty)
    }

    // MARK: - Clear

    func testClearAllEmptiesStoreAndMemory() throws {
        try store.save(makeTransaction(secondsAgo: 60))
        let vm = HistoryViewModel(store: store)
        XCTAssertEqual(vm.transactions.count, 1)

        vm.clearAll()

        XCTAssertTrue(vm.transactions.isEmpty)
        XCTAssertTrue(try store.loadAll().isEmpty)
    }

    // MARK: - Restore failure surfaces an error

    func testRestoreItemWithoutTrashPathSetsErrorMessage() async {
        let vm = HistoryViewModel(store: store)
        let item = CleanupItem(
            originalPath: "/Users/test/Library/Caches/ghost.bin",
            trashedPath: nil,  // dry-run item — cannot be restored
            sizeBytes: 10,
            reason: "Test",
            riskLevel: .safe
        )

        await vm.restoreItem(item)

        XCTAssertNil(vm.restoringItemID)
        let message = vm.errorMessage
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("ghost.bin") == true, message ?? "nil")
    }

    // MARK: - Formatting

    func testFormattedBytesUsesFileStyleUnits() {
        let vm = HistoryViewModel(store: store)
        let formatted = vm.formattedBytes(1_048_576)
        XCTAssertTrue(formatted.contains("MB"), formatted)
    }

    func testFormattedDateIsNonEmptyAndStable() {
        let vm = HistoryViewModel(store: store)
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let first = vm.formattedDate(date)
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, vm.formattedDate(date))
    }
}
