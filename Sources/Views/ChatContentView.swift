import SwiftUI

/// ChatView와 ChatWindowView에서 공유하는 메시지 리스트 + 입력 영역
struct ChatContentView: View {
    @Environment(\.colorPalette) private var palette
    let agentID: UUID
    let agent: Agent?
    @EnvironmentObject var chatVM: ChatViewModel
    @State private var inputText = ""
    @State private var inputAccessor = ScrollableTextInput.Accessor()

    var body: some View {
        VStack(spacing: 0) {
            // 메시지 목록
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if chatVM.messages(for: agentID).isEmpty {
                            welcomeMessage
                        }

                        let msgs = chatVM.messages(for: agentID)
                        ForEach(Array(msgs.enumerated()), id: \.element.id) { index, message in
                            if shouldShowDateSeparator(at: index, in: msgs) {
                                dateSeparatorView(for: message.timestamp)
                            }
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if chatVM.loadingAgentIDs.contains(agentID) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("응답 생성 중...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { chatVM.cancelTask(for: agentID) }) {
                                    Image(systemName: "stop.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .help("작업 취소")
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: chatVM.messages(for: agentID).last?.id) { _ in
                    if let last = chatVM.messages(for: agentID).last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // 그라데이션 구분선
            Rectangle()
                .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)

            // 입력 영역
            HStack(spacing: 8) {
                ScrollableTextInput(
                    text: $inputText,
                    placeholder: "메시지를 입력하세요...",
                    font: NSFont.systemFont(ofSize: DesignTokens.FontSize.bodyMd),
                    maxHeight: 100,
                    onSubmit: send,
                    accessor: inputAccessor
                )

                SendButton(
                    canSend: !inputText.isEmpty,
                    isLoading: chatVM.loadingAgentIDs.contains(agentID),
                    action: send
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                    .fill(palette.panelGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                    .strokeBorder(palette.cardBorder.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: palette.sidebarShadow.opacity(0.3), radius: 4, y: -1)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private var welcomeMessage: some View {
        VStack(spacing: 16) {
            Spacer()
            if let agent {
                AgentAvatarView(agent: agent, size: 52)
                    .opacity(0.6)
                    .shadow(color: palette.accent.opacity(0.15), radius: 12, y: 4)

                VStack(spacing: 4) {
                    Text(agent.isMaster
                         ? "무엇을 도와드릴까요?"
                         : "\(agent.name)에게 메시지를 보내보세요")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.6))
                    if agent.isMaster {
                        Text("빠른 질문부터 복잡한 프로젝트까지")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.35))
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func send() {
        inputAccessor.sync()
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputAccessor.clear()
        inputText = ""
        chatVM.sendMessage(text, agentID: agentID)
    }

    // MARK: - 날짜 구분선

    private func shouldShowDateSeparator(at index: Int, in messages: [ChatMessage]) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].timestamp, inSameDayAs: messages[index - 1].timestamp)
    }

    private func dateSeparatorView(for date: Date) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.25)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.5)
            Text(Self.dateSeparatorFormatter.string(from: date))
                .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                .foregroundColor(.secondary.opacity(0.4))
                .fixedSize()
            Rectangle()
                .fill(LinearGradient(colors: [palette.separator.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.5)
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    private static let dateSeparatorFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f
    }()
}
