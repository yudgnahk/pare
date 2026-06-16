import XCTest
@testable import App BCore

final class ScanMetadataCacheTests: XCTestCase {

    private var tempCacheURL: URL!

    override func setUp() {
        super.setUp()
        tempCacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-cache-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempCacheURL)
        super.tearDown()
    }

    // MARK: - Cache miss

    func testCacheMissForUnknownDirectory() async {
        let cache = ScanMetadataCache(persistURL: tempCacheURL)
        let dir = URL(fileURLWithPath: "/tmp/unknown")
        let fresh = await cache.isFresh(directory: dir, currentMtime: Date())
        let files = await cache.cachedFiles(for: dir)
        XCTAssertFalse(fresh)
        XCTAssertNil(files)
    }

    // MARK: - Cache hit

    func testCacheHitWhenMtimeMatchesAndFilesAreStored() async {
        let cache = ScanMetadataCache(persistURL: tempCacheURL)
        let dir = URL(fileURLWithPath: "/tmp/mydir")
        let mtime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let stored = [ScannedFile(url: dir.appendingPathComponent("a.bin"), sizeBytes: 42, lastModified: nil)]

        await cache.store(directory: dir, mtime: mtime, files: stored)

        let fresh = await cache.isFresh(directory: dir, currentMtime: mtime)
        let cached = await cache.cachedFiles(for: dir)
        XCTAssertTrue(fresh)
        XCTAssertEqual(cached?.count, 1)
        XCTAssertEqual(cached?.first?.sizeBytes, 42)
    }

    // MARK: - Cache miss on mtime change

    func testCacheMissWhenMtimeChanged() async {
        let cache = ScanMetadataCache(persistURL: tempCacheURL)
        let dir = URL(fileURLWithPath: "/tmp/mydir")
        let oldMtime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let newMtime = Date(timeIntervalSinceReferenceDate: 2_000_000)

        await cache.store(directory: dir, mtime: oldMtime, files: [])

        let fresh = await cache.isFresh(directory: dir, currentMtime: newMtime)
        XCTAssertFalse(fresh)
    }

    // MARK: - Profile change invalidation

    func testProfileChangeInvalidatesAllEntries() async {
        let cache = ScanMetadataCache(persistURL: tempCacheURL)
        let dir = URL(fileURLWithPath: "/tmp/mydir")
        let mtime = Date(timeIntervalSinceReferenceDate: 1_000_000)

        await cache.setProfile("profile-a")
        await cache.store(directory: dir, mtime: mtime, files: [
            ScannedFile(url: dir.appendingPathComponent("x.bin"), sizeBytes: 100, lastModified: nil)
        ])

        let freshBefore = await cache.isFresh(directory: dir, currentMtime: mtime)
        XCTAssertTrue(freshBefore)

        await cache.setProfile("profile-b")

        let freshAfter = await cache.isFresh(directory: dir, currentMtime: mtime)
        let files = await cache.cachedFiles(for: dir)
        XCTAssertFalse(freshAfter)
        XCTAssertNil(files)
    }

    func testSameProfileDoesNotInvalidate() async {
        let cache = ScanMetadataCache(persistURL: tempCacheURL)
        let dir = URL(fileURLWithPath: "/tmp/mydir")
        let mtime = Date(timeIntervalSinceReferenceDate: 1_000_000)

        await cache.setProfile("profile-a")
        await cache.store(directory: dir, mtime: mtime, files: [])

        await cache.setProfile("profile-a")

        let fresh = await cache.isFresh(directory: dir, currentMtime: mtime)
        XCTAssertTrue(fresh)
    }

    // MARK: - Invalidate

    func testInvalidateClearsEverything() async {
        let cache = ScanMetadataCache(persistURL: tempCacheURL)
        let dir = URL(fileURLWithPath: "/tmp/mydir")
        let mtime = Date(timeIntervalSinceReferenceDate: 1_000_000)

        await cache.store(directory: dir, mtime: mtime, files: [])
        await cache.invalidate()

        let fresh = await cache.isFresh(directory: dir, currentMtime: mtime)
        let files = await cache.cachedFiles(for: dir)
        XCTAssertFalse(fresh)
        XCTAssertNil(files)
    }

    // MARK: - Persistence round-trip

    func testMtimeIndexSurvivesRestart() async {
        let mtime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let dir = URL(fileURLWithPath: "/tmp/persist-test")

        let cache1 = ScanMetadataCache(persistURL: tempCacheURL)
        await cache1.setProfile("developer")
        await cache1.store(directory: dir, mtime: mtime, files: [])

        // Simulates app restart — new instance loads from disk
        let cache2 = ScanMetadataCache(persistURL: tempCacheURL)
        let freshOnRestart = await cache2.isFresh(directory: dir, currentMtime: mtime)
        let filesOnRestart = await cache2.cachedFiles(for: dir)

        // mtime index is persisted → isFresh returns true
        XCTAssertTrue(freshOnRestart)
        // file cache is not persisted → nil until a traversal populates it
        XCTAssertNil(filesOnRestart)
    }

    func testProfileFingerprintSurvivesRestart() async {
        let cache1 = ScanMetadataCache(persistURL: tempCacheURL)
        await cache1.setProfile("developer")
        let dir = URL(fileURLWithPath: "/tmp/fp-test")
        let mtime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        await cache1.store(directory: dir, mtime: mtime, files: [])

        let cache2 = ScanMetadataCache(persistURL: tempCacheURL)
        await cache2.setProfile("developer")
        let freshAfterSameProfile = await cache2.isFresh(directory: dir, currentMtime: mtime)
        XCTAssertTrue(freshAfterSameProfile)

        await cache2.setProfile("designer")
        let freshAfterProfileSwitch = await cache2.isFresh(directory: dir, currentMtime: mtime)
        XCTAssertFalse(freshAfterProfileSwitch)
    }
}
