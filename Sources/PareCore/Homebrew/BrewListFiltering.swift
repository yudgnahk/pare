import Foundation

/// Pure filter/sort predicates for the Homebrew manager lists.
/// Lives next to `BrewBulkPlanning` so PareCore tests can cover list
/// presentation logic without a PareApp test target.
public enum BrewListFiltering {

    public enum FormulaSortField: String, CaseIterable, Sendable {
        case name = "Name"
        case size = "Size"
        case installed = "Installed"
    }

    /// Case-insensitive name/description search + configurable sort.
    public static func filterFormulae(
        _ formulae: [BrewFormula],
        search: String,
        sortField: FormulaSortField,
        ascending: Bool
    ) -> [BrewFormula] {
        var result = formulae
        if !search.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(search)
                    || $0.desc.localizedCaseInsensitiveContains(search)
            }
        }
        result.sort { a, b in
            let orderedAscending: Bool
            switch sortField {
            case .name:
                orderedAscending = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .size:
                orderedAscending = a.sizeBytes < b.sizeBytes
            case .installed:
                orderedAscending = (a.installDate ?? .distantPast) < (b.installDate ?? .distantPast)
            }
            return ascending ? orderedAscending : !orderedAscending
        }
        return result
    }

    /// Token/app-name search; orphaned casks float to the top so they are
    /// immediately visible, then alphabetical by token.
    public static func filterCasks(_ casks: [BrewCask], search: String) -> [BrewCask] {
        let base: [BrewCask]
        if search.isEmpty {
            base = casks
        } else {
            base = casks.filter {
                $0.token.localizedCaseInsensitiveContains(search)
                    || $0.installedAppNames.contains { $0.localizedCaseInsensitiveContains(search) }
            }
        }
        return base.sorted { a, b in
            if a.isOrphaned != b.isOrphaned { return a.isOrphaned }
            return a.token.localizedCaseInsensitiveCompare(b.token) == .orderedAscending
        }
    }

    /// Name search over outdated packages (input order preserved).
    public static func filterOutdated(
        _ packages: [BrewOutdatedPackage],
        search: String
    ) -> [BrewOutdatedPackage] {
        guard !search.isEmpty else { return packages }
        return packages.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    /// App-name/cask-token search over migration candidates (input order preserved).
    public static func filterMigrationCandidates(
        _ candidates: [MigrationCandidate],
        search: String
    ) -> [MigrationCandidate] {
        guard !search.isEmpty else { return candidates }
        return candidates.filter {
            $0.appName.localizedCaseInsensitiveContains(search)
                || $0.caskToken.localizedCaseInsensitiveContains(search)
        }
    }

    /// Outdated packages that `brew upgrade` (non-greedy) will touch.
    /// Self-updating casks are excluded — they update themselves.
    public static func brewManagedOutdated(
        _ packages: [BrewOutdatedPackage]
    ) -> [BrewOutdatedPackage] {
        packages.filter { $0.isFormula || !$0.isAutoUpdate }
    }

    /// Self-updating casks visible via greedy outdated discovery.
    public static func autoUpdateOutdated(
        _ packages: [BrewOutdatedPackage]
    ) -> [BrewOutdatedPackage] {
        packages.filter { !$0.isFormula && $0.isAutoUpdate }
    }
}
