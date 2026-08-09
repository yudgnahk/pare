import XCTest
@testable import PareCore

final class BrewListFilteringTests: XCTestCase {

    // MARK: - Fixtures

    private func formula(
        _ name: String,
        desc: String = "",
        sizeBytes: Int64 = 0,
        installDate: Date? = nil
    ) -> BrewFormula {
        BrewFormula(
            name: name,
            desc: desc,
            version: "1.0",
            installedOnRequest: true,
            pinned: false,
            installDate: installDate,
            dependencies: [],
            sizeBytes: sizeBytes
        )
    }

    private func cask(_ token: String, apps: [String] = [], orphaned: Bool = false) -> BrewCask {
        BrewCask(
            token: token,
            version: "1.0",
            autoUpdates: false,
            installedAppNames: apps,
            installDate: nil,
            isOrphaned: orphaned
        )
    }

    private func outdated(
        _ name: String,
        isFormula: Bool = true,
        isAutoUpdate: Bool = false,
        pinned: Bool = false
    ) -> BrewOutdatedPackage {
        BrewOutdatedPackage(
            name: name,
            installedVersions: ["1.0"],
            currentVersion: "2.0",
            pinned: pinned,
            isAutoUpdate: isAutoUpdate,
            isFormula: isFormula
        )
    }

    private func candidate(_ token: String, appName: String) -> MigrationCandidate {
        MigrationCandidate(caskToken: token, appName: appName, bundleID: nil, currentPath: "/Applications/\(appName).app")
    }

    // MARK: - Formulae

    func testFilterFormulaeMatchesNameAndDescriptionCaseInsensitively() {
        let input = [
            formula("wget", desc: "Internet file retriever"),
            formula("jq", desc: "JSON processor"),
            formula("ripgrep", desc: "Search tool like grep"),
        ]
        let byName = BrewListFiltering.filterFormulae(input, search: "WGET", sortField: .name, ascending: true)
        XCTAssertEqual(byName.map(\.name), ["wget"])

        let byDesc = BrewListFiltering.filterFormulae(input, search: "json", sortField: .name, ascending: true)
        XCTAssertEqual(byDesc.map(\.name), ["jq"])
    }

    func testFilterFormulaeSortsByEachField() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let input = [
            formula("beta", sizeBytes: 300, installDate: newer),
            formula("alpha", sizeBytes: 100, installDate: nil),
            formula("gamma", sizeBytes: 200, installDate: older),
        ]

        let byNameAsc = BrewListFiltering.filterFormulae(input, search: "", sortField: .name, ascending: true)
        XCTAssertEqual(byNameAsc.map(\.name), ["alpha", "beta", "gamma"])

        let bySizeDesc = BrewListFiltering.filterFormulae(input, search: "", sortField: .size, ascending: false)
        XCTAssertEqual(bySizeDesc.map(\.name), ["beta", "gamma", "alpha"])

        // nil installDate sorts as distantPast (oldest first when ascending).
        let byInstalledAsc = BrewListFiltering.filterFormulae(input, search: "", sortField: .installed, ascending: true)
        XCTAssertEqual(byInstalledAsc.map(\.name), ["alpha", "gamma", "beta"])
    }

    // MARK: - Casks

    func testFilterCasksFloatsOrphanedToTopThenAlphabetical() {
        let input = [
            cask("zulu"),
            cask("firefox", orphaned: true),
            cask("alacritty"),
            cask("iterm2", orphaned: true),
        ]
        let result = BrewListFiltering.filterCasks(input, search: "")
        XCTAssertEqual(result.map(\.token), ["firefox", "iterm2", "alacritty", "zulu"])
    }

    func testFilterCasksMatchesTokenOrInstalledAppName() {
        let input = [
            cask("visual-studio-code", apps: ["Visual Studio Code.app"]),
            cask("firefox", apps: ["Firefox.app"]),
        ]
        let byToken = BrewListFiltering.filterCasks(input, search: "studio")
        XCTAssertEqual(byToken.map(\.token), ["visual-studio-code"])

        let byApp = BrewListFiltering.filterCasks(input, search: "firefox.APP")
        XCTAssertEqual(byApp.map(\.token), ["firefox"])
    }

    // MARK: - Outdated

    func testFilterOutdatedByNamePreservesOrder() {
        let input = [outdated("node"), outdated("nodemon"), outdated("go")]
        XCTAssertEqual(
            BrewListFiltering.filterOutdated(input, search: "node").map(\.name),
            ["node", "nodemon"]
        )
        XCTAssertEqual(BrewListFiltering.filterOutdated(input, search: "").count, 3)
    }

    func testBrewManagedVsAutoUpdatePartition() {
        let input = [
            outdated("wget", isFormula: true, isAutoUpdate: false),
            outdated("slack", isFormula: false, isAutoUpdate: true),
            outdated("firefox", isFormula: false, isAutoUpdate: false),
        ]
        XCTAssertEqual(
            BrewListFiltering.brewManagedOutdated(input).map(\.name),
            ["wget", "firefox"]
        )
        XCTAssertEqual(
            BrewListFiltering.autoUpdateOutdated(input).map(\.name),
            ["slack"]
        )
    }

    // MARK: - Migration candidates

    func testFilterMigrationCandidatesMatchesAppNameOrToken() {
        let input = [
            candidate("visual-studio-code", appName: "Visual Studio Code"),
            candidate("rectangle", appName: "Rectangle"),
        ]
        XCTAssertEqual(
            BrewListFiltering.filterMigrationCandidates(input, search: "rect").map(\.caskToken),
            ["rectangle"]
        )
        XCTAssertEqual(
            BrewListFiltering.filterMigrationCandidates(input, search: "visual").map(\.caskToken),
            ["visual-studio-code"]
        )
        XCTAssertEqual(BrewListFiltering.filterMigrationCandidates(input, search: "").count, 2)
    }
}
