import AppKit
import PareCore
import SwiftUI
import UniformTypeIdentifiers

/// File menu: Export Diagnostics… — support JSON without full paths.
struct DiagnosticsExportCommands: Commands {
    @ObservedObject var scanViewModel: ScanDashboardViewModel

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export Diagnostics…") {
                exportDiagnostics()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }

    @MainActor
    private func exportDiagnostics() {
        let bundle = scanViewModel.makeDiagnosticsBundle()
        let data: Data
        do {
            data = try DiagnosticsExporter.jsonData(from: bundle)
        } catch {
            presentAlert(
                title: "Could not build diagnostics",
                message: error.localizedDescription
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName()
        panel.message = "Save a support-safe diagnostics report (no full file paths)"
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            presentAlert(
                title: "Could not save diagnostics",
                message: error.localizedDescription
            )
        }
    }

    private func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "pare-diagnostics-\(formatter.string(from: Date())).json"
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension ScanDashboardViewModel {
    /// Builds a support diagnostics bundle from the last scan using public dashboard state.
    /// Category totals only — no absolute paths (prefixes from top findings are anonymized).
    func makeDiagnosticsBundle() -> DiagnosticsBundle {
        let categorySummaries = summaries.map {
            DiagnosticsCategorySummary(
                category: $0.category.rawValue,
                reclaimableBytes: $0.reclaimableBytes,
                fileCount: $0.fileCount
            )
        }
        let findingCount = summaries.reduce(0) { $0 + $1.fileCount }

        // Approximate risk mix from the on-screen largest-items list (paths anonymized later).
        var safe = 0
        var review = 0
        var advanced = 0
        for item in topFindings {
            switch item.riskLevel {
            case .safe: safe += 1
            case .review: review += 1
            case .advanced: advanced += 1
            }
        }
        // When no top items but we have totals, leave risk zeros; category counts still ship.
        let risks = DiagnosticsRiskCounts(safe: safe, review: review, advanced: advanced)

        return DiagnosticsExporter.makeBundle(
            categorySummaries: categorySummaries,
            riskCounts: risks,
            profileUsed: "all",
            totalReclaimableBytes: totalReclaimableBytes,
            findingCount: findingCount,
            scanDate: lastScanDate,
            scanDurationSeconds: lastScanDuration,
            pathSamples: topFindings.map(\.path),
            ruleIds: RuleCatalog.all.map(\.id).sorted()
        )
    }
}
