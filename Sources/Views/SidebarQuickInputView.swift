import SwiftUI

/// 사이드바 하단 퀵 인풋 — 마스터 에이전트에게 빠르게 메시지 전송
struct SidebarQuickInputView: View {
    @Environment(\.colorPalette) private var palette
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10))
                    .foregroundColor(palette.accent.opacity(0.6))
                Text("빠른 질문")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }

            HStack(spacing: 6) {
                TextField("메시지 입력...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(isFocused ? 1...3 : 1...1)
                    .font(.system(size: DesignTokens.FontSize.body, design: .rounded))
                    .focused($isFocused)
                    .onSubmit { onSend() }

                let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(canSend ? palette.accent : .secondary.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isLoading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.panelGradient)
        .continuousRadius(DesignTokens.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.12), lineWidth: 0.5)
        )
    }
}
