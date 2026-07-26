import SwiftUI
import Combine

/// User-controlled text zoom, Chrome-style.
///
/// - ⌘ + / ⌘ =  → zoom in
/// - ⌘ −       → zoom out
/// - ⌘ 0       → reset to 100%
///
/// Multiplies the window-size base scale. Preference is persisted.
@MainActor
final class TextZoomController: ObservableObject {
    /// Discrete steps from 85% to 200% (Chrome-like range).
    static let minFactor: CGFloat = 0.85
    static let maxFactor: CGFloat = 2.00
    static let step: CGFloat = 0.10
    static let defaultFactor: CGFloat = 1.0

    private static let storageKey = "pare.textZoom.factor"

    /// Multiplier applied on top of the automatic display scale (1.0 = 100%).
    @Published private(set) var factor: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(factor), forKey: Self.storageKey)
        }
    }

    /// Brief HUD when the user changes zoom via keyboard/menu.
    @Published var hudMessage: String?

    private var hudClearTask: Task<Void, Never>?

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.storageKey) as? Double
        let raw = CGFloat(stored ?? Double(Self.defaultFactor))
        self.factor = Self.clamp(Self.snap(raw))
    }

    var percentLabel: String {
        "\(Int((factor * 100).rounded()))%"
    }

    var canZoomIn: Bool { factor < Self.maxFactor - 0.001 }
    var canZoomOut: Bool { factor > Self.minFactor + 0.001 }

    func zoomIn() {
        guard canZoomIn else {
            showHUD("Maximum zoom (\(Int(Self.maxFactor * 100))%)")
            return
        }
        factor = Self.clamp(Self.snap(factor + Self.step))
        showHUD("Text size \(percentLabel)")
    }

    func zoomOut() {
        guard canZoomOut else {
            showHUD("Minimum zoom (\(Int(Self.minFactor * 100))%)")
            return
        }
        factor = Self.clamp(Self.snap(factor - Self.step))
        showHUD("Text size \(percentLabel)")
    }

    func reset() {
        factor = Self.defaultFactor
        showHUD("Text size \(percentLabel)")
    }

    // MARK: - Helpers

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(maxFactor, max(minFactor, value))
    }

    private static func snap(_ value: CGFloat) -> CGFloat {
        let steps = ((value - minFactor) / step).rounded()
        return minFactor + steps * step
    }

    private func showHUD(_ message: String) {
        hudMessage = message
        hudClearTask?.cancel()
        hudClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            if hudMessage == message {
                withAnimation(.easeOut(duration: 0.2)) {
                    hudMessage = nil
                }
            }
        }
    }
}

// MARK: - Commands (View menu + keyboard shortcuts)

struct TextZoomCommands: Commands {
    @ObservedObject var zoom: TextZoomController

    var body: some Commands {
        CommandMenu("View") {
            Button("Zoom In") { zoom.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!zoom.canZoomIn)

            Button("Zoom Out") { zoom.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!zoom.canZoomOut)

            Button("Actual Size") { zoom.reset() }
                .keyboardShortcut("0", modifiers: .command)

            Divider()

            Text("Text size: \(zoom.percentLabel)")
        }
    }
}

/// Invisible focus-independent shortcuts for ⌘= (zoom in without Shift)
/// and redundancy with the View menu commands.
struct TextZoomKeyMonitor: ViewModifier {
    @ObservedObject var zoom: TextZoomController

    func body(content: Content) -> some View {
        content
            // ⌘= — Chrome/Safari-style zoom-in without holding Shift for +
            .background(
                Button("") { zoom.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            )
    }
}

// MARK: - Zoom HUD overlay

struct TextZoomHUD: View {
    let message: String?
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        if let message {
            Text(message)
                .font(scale.font(14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.panel.opacity(0.92))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(AppTheme.Hairline.strong, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .allowsHitTesting(false)
        }
    }
}
