import SwiftUI

/// ChatView와 ChatWindowView에서 공유하는 메시지 리스트 + 입력 영역
struct ChatContentView: View {
    @Environment(\.colorPalette) private var palette
    let agentID: UUID
    let agent: Agent?
    @EnvironmentObject var chatVM: ChatViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

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
                .onChange(of: chatVM.messages(for: agentID).last?.id) { _, _ in
                    if let last = chatVM.messages(for: agentID).last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // 입력 영역
            HStack(spacing: 8) {
                TextField("메시지를 입력하세요...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit { send() }

                SendButton(
                    canSend: !inputText.isEmpty,
                    isLoading: chatVM.loadingAgentIDs.contains(agentID),
                    action: send
                )
            }
            .padding(10)
            .background(palette.inputBackground)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private var welcomeMessage: some View {
        VStack(spacing: 12) {
            Spacer()
            if let agent {
                AgentAvatarView(agent: agent, size: 48)
                    .opacity(0.5)
                Text(agent.isMaster
                     ? "안녕하세요! 무엇을 도와드릴까요?"
                     : "\(agent.name)에게 메시지를 보내보세요.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        chatVM.sendMessage(text, agentID: agentID)
    }

    // MARK: - 날짜 구분선

    private func shouldShowDateSeparator(at index: Int, in messages: [ChatMessage]) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].timestamp, inSameDayAs: messages[index - 1].timestamp)
    }

    private func dateSeparatorView(for date: Date) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 0.5)
            Text(Self.dateSeparatorFormatter.string(from: date))
                .font(.system(size: DesignTokens.FontSize.xs))
                .foregroundColor(.secondary.opacity(0.5))
                .fixedSize()
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 0.5)
        }
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private static let dateSeparatorFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f
    }()
}
