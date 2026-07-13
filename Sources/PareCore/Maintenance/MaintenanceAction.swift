import Foundation

/// Metadata for a single one-shot maintenance action.
/// No closures — execution lives in `MaintenanceRunner`.
public struct MaintenanceAction: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let systemImage: String
    /// Rough wall-clock estimate shown as a hint to the user.
    public let estimatedSeconds: Int
    public let requiresSudo: Bool

    public init(
        id: String,
        title: String,
        description: String,
        systemImage: String,
        estimatedSeconds: Int,
        requiresSudo: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.estimatedSeconds = estimatedSeconds
        self.requiresSudo = requiresSudo
    }
}

/// Static catalog of all available maintenance actions.
/// Docker prune is included here; the ViewModel filters it out when Docker is not running.
public enum MaintenanceCatalog {
    public static let flushDNS = MaintenanceAction(
        id: "flush-dns",
        title: "Flush DNS Cache",
        description: "Clears the system DNS resolver cache to fix stale or broken hostname lookups.",
        systemImage: "network.badge.shield.half.filled",
        estimatedSeconds: 2
    )

    public static let rebuildLaunchServices = MaintenanceAction(
        id: "rebuild-launch-services",
        title: "Rebuild Launch Services",
        description: "Rebuilds the Launch Services database to fix broken 'Open With' menus and default app assignments.",
        systemImage: "arrow.clockwise.circle",
        estimatedSeconds: 15
    )

    public static let restartFinder = MaintenanceAction(
        id: "restart-finder",
        title: "Restart Finder",
        description: "Kills and relaunches Finder to fix frozen icons, missing sidebar items, or layout glitches.",
        systemImage: "macwindow.badge.plus",
        estimatedSeconds: 3
    )

    public static let vacuumDatabases = MaintenanceAction(
        id: "vacuum-databases",
        title: "Vacuum SQLite Databases",
        description: "Reclaims wasted space in Mail, Safari, and Messages databases. Close those apps first.",
        systemImage: "cylinder.split.1x2",
        estimatedSeconds: 20
    )

    public static let dockerPrune = MaintenanceAction(
        id: "docker-prune",
        title: "Docker System Prune",
        description: "Runs `docker system prune -f` only: stopped containers, unused networks, dangling images, and dangling build cache. Never uses --volumes — named volumes and database data are left intact. Does not delete Docker.raw.",
        systemImage: "shippingbox.and.arrow.backward",
        estimatedSeconds: 30
    )

    /// Prefer this for routine reclaim: build cache older than 7 days only.
    public static let dockerBuilderPrune7d = MaintenanceAction(
        id: "docker-builder-prune-7d",
        title: "Docker Build Cache (>7 days)",
        description: "Runs `docker builder prune -f --filter until=168h`. Removes only image build cache older than 7 days. Safe default. Never touches volumes or Docker.raw.",
        systemImage: "cube.transparent",
        estimatedSeconds: 45
    )

    /// Aggressive option when the disk is critically low.
    public static let dockerBuilderPrune1d = MaintenanceAction(
        id: "docker-builder-prune-1d",
        title: "Docker Build Cache (>1 day, low space)",
        description: "Runs `docker builder prune -f --filter until=24h`. Use when free space is low. Keeps only the last day of build cache. Never uses --volumes.",
        systemImage: "exclamationmark.triangle",
        estimatedSeconds: 60
    )

    /// All actions. Docker prune is included; callers filter based on availability.
    public static let all: [MaintenanceAction] = [
        flushDNS,
        rebuildLaunchServices,
        restartFinder,
        vacuumDatabases,
        dockerPrune,
        dockerBuilderPrune7d,
        dockerBuilderPrune1d,
    ]
}
