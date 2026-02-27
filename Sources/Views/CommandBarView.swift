import SwiftUI

/// Spotlight 스타일 커맨드 바 — 마스터 에이전트에게 빠르게 질문
struct CommandBarView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var agentStore: AgentStore

    var onDismiss: () -> Void
    var onOpenFullChat: (Agent) -> Void

    @State private var inputText = ""
    @State private var responseText: String?
    @State private var delegationInfo: String?
    @State private var messageCountBeforeSend = 0
    @State private var hasSent = false
    @FocusState private var isInputFocused: Bool

    private var masterAgent: Agent? { agentStore.masterAgent }

    private var isMasterLoading: Bool {
        guard let id = masterAgent?.id else { return false }
        return chatVM.loadingAgentIDs.contains(id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            header
            Divider()

            // 입력 영역
            inputArea
                .padding(16)

            // 액션 바
            actionBar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // 응답 영역
            if hasSent {
                Divider()
                responseArea
                    .padding(16)
            }
        }
        .frame(width: 600)
        .background(.ultraThinMaterial)
        .onAppear {
            isInputFocused = true
        }
        .onChange(of: isMasterLoading) { _, loading in
            if !loading && hasSent {
                extractResponse()
            }
        }
    }

    // MARK: - 헤더

    private var header: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
            Text("빠른 질문")
                .font(.headline)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 입력 영역

    private var inputArea: some View {
        TextEditor(text: $inputText)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(10)
            .frame(minHeight: 100, maxHeight: 120)
            .focused($isInputFocused)
    }

    // MARK: - 액션 바

    private var actionBar: some View {
        HStack {
            if let master = masterAgent {
                Button(action: { openFullChat(master) }) {
                    Label("전체 대화 열기", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Spacer()

            Text("⌘⏎ 전송")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(canSend ? .accentColor : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: - 응답 영역

    private var responseArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isMasterLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("응답 생성 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let info = delegationInfo {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(info)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if let response = responseText {
                ScrollView {
                    Text(response)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            }
        }
    }

    // MARK: - 로직

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isMasterLoading
    }

    private func send() {
        guard let master = masterAgent else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messageCountBeforeSend = chatVM.messages(for: master.id).count
        responseText = nil
        delegationInfo = nil
        hasSent = true
        inputText = ""

        chatVM.sendMessage(text, agentID: master.id)
    }

    private func extractResponse() {
        guard let master = masterAgent else { return }
        let allMessages = chatVM.messages(for: master.id)
        let newMessages = Array(allMessages.dropFirst(messageCountBeforeSend))

        // 위임 정보 추출
        if let delegation = newMessages.first(where: { $0.messageType == .delegation }) {
            delegationInfo = delegation.content
        }

        // 마지막 assistant 응답 표시
        if let lastResponse = newMessages.last(where: { $0.role == .assistant && $0.messageType != .delegation }) {
            responseText = lastResponse.content
        }
    }

    private func openFullChat(_ agent: Agent) {
        onOpenFullChat(agent)
        onDismiss()
    }
}
