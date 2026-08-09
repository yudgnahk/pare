import Foundation

/// Lifecycle of an async data load, shared by manager view models
/// (Homebrew, App Manager). Equatable is synthesized.
enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}
