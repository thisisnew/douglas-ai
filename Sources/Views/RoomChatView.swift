import SwiftUI
import UniformTypeIdentifiers

// MARK: - 방 채팅 뷰

struct RoomChatView: View {
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore
    @Environment(\.colorPalette) private var palette
    @State private var inputText = ""
    @State private var pendingAttachments: [ImageAttachment] = []
    @State private var showDeleteConfirm = false
    @State private var showCopiedFeedback = false
    @State private var selectedAgent: Agent?
    @State private var mentionCandidates: [Agent] = []
    @FocusState private var isInputFocused: Bool

    private var room: Room? {
        roomManager.rooms.first { $0.id == roomID }
    }

    var body: some View {
        if let room = room {
            VStack(spacing: 0) {
                // 방 헤더
                roomHeader(room)

                Rectangle()
                    .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)

                // 토론 진행 바 (계획 수립 전)
                if room.plan == nil && room.status == .planning {
                    DiscussionProgressBar(room: room)
                }

                // 계획 카드 (계획 수립 후) — 헤더 아래 고정
                if let plan = room.plan {
                    PlanCard(plan: plan, currentStep: room.currentStepIndex, status: room.status, agentStore: agentStore)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // 메시지 목록
                messageListView(room)

                // 액션 카드 영역 (입력 위, 메시지 아래)

                // 에이전트 생성 제안 카드
                ForEach(room.pendingAgentSuggestions.filter { $0.status == .pending }) { suggestion in
                    AgentSuggestionCard(suggestion: suggestion, roomID: room.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                }
                .animation(.easeInOut(duration: 0.3), value: room.pendingAgentSuggestions.filter { $0.status == .pending }.count)

                // Intent 선택 카드 (quickClassify 실패 시)
                if let suggestedIntent = roomManager.pendingIntentSelection[room.id] {
                    IntentSelectionCard(roomID: room.id, suggestedIntent: suggestedIntent)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 승인 대기 카드 (승인 게이트 활성 시)
                if room.status == .awaitingApproval {
                    ApprovalCard(roomID: room.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 사용자 입력 카드 (ask_user 도구 활성 시)
                if room.status == .awaitingUserInput {
                    UserInputCard(roomID: room.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Rectangle()
                    .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)

                // 입력 영역 (완료/실패 후에만 — 진행 중에는 숨김)
                if room.status == .completed || room.status == .failed {
                    inputArea(room)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: room.status)
        }
    }

    // MARK: - 메시지 목록

    @ViewBuilder
    private func messageListView(_ room: Room) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let msgs = visibleMessages(room)
                    ForEach(Array(msgs.enumerated()), id: \.element.id) { index, message in
                        if shouldShowDateSeparator(at: index, in: msgs) {
                            dateSeparatorView(for: message.timestamp)
                        }
                        messageRow(message, in: room)
                    }

                    // 작업 진행 중 타이핑 인디케이터 (활성 진행 버블이 없을 때만)
                    if (room.status == .planning || room.status == .inProgress),
                       !hasActiveProgressBubble(room) {
                        TypingIndicator(room: room, agentStore: agentStore)
                            .id("typing-indicator")
                    }
                }
                .padding(12)
            }
            .onAppear {
                scrollToBottom(proxy: proxy, room: room)
            }
            .onChange(of: room.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, room: room)
            }
            .onChange(of: room.messages.last?.id) { _, _ in
                scrollToBottom(proxy: proxy, room: room)
            }
            .onChange(of: room.status) { _, _ in
                scrollToBottom(proxy: proxy, room: room)
            }
            .onChange(of: room.currentPhase) { _, _ in
                scrollToBottom(proxy: proxy, room: room)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage, in room: Room) -> some View {
        if message.messageType == .progress {
            ProgressActivityBubble(
                message: message,
                activities: activitiesForProgress(message.id, in: room),
                isActive: isProgressActive(message, in: room)
            )
            .id(message.id)
        } else {
            MessageBubble(message: message)
                .id(message.id)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, room: Room) {
        if let last = visibleMessages(room).last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    // MARK: - 날짜 구분선

    private func shouldShowDateSeparator(at index: Int, in messages: [ChatMessage]) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].timestamp, inSameDayAs: messages[index - 1].timestamp)
    }

    private func dateSeparatorView(for date: Date) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            Text(Self.dateSeparatorFormatter.string(from: date))
                .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                .foregroundColor(.secondary.opacity(0.5))
                .fixedSize()
            Rectangle()
                .fill(LinearGradient(colors: [palette.separator.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private static let dateSeparatorFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f
    }()

    // MARK: - 메시지 필터링 (활동 그룹 숨김)

    /// 메인 채팅에 보이는 메시지: activityGroupID 소속 메시지는 숨김 (progress 버블에서 표시)
    private func visibleMessages(_ room: Room) -> [ChatMessage] {
        room.messages.filter { $0.activityGroupID == nil && $0.messageType != .approvalRequest }
    }

    /// 특정 progress 메시지에 소속된 활동 메시지들
    private func activitiesForProgress(_ progressID: UUID, in room: Room) -> [ChatMessage] {
        room.messages.filter { $0.activityGroupID == progressID }
    }

    /// progress 메시지가 현재 진행 중인지 (다음 progress가 아직 없으면 활성)
    private func isProgressActive(_ message: ChatMessage, in room: Room) -> Bool {
        guard room.isActive else { return false }
        let progressMessages = room.messages.filter { $0.messageType == .progress }
        guard let lastProgress = progressMessages.last else { return false }
        return lastProgress.id == message.id
    }

    /// 현재 활성 상태인 진행 버블이 있는지
    private func hasActiveProgressBubble(_ room: Room) -> Bool {
        guard room.isActive else { return false }
        return room.messages.contains { $0.messageType == .progress }
    }

    // MARK: - 방 헤더

    private func roomHeader(_ room: Room) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(room.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer()

                // 미니 모드 (PiP)
                Button {
                    UtilityWindowManager.shared.toggleMiniMode(windowID: roomID.uuidString)
                } label: {
                    Image(systemName: "rectangle.bottomhalf.inset.filled")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("미니 모드")

                // 대화 내역 복사
                Button {
                    copyRoomTranscript(room)
                    withAnimation(.easeInOut(duration: 0.15)) { showCopiedFeedback = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) { showCopiedFeedback = false }
                    }
                } label: {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(showCopiedFeedback ? .green : .secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("대화 내역 복사")

                // 작업 중지 버튼 (진행 중인 방만)
                if room.isActive {
                    Button {
                        roomManager.completeRoom(room.id)
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("작업 중지 (완료 처리)")
                }

                // 삭제 버튼
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("방 삭제")
                .confirmationDialog("이 방을 삭제할까요?", isPresented: $showDeleteConfirm) {
                    Button("삭제", role: .destructive) {
                        // 창 닫기를 위해 UtilityWindowManager 사용
                        roomManager.deleteRoom(room.id)
                        // NSWindow를 찾아 닫기
                        UtilityWindowManager.shared.closeKeyWindow()
                    }
                } message: {
                    Text("진행 중인 작업이 있으면 즉시 중단됩니다.")
                }

                // Intent 배지
                if let intent = room.intent {
                    HStack(spacing: 2) {
                        Image(systemName: intent.iconName)
                            .font(.system(size: 8))
                        Text(intent.displayName)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(palette.accent.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(palette.accent.opacity(0.12))
                    )
                }

                // 상태 + 생성일시
                statusLabel(room)
            }

            // 참여 에이전트 아바타
            HStack(spacing: -6) {
                ForEach(room.assignedAgentIDs, id: \.self) { agentID in
                    if let agent = agentStore.agents.first(where: { $0.id == agentID }) {
                        let isSpeaking = roomManager.speakingAgentIDByRoom[room.id] == agentID
                        AgentAvatarView(agent: agent, size: 20)
                            .overlay(
                                Circle().stroke(
                                    isSpeaking ? Color.green : palette.background,
                                    lineWidth: isSpeaking ? 2 : 1
                                )
                            )
                            .opacity(isSpeaking ? 1.0 : 0.7)
                            .onTapGesture { selectedAgent = agent }
                            .help(agent.name)
                    }
                }
                Spacer()
            }
            .sheet(item: $selectedAgent) { agent in
                AgentInfoSheet(agent: agent)
                    .frame(
                        width: DesignTokens.WindowSize.agentInfoSheet.width,
                        height: DesignTokens.WindowSize.agentInfoSheet.height
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(palette.panelGradient)
    }

    private func copyRoomTranscript(_ room: Room) {
        var text = "[\(room.shortID)] \(room.title)\n"
        text += "상태: \(DesignTokens.RoomStatusColor.label(for: room.status))"
        if let intent = room.intent { text += " · \(intent.displayName)" }
        if let phase = room.currentPhase { text += " · \(phase.rawValue)" }
        text += "\n"

        let agentNames = room.assignedAgentIDs.compactMap { id in
            agentStore.agents.first(where: { $0.id == id })?.name
        }
        if !agentNames.isEmpty {
            text += "참여: \(agentNames.joined(separator: ", "))\n"
        }
        text += "\n"

        for msg in room.messages {
            let sender: String
            switch msg.role {
            case .user: sender = "사용자"
            case .assistant: sender = msg.agentName ?? "에이전트"
            case .system: sender = "시스템"
            }
            text += "[\(sender)] \(msg.content)\n\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - 입력 영역

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    private func inputArea(_ room: Room) -> some View {
        VStack(spacing: 4) {
            // 첨부 이미지 미리보기
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(pendingAttachments) { att in
                            AttachmentThumbnail(attachment: att) {
                                att.delete()
                                pendingAttachments.removeAll { $0.id == att.id }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                }
            }

            // @멘션 자동완성 팝오버
            if !mentionCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(mentionCandidates) { agent in
                        Button {
                            insertMention(agent)
                        } label: {
                            HStack(spacing: 6) {
                                AgentAvatarView(agent: agent, size: 18)
                                Text(agent.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary)
                                Spacer()
                                if room.assignedAgentIDs.contains(agent.id) {
                                    Text("참여중")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(palette.panelGradientStart)
                .continuousRadius(DesignTokens.CozyGame.cardRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: palette.sidebarShadow, radius: 6, y: -2)
                .padding(.horizontal, 10)
            }

            HStack(spacing: 8) {
                // 이미지 첨부 버튼
                Button(action: pickImage) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("이미지 첨부")

                TextField(room.status == .inProgress ? "추가 요건을 입력하세요..." : "메시지를 입력하세요...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }
                    .onChange(of: inputText) { _, newValue in
                        updateMentionCandidates(newValue)
                    }

                SendButton(canSend: canSend, isLoading: false, action: sendMessage)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                .fill(palette.panelGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            handleImageDrop(providers)
            return true
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        let attachments = pendingAttachments.isEmpty ? nil : pendingAttachments
        inputText = ""
        pendingAttachments = []
        mentionCandidates = []
        Task { await roomManager.sendUserMessage(text, to: roomID, attachments: attachments) }
    }

    // MARK: - @멘션 자동완성

    /// 입력 텍스트에서 마지막 `@` 이후 쿼리를 추출하여 후보 목록 갱신
    private func updateMentionCandidates(_ text: String) {
        // 마지막 @ 찾기
        guard let atRange = text.range(of: "@", options: .backwards) else {
            mentionCandidates = []
            return
        }

        // @ 앞이 공백이거나 문장 시작인 경우만 멘션으로 인식 (이메일 오탐 방지)
        if atRange.lowerBound != text.startIndex {
            let charBefore = text[text.index(before: atRange.lowerBound)]
            if !charBefore.isWhitespace {
                mentionCandidates = []
                return
            }
        }

        let afterAt = text[atRange.upperBound...]
        // @ 뒤에 공백이 있으면 멘션 입력 완료 간주
        if afterAt.contains(" ") {
            mentionCandidates = []
            return
        }

        let query = String(afterAt).lowercased()
        let subAgents = agentStore.subAgents
        if query.isEmpty {
            // @ 만 입력 → 전체 서브 에이전트 목록 (최대 6명)
            mentionCandidates = Array(subAgents.prefix(6))
        } else {
            // 쿼리로 필터
            mentionCandidates = subAgents.filter {
                $0.name.lowercased().contains(query)
            }
        }
    }

    /// 자동완성에서 에이전트 선택 시 입력 필드에 멘션 삽입
    private func insertMention(_ agent: Agent) {
        // 마지막 @ 위치 찾아서 교체
        if let atRange = inputText.range(of: "@", options: .backwards) {
            inputText = String(inputText[inputText.startIndex..<atRange.lowerBound])
                + "@\(agent.name) "
        }
        mentionCandidates = []
    }

    // MARK: - 이미지 첨부

    private func pickImage() {
        // .nonactivatingPanel이 NSOpenPanel 클릭을 방해하므로 임시 해제 (NSColorPanel 제외)
        if NSColorPanel.shared.isVisible { NSColorPanel.shared.orderOut(nil) }
        let panels = NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.styleMask.contains(.nonactivatingPanel) && !($0 is NSColorPanel) }
        for p in panels { p.styleMask.remove(.nonactivatingPanel) }

        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.jpeg, .png, .gif, .webP]
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.message = "첨부할 이미지를 선택하세요"
        let response = openPanel.runModal()

        // 복원
        for p in panels { p.styleMask.insert(.nonactivatingPanel) }
        if wasAccessory && UtilityWindowManager.shared.windows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
        guard response == .OK else { return }
        for url in openPanel.urls {
            addImageFromURL(url)
        }
    }

    private func addImageFromURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let mime = ImageAttachment.mimeType(for: data) else { return }
        guard let attachment = try? ImageAttachment.save(data: data, mimeType: mime) else { return }
        pendingAttachments.append(attachment)
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data = data,
                          let mime = ImageAttachment.mimeType(for: data),
                          let attachment = try? ImageAttachment.save(data: data, mimeType: mime) else { return }
                    DispatchQueue.main.async {
                        pendingAttachments.append(attachment)
                    }
                }
            }
        }
    }

    // roomAttachmentThumbnail → SharedComponents.AttachmentThumbnail 사용

    // MARK: - 상태 라벨

    @ViewBuilder
    private func statusLabel(_ room: Room) -> some View {
        HStack(spacing: 4) {
            switch room.status {
            case .planning:
                ProgressView().scaleEffect(0.4)
                    .frame(width: 12, height: 12)
                Text(room.phaseLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(DesignTokens.RoomStatusColor.color(for: .planning, palette: palette))
            case .inProgress:
                Circle()
                    .fill(Color.orange.opacity(0.7))
                    .frame(width: 6, height: 6)
                Text("진행중")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.orange.opacity(0.7))
            case .awaitingApproval:
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.yellow.opacity(0.7))
                Text("승인 대기")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.yellow.opacity(0.7))
            case .awaitingUserInput:
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.cyan.opacity(0.7))
                Text("입력 대기")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.cyan.opacity(0.7))
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.green.opacity(0.7))
                Text("완료")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.green.opacity(0.7))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.red.opacity(0.7))
                Text("실패")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.red.opacity(0.7))
            }

            Text("·")
                .foregroundColor(.secondary.opacity(0.4))
            ElapsedTimeLabel(room: room)

            Text("·")
                .foregroundColor(.secondary.opacity(0.4))
            Text(room.shortID)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

// MARK: - 계획 카드

struct PlanCard: View {
    let plan: RoomPlan
    let currentStep: Int
    let status: RoomStatus
    var agentStore: AgentStore?

    @State private var isExpanded = true

    var body: some View {
        CardContainer(accentColor: .purple) {
            VStack(alignment: .leading, spacing: 4) {
                // 헤더 (접이식)
                Button {
                    withAnimation(.dgStandard) { isExpanded.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.purple.opacity(0.7))
                        Text("작업 계획")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.purple.opacity(0.7))
                        Spacer()
                        Text("\(completedStepCount)/\(plan.steps.count)")
                            .font(DesignTokens.Typography.mono(DesignTokens.FontSize.nano))
                            .foregroundColor(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: DesignTokens.FontSize.nano))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(plan.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 6) {
                            stepIcon(index: index)
                            if step.requiresApproval {
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: DesignTokens.FontSize.nano))
                                    .foregroundColor(.orange.opacity(0.7))
                            }
                            Text(step.text)
                                .font(.caption2)
                                .foregroundColor(stepColor(index: index))
                                .lineLimit(1)
                            Spacer()
                            if let name = agentName(for: step) {
                                Text(name)
                                    .font(.system(size: 9))
                                    .foregroundColor(index == currentStep && status == .inProgress ? .orange.opacity(0.7) : .secondary.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var completedStepCount: Int {
        if status == .completed { return plan.steps.count }
        return currentStep
    }

    private func agentName(for step: RoomStep) -> String? {
        guard let id = step.assignedAgentID,
              let agent = agentStore?.agents.first(where: { $0.id == id }) else { return nil }
        return agent.name
    }

    @ViewBuilder
    private func stepIcon(index: Int) -> some View {
        if status == .completed || index < currentStep {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundColor(.green.opacity(0.7))
        } else if index == currentStep && status == .inProgress {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 9))
                .foregroundColor(.orange.opacity(0.7))
        } else {
            Image(systemName: "circle")
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
    }

    private func stepColor(index: Int) -> Color {
        if status == .completed || index < currentStep {
            return .secondary
        } else if index == currentStep && status == .inProgress {
            return .primary
        } else {
            return .secondary.opacity(0.7)
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let min = seconds / 60
        let sec = seconds % 60
        return String(format: "%d:%02d 예상", min, sec)
    }
}

// MARK: - 토론 진행 바

struct DiscussionProgressBar: View {
    let room: Room
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore

    var body: some View {
        CardContainer(accentColor: .blue) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.blue.opacity(0.7))
                    Text("작업 진행")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.blue.opacity(0.7))
                    Spacer()
                    Text(room.phaseLabel)
                        .font(DesignTokens.Typography.monoBadge)
                        .foregroundColor(.secondary)
                }

            // 프로그레스 바
            CozyProgressBar(
                progress: Double(progressRatio),
                fillColor: Color.blue.opacity(0.7),
                fillEndColor: Color.blue.opacity(0.5)
            )

            // 현재 발언 중인 에이전트 또는 참여자 수
            if let speakingName = speakingAgentName {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 12, height: 12)
                    Text("\(speakingName) 발언 중...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("\(room.assignedAgentIDs.count)명 참여")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            }
        }
    }

    private var progressRatio: CGFloat {
        let maxRounds = 3
        return CGFloat(min(room.currentRound, maxRounds)) / CGFloat(maxRounds)
    }

    private var speakingAgentName: String? {
        guard let agentID = roomManager.speakingAgentIDByRoom[room.id] else { return nil }
        return agentStore.agents.first(where: { $0.id == agentID })?.name
    }
}


// MARK: - 빌드 상태 카드

struct BuildStatusCard: View {
    let room: Room

    var body: some View {
        CardContainer(accentColor: statusColor, opacity: 0.06) {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.caption2.bold())
                        .foregroundColor(statusColor)
                    if let cmd = room.buildCommand {
                        Text(cmd)
                            .font(DesignTokens.Typography.mono(DesignTokens.FontSize.badge))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if room.buildRetryCount > 0 {
                    Text("\(room.buildRetryCount)/\(room.maxBuildRetries)")
                        .font(DesignTokens.Typography.monoStatus)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var statusText: String {
        switch room.buildLoopStatus {
        case .building: return "빌드 실행 중..."
        case .fixing:   return "오류 수정 중..."
        case .passed:   return "빌드 성공"
        case .failed:   return "빌드 실패"
        case .idle, .none: return "빌드 대기"
        }
    }

    private var statusColor: Color {
        switch room.buildLoopStatus {
        case .building: return .orange.opacity(0.7)
        case .fixing:   return .yellow.opacity(0.7)
        case .passed:   return .green.opacity(0.7)
        case .failed:   return .red.opacity(0.7)
        case .idle, .none: return .gray
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch room.buildLoopStatus {
        case .building, .fixing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green.opacity(0.7))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red.opacity(0.7))
        case .idle, .none:
            Image(systemName: "hammer")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - 승인 카드

struct ApprovalCard: View {
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @Environment(\.colorPalette) private var palette
    @State private var hoveredButton: String?
    @State private var showFeedbackInput = false
    @State private var feedbackText = ""
    @FocusState private var isFeedbackFocused: Bool

    /// 방의 최근 .approvalRequest 메시지에서 승인 제목과 내용을 추출
    private var approvalInfo: (title: String, detail: String?) {
        guard let room = roomManager.rooms.first(where: { $0.id == roomID }),
              let msg = room.messages.last(where: { $0.messageType == .approvalRequest }) else {
            return ("이해한 내용이 맞는지 확인해주세요", nil)
        }
        let content = msg.content
        if content.hasPrefix("실행 계획:") {
            return ("실행 계획을 확인해주세요", String(content.dropFirst("실행 계획:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if content.contains("이 단계는 승인이 필요합니다") {
            return ("단계 승인이 필요합니다", content)
        }
        if content.hasPrefix("토론이 완료되었습니다") {
            return ("토론 결과를 확인해주세요", String(content.dropFirst("토론이 완료되었습니다.".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ("분석 결과를 확인해주세요", nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // 타이틀
                HStack(spacing: 8) {
                    Circle()
                        .fill(.yellow.opacity(0.1))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.yellow.opacity(0.7))
                        )
                    Text(approvalInfo.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                    Spacer()
                }

                // 상세 내용
                if let detail = approvalInfo.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(palette.inputBackground.opacity(0.5))
                        .continuousRadius(DesignTokens.CozyGame.cardRadius)
                }

                // 피드백 입력 영역 (수정 요청 클릭 시 표시)
                if showFeedbackInput {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("어떤 부분을 수정해야 하나요?")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("수정 사항을 입력하세요...", text: $feedbackText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .rounded))
                            .lineLimit(1...4)
                            .padding(8)
                            .background(palette.inputBackground)
                            .continuousRadius(DesignTokens.CozyGame.cardRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                                    .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                            )
                            .focused($isFeedbackFocused)
                            .onSubmit {
                                submitFeedback()
                            }

                        HStack(spacing: 8) {
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showFeedbackInput = false
                                    feedbackText = ""
                                }
                            } label: {
                                Text("취소")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                submitFeedback()
                            } label: {
                                Text("전송")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                                            .fill(feedbackText.trimmingCharacters(in: .whitespaces).isEmpty
                                                  ? palette.accent.opacity(0.4)
                                                  : palette.accent)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(feedbackText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // 버튼 (피드백 입력 중이 아닐 때만 표시)
                if !showFeedbackInput {
                    HStack(spacing: 10) {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFeedbackInput = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isFeedbackFocused = true
                            }
                        } label: {
                            Text("수정 요청")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                                        .fill(hoveredButton == "reject" ? palette.separator : palette.inputBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                                        .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredButton = hovering ? "reject" : (hoveredButton == "reject" ? nil : hoveredButton)
                            }
                        }

                        Button {
                            roomManager.approveStep(roomID: roomID)
                        } label: {
                            Text("승인")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    hoveredButton == "approve" ? palette.accent.opacity(0.85) : palette.accent.opacity(0.9),
                                                    palette.accent
                                                ],
                                                startPoint: .top, endPoint: .bottom
                                            )
                                        )
                                )
                                .shadow(color: palette.buttonShadow.opacity(0.25), radius: 4, y: DesignTokens.CozyGame.buttonShadowY)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredButton = hovering ? "approve" : (hoveredButton == "approve" ? nil : hoveredButton)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.panelRadius, style: .continuous)
                    .fill(palette.panelGradient)
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.panelRadius, style: .continuous)
                    .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1.5)
            }
        )
        .shadow(color: palette.sidebarShadow, radius: DesignTokens.CozyGame.panelShadowRadius, y: DesignTokens.CozyGame.panelShadowY)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .animation(.easeInOut(duration: 0.2), value: showFeedbackInput)
    }

    private func submitFeedback() {
        let text = feedbackText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        // 피드백을 사용자 메시지로 추가 후 거부
        roomManager.appendAdditionalInput(roomID: roomID, text: text)
        roomManager.rejectStep(roomID: roomID)
    }
}

// MARK: - 사용자 입력 카드

struct UserInputCard: View {
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @Environment(\.colorPalette) private var palette
    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        CardContainer(accentColor: .cyan, opacity: 0.08) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.cyan.opacity(0.7))
                    Text("에이전트가 추가 정보를 요청합니다")
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                }

                HStack(spacing: 8) {
                    TextField("답변을 입력하세요...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .rounded))
                        .padding(6)
                        .background(palette.inputBackground)
                        .continuousRadius(DesignTokens.CozyGame.cardRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                                .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                        )
                        .focused($isFocused)
                        .onSubmit { submit() }

                    Button("전송") { submit() }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.6) : palette.accent)
                        .continuousRadius(DesignTokens.CozyGame.buttonRadius)
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        let answer = inputText.trimmingCharacters(in: .whitespaces)
        guard !answer.isEmpty else { return }
        inputText = ""
        roomManager.answerUserQuestion(roomID: roomID, answer: answer)
    }
}

// MARK: - Intent 선택 카드

struct IntentSelectionCard: View {
    let roomID: UUID
    let suggestedIntent: WorkflowIntent
    @EnvironmentObject var roomManager: RoomManager
    @Environment(\.colorPalette) private var palette

    var body: some View {
        CardContainer(accentColor: .teal, opacity: 0.08) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundColor(.teal.opacity(0.7))
                    Text("작업 유형을 선택해주세요")
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                    Spacer()
                }

                // Intent 버튼 리스트 (설명 포함)
                let intents = WorkflowIntent.allCases
                VStack(spacing: 4) {
                    ForEach(intents, id: \.self) { intent in
                        Button {
                            roomManager.selectIntent(roomID: roomID, intent: intent)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: intentIcon(intent))
                                    .font(.system(size: 10))
                                    .frame(width: 14)
                                Text(intent.displayName)
                                    .font(.caption2.bold())
                                if intent == suggestedIntent {
                                    Text("추천")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.teal.opacity(0.7))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Text(intent.subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(intent == suggestedIntent ? Color.teal.opacity(0.08) : palette.inputBackground)
                            .foregroundColor(intent == suggestedIntent ? .teal.opacity(0.7) : .primary)
                            .continuousRadius(DesignTokens.CozyGame.cardRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                                    .strokeBorder(
                                        intent == suggestedIntent ? Color.teal.opacity(0.2) : palette.cardBorder.opacity(0.1),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func intentIcon(_ intent: WorkflowIntent) -> String {
        intent.iconName
    }
}

// MARK: - 에이전트 생성 제안 카드

struct AgentSuggestionCard: View {
    let suggestion: RoomAgentSuggestion
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore
    @Environment(\.colorPalette) private var palette
    @State private var showAddSheet = false

    var body: some View {
        CardContainer(accentColor: .orange, opacity: 0.06) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.7))
                    Text("에이전트 생성 제안")
                        .font(.caption2.bold())
                        .foregroundColor(.orange.opacity(0.7))
                    Spacer()
                    Text(suggestion.suggestedBy)
                        .font(.system(size: DesignTokens.FontSize.badge))
                        .foregroundColor(.secondary)
                }

                Text(suggestion.name)
                    .font(.caption.bold())
                    .foregroundColor(.primary)

                Text(suggestion.persona.prefix(120) + (suggestion.persona.count > 120 ? "..." : ""))
                    .font(.system(size: DesignTokens.FontSize.xs))
                    .foregroundColor(.secondary)
                    .lineLimit(3)

                if !suggestion.reason.isEmpty {
                    Text("사유: \(suggestion.reason)")
                        .font(.system(size: DesignTokens.FontSize.badge))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button("건너뛰기") {
                        roomManager.rejectAgentSuggestion(suggestionID: suggestion.id, in: roomID)
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(palette.inputBackground)
                    .continuousRadius(DesignTokens.CozyGame.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                            .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                    )

                    Button("추가") {
                        showAddSheet = true
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.8), Color.orange.opacity(0.9)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .continuousRadius(DesignTokens.CozyGame.buttonRadius)
                    .shadow(color: Color.orange.opacity(0.2), radius: 3, y: 2)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddAgentSheet(
                prefillName: suggestion.name,
                prefillPersona: suggestion.persona,
                onCreated: { newAgent in
                    // 제안 승인 + 방에 에이전트 추가
                    if let roomIdx = roomManager.rooms.firstIndex(where: { $0.id == roomID }),
                       let sugIdx = roomManager.rooms[roomIdx].pendingAgentSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
                        roomManager.rooms[roomIdx].pendingAgentSuggestions[sugIdx].status = .approved
                    }
                    roomManager.addAgent(newAgent.id, to: roomID, silent: true)
                    let msg = ChatMessage(
                        role: .system,
                        content: "'\(newAgent.name)' 에이전트가 생성되어 방에 참여했습니다."
                    )
                    roomManager.appendMessage(msg, to: roomID)
                    roomManager.resumeSuggestionContinuationIfResolved(roomID: roomID)
                }
            )
            .environmentObject(agentStore)
        }
    }
}

// MARK: - QA 상태 카드

struct QAStatusCard: View {
    let room: Room

    var body: some View {
        CardContainer(accentColor: qaStatusColor, opacity: 0.06) {
            HStack(spacing: 8) {
                qaStatusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(qaStatusText)
                        .font(.caption2.bold())
                        .foregroundColor(qaStatusColor)
                    if let cmd = room.testCommand {
                        Text(cmd)
                            .font(DesignTokens.Typography.mono(DesignTokens.FontSize.badge))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if room.qaRetryCount > 0 {
                    Text("\(room.qaRetryCount)/\(room.maxQARetries)")
                        .font(DesignTokens.Typography.monoStatus)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var qaStatusText: String {
        switch room.qaLoopStatus {
        case .testing:   return "테스트 실행 중..."
        case .analyzing: return "실패 분석/수정 중..."
        case .passed:    return "테스트 통과"
        case .failed:    return "테스트 실패"
        case .idle, .none: return "테스트 대기"
        }
    }

    private var qaStatusColor: Color {
        switch room.qaLoopStatus {
        case .testing:   return .teal.opacity(0.7)
        case .analyzing: return .yellow.opacity(0.7)
        case .passed:    return .green.opacity(0.7)
        case .failed:    return .red.opacity(0.7)
        case .idle, .none: return .gray
        }
    }

    @ViewBuilder
    private var qaStatusIcon: some View {
        switch room.qaLoopStatus {
        case .testing, .analyzing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        case .passed:
            Image(systemName: "checkmark.shield.fill")
                .font(.caption)
                .foregroundColor(.green.opacity(0.7))
        case .failed:
            Image(systemName: "xmark.shield.fill")
                .font(.caption)
                .foregroundColor(.red.opacity(0.7))
        case .idle, .none:
            Image(systemName: "checkmark.shield")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - 토론 발언 컴팩트 버블

struct DiscussionTurnBubble: View {
    let message: ChatMessage
    @Environment(\.colorPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 9))
                .foregroundColor(.blue.opacity(0.5))
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 1) {
                if let name = message.agentName {
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.blue.opacity(0.7))
                }
                Text(message.content)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 48)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous))
        .shadow(color: palette.sidebarShadow.opacity(0.5), radius: 2, y: 1)
    }
}

// MARK: - 경과 시간 타이머

/// 활성 방: 1초마다 갱신되는 경과 시간 / 완료 방: 총 소요 시간
private struct ElapsedTimeLabel: View {
    let room: Room
    @State private var now = Date()

    private var isActive: Bool {
        room.status != .completed && room.status != .failed
    }

    private var elapsed: TimeInterval {
        let end = room.completedAt ?? now
        return max(0, end.timeIntervalSince(room.createdAt))
    }

    private var formattedTime: String {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes)분 \(seconds)초"
        }
        return "\(seconds)초"
    }

    var body: some View {
        Text(formattedTime)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { time in
                if isActive { now = time }
            }
    }
}

