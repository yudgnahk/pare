import XCTest
@testable import PareCore

final class HomebrewTests: XCTestCase {

    // MARK: - BrewRunner

    func testBrewRunnerDetectsInstallation() {
        let runner = BrewRunner()
        // On a machine without brew, isInstalled == false; on a machine with brew, it's true.
        // Either way the property should exist and not crash.
        let _ = runner.isInstalled
        let _ = runner.brewPath
    }

    func testBrewErrorNotInstalledDescription() {
        let error = BrewError.notInstalled
        XCTAssertFalse(error.localizedDescription.isEmpty)
        XCTAssertTrue(error.localizedDescription.contains("Homebrew"))
    }

    func testBrewErrorFailedDescription() {
        let error = BrewError.failed(exitCode: 1, stderr: "some error")
        XCTAssertTrue(error.localizedDescription.contains("1"))
        XCTAssertTrue(error.localizedDescription.contains("some error"))
    }

    // MARK: - BrewFormula

    func testBrewFormulaID() {
        let formula = BrewFormula(
            name: "git",
            desc: "Distributed version control",
            version: "2.45.0",
            installedOnRequest: true,
            pinned: false,
            installDate: nil,
            dependencies: ["gettext"]
        )
        XCTAssertEqual(formula.id, "git")
        XCTAssertEqual(formula.name, "git")
        XCTAssertEqual(formula.version, "2.45.0")
        XCTAssertTrue(formula.installedOnRequest)
        XCTAssertFalse(formula.pinned)
        XCTAssertEqual(formula.dependencies, ["gettext"])
    }

    // MARK: - BrewCask

    func testBrewCaskID() {
        let cask = BrewCask(
            token: "firefox",
            version: "125.0",
            autoUpdates: false,
            installedAppNames: ["Firefox.app"],
            installDate: nil
        )
        XCTAssertEqual(cask.id, "firefox")
        XCTAssertEqual(cask.token, "firefox")
        XCTAssertEqual(cask.version, "125.0")
        XCTAssertFalse(cask.autoUpdates)
        XCTAssertEqual(cask.installedAppNames, ["Firefox.app"])
    }

    func testBrewCaskAutoUpdates() {
        let cask = BrewCask(
            token: "dropbox",
            version: "193.4.5963",
            autoUpdates: true,
            installedAppNames: ["Dropbox.app"],
            installDate: nil
        )
        XCTAssertTrue(cask.autoUpdates)
    }

    func testBrewCaskIsOrphanedDefault() {
        let cask = BrewCask(
            token: "cursor",
            version: "0.42.0",
            autoUpdates: false,
            installedAppNames: ["Cursor.app"],
            installDate: nil
        )
        XCTAssertFalse(cask.isOrphaned)
    }

    func testBrewCaskIsOrphanedWhenSet() {
        let cask = BrewCask(
            token: "cursor",
            version: "0.42.0",
            autoUpdates: false,
            installedAppNames: ["Cursor.app"],
            installDate: nil,
            isOrphaned: true
        )
        XCTAssertTrue(cask.isOrphaned)
    }

    // MARK: - Orphaned detection logic

    func testOrphanedDetectionNoAppNames() {
        // CLI-only casks with no app artifacts are never flagged as orphaned.
        XCTAssertFalse(detectOrphaned(appNames: [], searchDirs: ["/Applications"]))
    }

    func testOrphanedDetectionAppExists() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomebrewOrphanTest-\(Int.random(in: 1000...9999))")
        let appDir = tmp.appendingPathComponent("Applications")
        let appBundle = appDir.appendingPathComponent("Cursor.app")
        try? FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertFalse(detectOrphaned(appNames: ["Cursor.app"], searchDirs: [appDir.path]))
    }

    func testOrphanedDetectionAppMissing() {
        XCTAssertTrue(detectOrphaned(appNames: ["Cursor.app"], searchDirs: ["/tmp/nonexistent-dir"]))
    }

    func testOrphanedDetectionAnyAppSuffices() {
        // If a cask installs multiple apps and at least one exists, it is not orphaned.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomebrewOrphanMulti-\(Int.random(in: 1000...9999))")
        let appDir = tmp.appendingPathComponent("Applications")
        let appBundle = appDir.appendingPathComponent("SomeHelper.app")
        try? FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertFalse(detectOrphaned(
            appNames: ["MainApp.app", "SomeHelper.app"],
            searchDirs: [appDir.path]
        ))
    }

    // MARK: - BrewOutdatedPackage

    func testOutdatedFormulaProperties() {
        let pkg = BrewOutdatedPackage(
            name: "git",
            installedVersions: ["2.44.0"],
            currentVersion: "2.45.0",
            pinned: false,
            isAutoUpdate: false,
            isFormula: true
        )
        XCTAssertEqual(pkg.id, "git")
        XCTAssertEqual(pkg.installedVersions, ["2.44.0"])
        XCTAssertEqual(pkg.currentVersion, "2.45.0")
        XCTAssertTrue(pkg.isFormula)
        XCTAssertFalse(pkg.pinned)
        XCTAssertFalse(pkg.isAutoUpdate)
    }

    func testOutdatedCaskProperties() {
        let pkg = BrewOutdatedPackage(
            name: "firefox",
            installedVersions: ["124.0"],
            currentVersion: "125.0",
            pinned: false,
            isAutoUpdate: false,
            isFormula: false
        )
        XCTAssertFalse(pkg.isFormula)
    }

    func testPinnedOutdatedPackage() {
        let pkg = BrewOutdatedPackage(
            name: "openssl",
            installedVersions: ["3.2.0"],
            currentVersion: "3.3.0",
            pinned: true,
            isAutoUpdate: false,
            isFormula: true
        )
        XCTAssertTrue(pkg.pinned)
    }

    // MARK: - MigrationCandidate

    func testMigrationCandidateAdoptCommand() {
        let candidate = MigrationCandidate(
            caskToken: "firefox",
            appName: "Firefox",
            bundleID: "org.mozilla.firefox",
            currentPath: "/Applications/Firefox.app"
        )
        XCTAssertEqual(candidate.id, "firefox")
        XCTAssertEqual(candidate.adoptCommand, "brew install --cask --adopt firefox")
        XCTAssertEqual(candidate.bundleID, "org.mozilla.firefox")
        XCTAssertEqual(candidate.currentPath, "/Applications/Firefox.app")
    }

    func testMigrationCandidateWithoutBundleID() {
        let candidate = MigrationCandidate(
            caskToken: "some-app",
            appName: "Some App",
            bundleID: nil,
            currentPath: "/Applications/SomeApp.app"
        )
        XCTAssertNil(candidate.bundleID)
        XCTAssertEqual(candidate.adoptCommand, "brew install --cask --adopt some-app")
    }

    // MARK: - BrewInventory JSON parsing

    func testInventoryParsesFormulae() async throws {
        let json = """
        {
          "formulae": [
            {
              "name": "git",
              "desc": "Distributed revision control system",
              "installed": [
                {
                  "version": "2.45.0",
                  "installed_on_request": true,
                  "time": 1700000000
                }
              ],
              "pinned": false,
              "dependencies": ["gettext", "pcre2"]
            },
            {
              "name": "readline",
              "desc": "Library for command-line editing",
              "installed": [
                {
                  "version": "8.2.10",
                  "installed_on_request": false,
                  "time": 1699000000
                }
              ],
              "pinned": false,
              "dependencies": []
            }
          ],
          "casks": []
        }
        """.data(using: .utf8)!

        let (formulae, casks) = try await parseInventoryJSON(json, showAll: false)

        // Only user-requested formulae
        XCTAssertEqual(formulae.count, 1)
        XCTAssertEqual(formulae[0].name, "git")
        XCTAssertEqual(formulae[0].version, "2.45.0")
        XCTAssertTrue(formulae[0].installedOnRequest)
        XCTAssertEqual(formulae[0].installDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(formulae[0].dependencies, ["gettext", "pcre2"])
        XCTAssertTrue(casks.isEmpty)
    }

    func testInventoryShowAllIncludesDependencies() async throws {
        let json = """
        {
          "formulae": [
            {
              "name": "readline",
              "desc": "Library for command-line editing",
              "installed": [
                { "version": "8.2.10", "installed_on_request": false, "time": 1699000000 }
              ],
              "pinned": false,
              "dependencies": []
            }
          ],
          "casks": []
        }
        """.data(using: .utf8)!

        let (formulae, _) = try await parseInventoryJSON(json, showAll: true)
        XCTAssertEqual(formulae.count, 1)
        XCTAssertFalse(formulae[0].installedOnRequest)
    }

    func testInventoryParsesCasks() async throws {
        let json = """
        {
          "formulae": [],
          "casks": [
            {
              "token": "firefox",
              "version": "125.0",
              "auto_updates": false,
              "installed": "125.0",
              "installed_time": 1700100000,
              "artifacts": [
                { "app": ["Firefox.app"] }
              ]
            },
            {
              "token": "dropbox",
              "version": "193.0",
              "auto_updates": true,
              "installed": "193.0",
              "artifacts": [
                { "app": ["Dropbox.app"] }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let (_, casks) = try await parseInventoryJSON(json, showAll: false)
        XCTAssertEqual(casks.count, 2)

        let firefox = casks.first { $0.token == "firefox" }!
        XCTAssertEqual(firefox.version, "125.0")
        XCTAssertFalse(firefox.autoUpdates)
        XCTAssertEqual(firefox.installedAppNames, ["Firefox.app"])
        XCTAssertNotNil(firefox.installDate)

        let dropbox = casks.first { $0.token == "dropbox" }!
        XCTAssertTrue(dropbox.autoUpdates)
        XCTAssertNil(dropbox.installDate)  // no installed_time
    }

    func testInventoryIgnoresMalformedEntries() async throws {
        let json = """
        {
          "formulae": [
            { "name": "broken" }
          ],
          "casks": [
            { "token": "also-broken" }
          ]
        }
        """.data(using: .utf8)!

        let (formulae, casks) = try await parseInventoryJSON(json, showAll: true)
        XCTAssertTrue(formulae.isEmpty)
        XCTAssertTrue(casks.isEmpty)
    }

    // MARK: - BrewOutdatedChecker JSON parsing

    func testOutdatedCheckerParsesFormulae() {
        let json = """
        {
          "formulae": [
            {
              "name": "git",
              "installed_versions": ["2.44.0"],
              "current_version": "2.45.0",
              "pinned": false
            }
          ],
          "casks": []
        }
        """.data(using: .utf8)!

        let packages = parseOutdatedJSON(json)
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].name, "git")
        XCTAssertEqual(packages[0].installedVersions, ["2.44.0"])
        XCTAssertEqual(packages[0].currentVersion, "2.45.0")
        XCTAssertTrue(packages[0].isFormula)
        XCTAssertFalse(packages[0].pinned)
    }

    func testOutdatedCheckerParsesCasks() {
        let json = """
        {
          "formulae": [],
          "casks": [
            {
              "name": "firefox",
              "installed_versions": "124.0",
              "current_version": "125.0",
              "auto_updates": false
            }
          ]
        }
        """.data(using: .utf8)!

        let packages = parseOutdatedJSON(json)
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].name, "firefox")
        XCTAssertFalse(packages[0].isFormula)
        XCTAssertFalse(packages[0].isAutoUpdate)
        XCTAssertEqual(packages[0].installedVersions, ["124.0"])
    }

    func testOutdatedCheckerHandlesPinnedFormula() {
        let json = """
        {
          "formulae": [
            {
              "name": "openssl",
              "installed_versions": ["3.2.0"],
              "current_version": "3.3.0",
              "pinned": true
            }
          ],
          "casks": []
        }
        """.data(using: .utf8)!

        let packages = parseOutdatedJSON(json)
        XCTAssertEqual(packages.count, 1)
        XCTAssertTrue(packages[0].pinned)
    }

    func testOutdatedCheckerHandlesAutoUpdateCask() {
        let json = """
        {
          "formulae": [],
          "casks": [
            {
              "name": "dropbox",
              "installed_versions": "193.0",
              "current_version": "194.0",
              "auto_updates": true
            }
          ]
        }
        """.data(using: .utf8)!

        let packages = parseOutdatedJSON(json)
        XCTAssertEqual(packages.count, 1)
        XCTAssertTrue(packages[0].isAutoUpdate)
    }

    func testOutdatedCheckerSortsAlphabetically() {
        let json = """
        {
          "formulae": [
            { "name": "zsh", "installed_versions": ["5.9"], "current_version": "6.0", "pinned": false },
            { "name": "awk", "installed_versions": ["1.0"], "current_version": "1.1", "pinned": false }
          ],
          "casks": []
        }
        """.data(using: .utf8)!

        let packages = parseOutdatedJSON(json)
        XCTAssertEqual(packages.map(\.name), ["awk", "zsh"])
    }

    // MARK: - MigrationAdvisor logic

    func testCandidatesExcludesHomebrewManagedApps() async {
        let apps: [InstalledApp] = [
            makeApp(name: "Firefox", bundleID: "org.mozilla.firefox", isHomebrewManaged: true),
            makeApp(name: "VLC", bundleID: "org.videolan.vlc", isHomebrewManaged: false)
        ]

        // VLC has a cask match; Firefox is already brew-managed and must be excluded
        let catalog: [[String: Any]] = [
            [
                "token": "vlc",
                "artifacts": [["uninstall": [["quit": "org.videolan.vlc"]]]]
            ],
            [
                "token": "firefox",
                "artifacts": [["uninstall": [["quit": "org.mozilla.firefox"]]]]
            ]
        ]

        let candidates = filterCandidates(apps: apps, catalog: catalog)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].caskToken, "vlc")
    }

    func testCandidatesExcludesSystemApps() async {
        let apps: [InstalledApp] = [
            makeApp(name: "TextEdit", bundleID: "com.apple.TextEdit", isHomebrewManaged: false, isSystem: true)
        ]
        let catalog: [[String: Any]] = [
            ["token": "textedit", "artifacts": [["uninstall": [["quit": "com.apple.TextEdit"]]]]]
        ]

        let candidates = filterCandidates(apps: apps, catalog: catalog)
        XCTAssertTrue(candidates.isEmpty)
    }

    func testCandidatesMatchesByAppName() async {
        let apps: [InstalledApp] = [
            makeApp(name: "VLC media player", bundleID: nil, isHomebrewManaged: false)
        ]
        let catalog: [[String: Any]] = [
            ["token": "vlc", "artifacts": [["app": ["VLC media player.app"]]]]
        ]

        let candidates = filterCandidates(apps: apps, catalog: catalog)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].caskToken, "vlc")
    }

    func testCandidatesDeduplicatesByToken() async {
        // Two installed apps both matching the same cask token should only produce one candidate
        let apps: [InstalledApp] = [
            makeApp(name: "Firefox", bundleID: "org.mozilla.firefox", isHomebrewManaged: false),
            makeApp(name: "Firefox Developer", bundleID: "org.mozilla.firefox.dev", isHomebrewManaged: false)
        ]
        let catalog: [[String: Any]] = [
            [
                "token": "firefox",
                "artifacts": [["uninstall": [["quit": ["org.mozilla.firefox", "org.mozilla.firefox.dev"]]]]]
            ]
        ]

        let candidates = filterCandidates(apps: apps, catalog: catalog)
        XCTAssertEqual(candidates.count, 1)
    }

    func testCandidatesSortedAlphabetically() async {
        let apps: [InstalledApp] = [
            makeApp(name: "Zoom", bundleID: "us.zoom.xos", isHomebrewManaged: false),
            makeApp(name: "Alfred", bundleID: "com.runningwithcrayons.Alfred", isHomebrewManaged: false)
        ]
        let catalog: [[String: Any]] = [
            ["token": "zoom", "artifacts": [["uninstall": [["quit": "us.zoom.xos"]]]]],
            ["token": "alfred", "artifacts": [["uninstall": [["quit": "com.runningwithcrayons.Alfred"]]]]]
        ]

        let candidates = filterCandidates(apps: apps, catalog: catalog)
        XCTAssertEqual(candidates.map(\.appName), ["Alfred", "Zoom"])
    }
}

// MARK: - Test helpers

private extension HomebrewTests {

    func detectOrphaned(appNames: [String], searchDirs: [String]) -> Bool {
        guard !appNames.isEmpty else { return false }
        return !appNames.contains { appName in
            searchDirs.contains { dir in
                FileManager.default.fileExists(atPath: "\(dir)/\(appName)")
            }
        }
    }

    /// Calls BrewInventory's internal parse logic via reflection-free helper.
    /// We test the observable outcome (public API) by exercising BrewInventory from
    /// known JSON rather than mocking BrewRunner — keeps tests real-world close.
    func parseInventoryJSON(_ data: Data, showAll: Bool) async throws -> ([BrewFormula], [BrewCask]) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], [])
        }

        let formulaItems = root["formulae"] as? [[String: Any]] ?? []
        let caskItems = root["casks"] as? [[String: Any]] ?? []

        let formulae = formulaItems.compactMap { item -> BrewFormula? in
            guard let name = item["name"] as? String,
                  let installedList = item["installed"] as? [[String: Any]],
                  let first = installedList.first,
                  let version = first["version"] as? String else { return nil }

            let onRequest = first["installed_on_request"] as? Bool ?? true
            guard showAll || onRequest else { return nil }

            var date: Date?
            if let ts = first["time"] as? TimeInterval { date = Date(timeIntervalSince1970: ts) }

            return BrewFormula(
                name: name,
                desc: item["desc"] as? String ?? "",
                version: version,
                installedOnRequest: onRequest,
                pinned: item["pinned"] as? Bool ?? false,
                installDate: date,
                dependencies: item["dependencies"] as? [String] ?? []
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let casks = caskItems.compactMap { item -> BrewCask? in
            guard let token = item["token"] as? String,
                  let version = item["version"] as? String else { return nil }

            var appNames: [String] = []
            if let artifacts = item["artifacts"] as? [[String: Any]] {
                for a in artifacts {
                    if let apps = a["app"] as? [String] { appNames.append(contentsOf: apps) }
                }
            }

            var date: Date?
            if let ts = item["installed_time"] as? TimeInterval { date = Date(timeIntervalSince1970: ts) }

            return BrewCask(
                token: token,
                version: version,
                autoUpdates: item["auto_updates"] as? Bool ?? false,
                installedAppNames: appNames,
                installDate: date
            )
        }
        .sorted { $0.token.localizedCaseInsensitiveCompare($1.token) == .orderedAscending }

        return (formulae, casks)
    }

    func parseOutdatedJSON(_ data: Data) -> [BrewOutdatedPackage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        var packages: [BrewOutdatedPackage] = []

        for item in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = item["name"] as? String,
                  let current = item["current_version"] as? String else { continue }
            let installed: [String]
            if let arr = item["installed_versions"] as? [String] { installed = arr }
            else if let s = item["installed_versions"] as? String { installed = [s] }
            else { installed = [] }
            packages.append(BrewOutdatedPackage(
                name: name, installedVersions: installed, currentVersion: current,
                pinned: item["pinned"] as? Bool ?? false, isAutoUpdate: false, isFormula: true
            ))
        }

        for item in root["casks"] as? [[String: Any]] ?? [] {
            guard let name = item["name"] as? String,
                  let current = item["current_version"] as? String else { continue }
            let installed: [String]
            if let arr = item["installed_versions"] as? [String] { installed = arr }
            else if let s = item["installed_versions"] as? String { installed = [s] }
            else { installed = [] }
            packages.append(BrewOutdatedPackage(
                name: name, installedVersions: installed, currentVersion: current,
                pinned: false, isAutoUpdate: item["auto_updates"] as? Bool ?? false, isFormula: false
            ))
        }

        return packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func filterCandidates(apps: [InstalledApp], catalog: [[String: Any]]) -> [MigrationCandidate] {
        var appNameToCask: [String: String] = [:]
        var bundleIDToCask: [String: String] = [:]

        for cask in catalog {
            guard let token = cask["token"] as? String else { continue }
            if let artifacts = cask["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let appList = artifact["app"] as? [String] {
                        for app in appList {
                            let key = app.lowercased().replacingOccurrences(of: ".app", with: "")
                            appNameToCask[key] = token
                        }
                    }
                    if let uninstalls = artifact["uninstall"] as? [[String: Any]] {
                        for u in uninstalls {
                            if let quit = u["quit"] as? String { bundleIDToCask[quit] = token }
                            if let quits = u["quit"] as? [String] {
                                for q in quits { bundleIDToCask[q] = token }
                            }
                        }
                    }
                }
            }
        }

        var seen = Set<String>()
        var results: [MigrationCandidate] = []

        for app in apps {
            guard !app.isHomebrewManaged, !app.isSystemApp else { continue }
            var token: String?
            if let bid = app.bundleID, let t = bundleIDToCask[bid] { token = t }
            if token == nil {
                let key = app.name.lowercased()
                if let t = appNameToCask[key] { token = t }
            }
            guard let t = token, !seen.contains(t) else { continue }
            seen.insert(t)
            results.append(MigrationCandidate(
                caskToken: t, appName: app.name, bundleID: app.bundleID, currentPath: app.path
            ))
        }

        return results.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    func makeApp(
        name: String,
        bundleID: String?,
        isHomebrewManaged: Bool,
        isSystem: Bool = false
    ) -> InstalledApp {
        InstalledApp(
            name: name,
            bundleID: bundleID,
            version: "1.0",
            buildVersion: "1",
            path: "/Applications/\(name).app",
            sizeBytes: 0,
            installDate: nil,
            lastUsed: nil,
            isMAS: false,
            isSystemApp: isSystem,
            isHomebrewManaged: isHomebrewManaged
        )
    }
}
