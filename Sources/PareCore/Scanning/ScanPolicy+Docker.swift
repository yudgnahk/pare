import Foundation

// MARK: - Docker safety policy (R1.7 split)
// See docs/features/docker-safety.md — Docker.raw / the vms tree is never a cache.

extension ScanPolicy {

    /// Docker Desktop log paths only (not the VM disk). Used by review/safe log rules.
    /// Never include `…/data/vms` here — that tree is the VM disk image (images, containers, volumes).
    public static let developerDockerReviewPathMarkers = [
        "/library/containers/com.docker.docker/data/log",
        "/library/group containers/group.com.docker/log",
    ]

    public static let developerDockerSafePathMarkers: [String] = [
        "/library/containers/com.docker.docker/data/log",
        "/library/containers/com.docker.docker/data/lifecycle-server.log",
        "/library/group containers/group.com.docker/log",
    ]

    /// Docker VM disk area — detect-only. Contains images, containers, build cache, AND volumes
    /// (e.g. Postgres data). Never delete via filesystem; never treat as normal cache.
    /// Prefer `isDockerNeverDeletePath` over matching these markers for cleanup.
    public static let developerDockerAdvancedPathMarkers: [String] = [
        "/library/containers/com.docker.docker/data/vms/0/data/docker.raw",
        "/library/containers/com.docker.docker/data/vms/0/data/",
        "/library/containers/com.docker.docker/data/vms/",
    ]

    /// `true` for Docker Desktop VM disk paths (`Docker.raw` and the `vms/…/data` tree).
    /// These must never be moved to Trash by Pare — reclaim space only via Docker CLI
    /// (`docker system prune` / `builder prune`) **without** `--volumes`.
    public static func isDockerNeverDeletePath(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        // Entire VM disk payload (not daemon logs under Data/log).
        if path.contains("/library/containers/com.docker.docker/data/vms/") {
            return true
        }
        if path.hasSuffix("/docker.raw") || path.contains("/docker.raw/") {
            return true
        }
        return false
    }
}
