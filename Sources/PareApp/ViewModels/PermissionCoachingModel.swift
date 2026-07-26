import AppKit
import Foundation
import PareCore

/// How to present empty-scan coaching when reclaimable bytes are ~0.
enum EmptyScanCoachingStyle: Equatable {
    /// Live probe still says FDA is denied.
    case likelyMissingFDA
    /// Last scan ran without FDA; access is now granted — user must rescan.
    case permissionsUpdatedNeedsRescan
    /// Scan had access (or unknown); nothing reclaimable matched.
    case genuinelyEmpty
}

/// Shared Full Disk Access state machine: live probe, banner dismissal
/// persistence, and System Settings deep link. Used by the scan dashboard and
/// Settings (previously two independent probes/observers).
@MainActor
final class PermissionCoachingModel: ObservableObject {
    /// Heuristic Full Disk Access status for coaching banners (live probe).
    @Published private(set) var status: FullDiskAccessStatus = .unknown
    /// Show FDA coaching when access looks missing and the user has not dismissed the card.
    @Published private(set) var showBanner: Bool = false
    /// FDA status observed when the last successful scan finished (not live).
    private(set) var statusAtLastScan: FullDiskAccessStatus = .unknown

    private static let bannerDismissedKey = "pare.fdaCoaching.dismissed"

    /// Re-probe Full Disk Access and update banner visibility.
    func refresh() {
        let status = FullDiskAccessChecker.status()
        self.status = status

        if status == .granted {
            UserDefaults.standard.removeObject(forKey: Self.bannerDismissedKey)
            showBanner = false
        } else if status == .denied {
            let dismissed = UserDefaults.standard.bool(forKey: Self.bannerDismissedKey)
            showBanner = !dismissed
        } else {
            showBanner = false
        }
    }

    func dismissBanner() {
        UserDefaults.standard.set(true, forKey: Self.bannerDismissedKey)
        showBanner = false
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access (best-effort).
    /// Clears the dismiss flag so coaching can reappear if the user returns without granting.
    func openSystemSettings() {
        UserDefaults.standard.removeObject(forKey: Self.bannerDismissedKey)
        for url in FullDiskAccessChecker.systemSettingsURLs {
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Snapshot FDA at scan finish so later grants can show "rescan needed"
    /// instead of a misleading clean-disk empty state.
    func snapshotStatusAfterScan() {
        statusAtLastScan = FullDiskAccessChecker.status()
    }

    /// Empty-scan coaching style derived from live status vs. status at last scan.
    func emptyScanStyle() -> EmptyScanCoachingStyle {
        if status == .denied {
            return .likelyMissingFDA
        }
        if statusAtLastScan == .denied, status == .granted {
            // Permissions flipped after a zero-byte pre-FDA scan — do not claim disk is clean.
            return .permissionsUpdatedNeedsRescan
        }
        return .genuinelyEmpty
    }
}
