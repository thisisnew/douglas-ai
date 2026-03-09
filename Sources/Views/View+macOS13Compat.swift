import SwiftUI

// MARK: - macOS 13 Compatibility Extensions

extension View {
    /// Applies keyboard navigation for selection cards on macOS 14+.
    /// On macOS 13, keyboard navigation is not available (mouse/click still works).
    @ViewBuilder
    func keyboardNavigationCompat(
        selectedIndex: Binding<Int>,
        itemCount: Int,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            self
                .onKeyPress(.upArrow) {
                    selectedIndex.wrappedValue = max(0, selectedIndex.wrappedValue - 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    selectedIndex.wrappedValue = min(itemCount - 1, selectedIndex.wrappedValue + 1)
                    return .handled
                }
                .onKeyPress(.return) {
                    onSelect(selectedIndex.wrappedValue)
                    return .handled
                }
                .onKeyPress(characters: .decimalDigits) { press in
                    if let num = Int(press.characters), num >= 1, num <= itemCount {
                        onSelect(num - 1)
                        return .handled
                    }
                    return .ignored
                }
        } else {
            // macOS 13: keyboard navigation not available, click/mouse works
            self
        }
    }

    /// phaseAnimator wrapper for macOS 13 compatibility.
    /// On macOS 14+, applies pulse animation. On macOS 13, shows repeating opacity animation.
    @ViewBuilder
    func pulseAnimatorCompat() -> some View {
        if #available(macOS 14.0, *) {
            self.phaseAnimator([false, true]) { content, phase in
                content.opacity(phase ? 1.0 : 0.5)
            } animation: { _ in
                .easeInOut(duration: 1.2)
            }
        } else {
            // macOS 13 fallback: simple repeating opacity animation
            self.modifier(PulseAnimationModifier())
        }
    }
}

// MARK: - macOS 13 Fallback Pulse Animation

/// A modifier that creates a pulsing opacity effect using classic animation APIs (macOS 13 compatible)
private struct PulseAnimationModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}
