import SwiftUI

/// 사이드바 하단 퀵 인풋 — 마스터 에이전트에게 빠르게 메시지 전송
struct SidebarQuickInputView: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.caption2)
                    .foregroundColor(.purple)
                Text("빠른 질문")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }

            HStack(spacing: 4) {
                TextField("메시지 입력...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(isFocused ? 1...3 : 1...1)
                    .font(.caption)
                    .focused($isFocused)
                    .onSubmit { onSend() }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.body)
                        .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
        }
        .padding(8)
        .background(DesignTokens.Colors.overlay)
        .continuousRadius(DesignTokens.Radius.lg)
    }
}
