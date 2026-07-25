import Foundation

/// Pure helpers for Homebrew bulk-action planning and batch result aggregation.
/// Kept free of UI so PareCore tests can cover US-7 command construction and
/// partial-failure summary math without a PareApp test target.
public enum BrewBulkPlanning {

    public enum BatchOutcome: Equatable {
        case succeeded
        case partiallySucceeded
        case failed
    }

    /// Homebrew argv for upgrading a single outdated package (no `brew` prefix).
    public static func upgradeArgs(for package: BrewOutdatedPackage) -> [String] {
        package.isFormula
            ? ["upgrade", package.name]
            : ["upgrade", "--cask", package.name]
    }

    /// Uninstall argv for a formula.
    public static func uninstallFormulaArgs(name: String) -> [String] {
        ["uninstall", name]
    }

    /// Uninstall argv for a cask.
    public static func uninstallCaskArgs(token: String) -> [String] {
        ["uninstall", "--cask", token]
    }

    /// Adopt argv for a migration candidate.
    public static func adoptArgs(caskToken: String) -> [String] {
        ["install", "--cask", "--adopt", caskToken]
    }

    /// Packages that can actually be upgraded (excludes pinned).
    public static func upgradeablePackages(
        from packages: [BrewOutdatedPackage]
    ) -> [BrewOutdatedPackage] {
        packages.filter { !$0.pinned }
    }

    /// IDs safe to include in outdated multi-select (excludes pinned).
    public static func selectableOutdatedIDs(
        from packages: [BrewOutdatedPackage]
    ) -> [String] {
        upgradeablePackages(from: packages).map(\.id)
    }

    /// Human-readable batch summary and outcome from success/failure counts.
    public static func batchResult(
        successes: Int,
        failures: Int
    ) -> (summary: String, outcome: BatchOutcome) {
        precondition(successes >= 0 && failures >= 0)
        if failures == 0 {
            return ("Completed \(successes) item(s).", .succeeded)
        }
        if successes == 0 {
            return ("Completed 0 item(s); \(failures) failed.", .failed)
        }
        return (
            "Completed \(successes) item(s); \(failures) failed.",
            .partiallySucceeded
        )
    }

    /// Preview lines for confirmation UI: `"brew …"` strings, capped with remainder.
    public static func commandPreviewLines(
        commands: [[String]],
        maxVisible: Int = 5
    ) -> [String] {
        guard !commands.isEmpty else { return [] }
        let visible = commands.prefix(max(1, maxVisible)).map { args in
            "brew \(args.joined(separator: " "))"
        }
        let remainder = commands.count - visible.count
        if remainder > 0 {
            return visible + ["… and \(remainder) more"]
        }
        return Array(visible)
    }

    /// Pattern summary for mixed multi-item batches (e.g. upgrade formula vs cask).
    public static func commandPatternSummary(commands: [[String]]) -> String? {
        guard commands.count > 1 else { return nil }
        var formulaUpgrades = 0
        var caskUpgrades = 0
        var formulaUninstalls = 0
        var caskUninstalls = 0
        var adopts = 0
        var other = 0

        for args in commands {
            switch args.first {
            case "upgrade" where args.contains("--cask"):
                caskUpgrades += 1
            case "upgrade":
                formulaUpgrades += 1
            case "uninstall" where args.contains("--cask"):
                caskUninstalls += 1
            case "uninstall":
                formulaUninstalls += 1
            case "install" where args.contains("--adopt"):
                adopts += 1
            default:
                other += 1
            }
        }

        var parts: [String] = []
        if formulaUpgrades > 0 { parts.append("\(formulaUpgrades)× upgrade formula") }
        if caskUpgrades > 0 { parts.append("\(caskUpgrades)× upgrade --cask") }
        if formulaUninstalls > 0 { parts.append("\(formulaUninstalls)× uninstall formula") }
        if caskUninstalls > 0 { parts.append("\(caskUninstalls)× uninstall --cask") }
        if adopts > 0 { parts.append("\(adopts)× adopt") }
        if other > 0 { parts.append("\(other)× other") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
