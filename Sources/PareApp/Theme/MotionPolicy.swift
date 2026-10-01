import SwiftUI

/// Reduce Motion gate: travelling or looping motion becomes an instant state change.
enum MotionPolicy {
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// `withAnimation` that snaps instead of animating when Reduce Motion is on.
    static func perform(_ animation: Animation, reduceMotion: Bool, _ body: () -> Void) {
        if reduceMotion {
            body()
        } else {
            withAnimation(animation, body)
        }
    }
}

extension View {
    /// `.animation(_:value:)` that is skipped entirely under Reduce Motion.
    func motionAwareAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAwareAnimation(animation: animation, value: value))
    }
}

private struct MotionAwareAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(MotionPolicy.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}
