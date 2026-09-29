import SwiftUI
import PareCore

// MARK: - Clean confirmation copy

/// Shared heads-up when a clean is large enough that Spotlight may busy-update
/// (incremental FSEvents work — not a full index wipe).
private enum CleanConfirmationSpotlightWarning {
    static let message =
        "Large clean: Spotlight may update search indexes for a while. This is normal; Pare never deletes Spotlight’s store."
}

// MARK: - Clean confirmation configs

extension ScanDashboardView {
    var quickCleanConfig: CleanConfirmationSheet.Config {
        var lines: [CleanConfirmationSheet.InfoLine] = [
            .init(
                icon: "checkmark.shield.fill",
                color: AppTheme.success,
                text: "\(viewModel.quickCleanCandidatesCount) safe-risk file\(viewModel.quickCleanCandidatesCount == 1 ? "" : "s") will be moved to Trash."
            ),
            .init(
                icon: "exclamationmark.triangle",
                color: AppTheme.warning,
                text: "Review and Advanced findings are never touched."
            )
        ]
        if viewModel.quickCleanMayTriggerSpotlightWork {
            lines.append(.init(
                icon: "magnifyingglass",
                color: AppTheme.warning,
                text: CleanConfirmationSpotlightWarning.message
            ))
        }
        lines.append(.init(
            icon: "arrow.uturn.backward",
            color: AppTheme.accent,
            text: "Undo is available immediately after cleanup."
        ))
        lines.append(.init(
            icon: "externaldrive",
            color: AppTheme.textSecondary,
            text: "Estimated space: \(viewModel.formattedBytes(viewModel.quickCleanCandidatesBytes))"
        ))

        return .init(
            title: "Quick Clean",
            subtitle: "Safe-risk findings only",
            headerIcon: "trash.fill",
            headerTint: AppTheme.success,
            infoLines: lines,
            size: .init(minHeight: 320, idealHeight: 360)
        )
    }

    var deepCleanConfig: CleanConfirmationSheet.Config {
        var lines: [CleanConfirmationSheet.InfoLine] = [
            .init(
                icon: "bolt.fill",
                color: AppTheme.review,
                text: "\(viewModel.deepCleanCandidatesCount) file\(viewModel.deepCleanCandidatesCount == 1 ? "" : "s") will be moved to Trash (\(viewModel.reviewRiskCandidatesCount) review-risk)."
            ),
            .init(
                icon: "exclamationmark.shield",
                color: AppTheme.warning,
                text: "ADVANCED findings (e.g. Docker VM data) are never touched."
            )
        ]
        if viewModel.deepCleanMayTriggerSpotlightWork {
            lines.append(.init(
                icon: "magnifyingglass",
                color: AppTheme.warning,
                text: CleanConfirmationSpotlightWarning.message
            ))
        }
        lines.append(.init(
            icon: "arrow.uturn.backward",
            color: AppTheme.accent,
            text: "You can undo immediately after cleanup via the Undo button."
        ))
        lines.append(.init(
            icon: "externaldrive",
            color: AppTheme.textSecondary,
            text: "Estimated space: \(viewModel.formattedBytes(viewModel.deepCleanCandidatesBytes))"
        ))

        return .init(
            title: "Deep Clean",
            subtitle: "Safe + Review-risk findings",
            subtitleColor: AppTheme.review,
            headerIcon: "bolt.fill",
            headerTint: AppTheme.review,
            warningText: "Deep Clean includes REVIEW-risk items. They may need app reconfiguration; review them before continuing.",
            infoLines: lines,
            confirmTint: AppTheme.review,
            confirmForeground: AppTheme.onAccent,
            size: .init(
                minWidth: 420,
                idealWidth: 480,
                maxWidth: AppTheme.Sheet.wideWidth,
                minHeight: 380,
                idealHeight: 420,
                maxHeight: 560
            )
        )
    }

    var selectedCleanConfig: CleanConfirmationSheet.Config {
        var lines: [CleanConfirmationSheet.InfoLine] = [
            .init(
                icon: "checkmark.circle",
                color: AppTheme.success,
                text: "\(viewModel.selectedCandidatesCount) item(s) · \(viewModel.formattedBytes(viewModel.selectedCandidatesBytes))"
            )
        ]
        if viewModel.selectedReviewCount > 0 {
            lines.append(.init(
                icon: "exclamationmark.triangle",
                color: AppTheme.warning,
                text: "\(viewModel.selectedReviewCount) REVIEW item(s) — may include browser Local Storage or similar site data."
            ))
        }
        if viewModel.selectedCleanMayTriggerSpotlightWork {
            lines.append(.init(
                icon: "magnifyingglass",
                color: AppTheme.warning,
                text: CleanConfirmationSpotlightWarning.message
            ))
        }
        lines.append(.init(
            icon: "arrow.uturn.backward",
            color: AppTheme.accent,
            text: "Items move to Trash. Undo is available after cleanup."
        ))

        return .init(
            title: "Clean selected",
            subtitle: "Only items you checked",
            headerIcon: "checkmark.circle.fill",
            headerTint: AppTheme.accent,
            infoLines: lines
        )
    }
}
