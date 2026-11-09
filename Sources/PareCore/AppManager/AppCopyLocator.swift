import AppKit
import Foundation

/// Finds every installed copy of an app by bundle ID, including those App Manager's inventory misses.
public protocol AppCopyLocating: Sendable {
    func appURLs(forBundleID bundleID: String) -> [URL]
}

/// LaunchServices sees apps in `/Applications` subfolders and elsewhere, even when Spotlight is off.
public struct LaunchServicesAppCopyLocator: AppCopyLocating {
    public init() {}

    public func appURLs(forBundleID bundleID: String) -> [URL] {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
    }
}
