import Foundation

/// Docker Desktop deep links; no Settings link is verified, so the button opens the dashboard.
public enum DockerDesktopLinks {
    public static let dashboard: [URL] = ["docker-desktop://dashboard/open"].compactMap(URL.init(string:))
}
