import SwiftUI
import UniformTypeIdentifiers

// MARK: - 방 채팅 뷰

struct RoomChatView: View {
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var providerManager: ProviderManager
    @Environment(\.colorPalette) private var palette
    @State private var inputText = ""
    @State private var inputAccessor = ScrollableTextInput.Accessor()
    @State private var pendingAttachments: [FileAttachment] = []
    @State private var showDeleteConfirm = false
    @State private var showCopiedFeedback = false
    @State private var selectedAgent: Agent?
    @State private var mentionCandidates: [Agent] = []
    @State private var mentionSelectionIndex: Int = 0
    @State private var suggestionToAdd: RoomAgentSuggestion? = nil

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

                // 워크플로우 단계 체크리스트
                if room.workflowState.intent != nil && room.isActive {
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
                    AgentSuggestionCard(suggestion: suggestion, roomID: room.id) {
                        suggestionToAdd = suggestion
                    }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                }
                .animation(.easeInOut(duration: 0.3), value: room.pendingAgentSuggestions.filter { $0.status == .pending }.count)

                // 팀 구성 확인 카드
                if let teamState = roomManager.pendingTeamConfirmation[room.id] {
                    TeamConfirmationCard(state: teamState, roomID: room.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 문서 유형 선택 카드 (documentation intent 선택 후)
                if roomManager.pendingDocTypeSelection[room.id] != nil {
                    DocTypeSelectionCard(roomID: room.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 승인 대기 카드 (승인 게이트 활성 시)
                if room.status == .awaitingApproval {
                    ApprovalCard(roomID: room.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 사용자 입력 카드
                if room.status == .awaitingUserInput {
                    if room.discussion.isCheckpoint {
                        DiscussionCheckpointCard(roomID: room.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        UserInputCard(roomID: room.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
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
            .sheet(item: $suggestionToAdd) { suggestion in
                AddAgentSheet(
                    prefillName: suggestion.name,
                    prefillPersona: suggestion.persona,
                    onCreated: { newAgent in
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
                .environmentObject(providerManager)
            }
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

                    // 작업 진행 중 타이핑 인디케이터 (활성 진행 정보를 흡수하여 표시)
                    if room.status == .planning || room.status == .inProgress {
                        TypingIndicator(roomID: room.id, agentStore: agentStore)
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
            .onChange(of: room.workflowState.currentPhase) { _, _ in
                scrollToBottom(proxy: proxy, room: room)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage, in room: Room) -> some View {
        MessageBubble(message: message)
            .id(message.id)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, room: Room) {
        // 작업 진행 중이면 TypingIndicator 하단까지 스크롤
        if room.status == .planning || room.status == .inProgress {
            withAnimation { proxy.scrollTo("typing-indicator", anchor: .bottom) }
        } else if let last = visibleMessages(room).last {
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

    /// 메인 채팅에 보이는 메시지
    /// - activityGroupID 소속 메시지: TypingIndicator 확장 영역에서 표시
    /// - .progress 메시지: TypingIndicator가 흡수 (인라인 표시 안 함)
    private func visibleMessages(_ room: Room) -> [ChatMessage] {
        room.messages.filter { msg in
            msg.activityGroupID == nil
                && msg.messageType != .approvalRequest
                && msg.messageType != .progress
        }
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
                if let intent = room.workflowState.intent {
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
        if let intent = room.workflowState.intent { text += " · \(intent.displayName)" }
        if let phase = room.workflowState.currentPhase { text += " · \(phase.rawValue)" }
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
                    ForEach(Array(mentionCandidates.enumerated()), id: \.element.id) { idx, agent in
                        Button {
                            insertMention(agent)
                        } label: {
                            HStack(spacing: 6) {
                                AgentAvatarView(agent: agent, size: 18)
                                Text(agent.name)
                                    .font(.system(size: 11, weight: idx == mentionSelectionIndex ? .bold : .regular))
                                    .foregroundColor(.primary)
                                Spacer()
                                if room.assignedAgentIDs.contains(agent.id) {
                                    Text("참여 중")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                idx == mentionSelectionIndex
                                    ? palette.accent.opacity(0.12)
                                    : Color.clear
                            )
                            .continuousRadius(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
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
                // 파일 첨부 버튼
                Button(action: pickFile) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("파일 첨부")

                textInputView(room)
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
            handleFileDrop(providers)
            return true
        }
    }

    private func textInputView(_ room: Room) -> some View {
        ScrollableTextInput(
            text: $inputText,
            placeholder: room.status == .inProgress ? "추가 요건을 입력하세요..." : "메시지를 입력하세요...",
            font: NSFont.systemFont(ofSize: 13),
            maxHeight: 80,
            onSubmit: {
                if !mentionCandidates.isEmpty {
                    let idx = min(mentionSelectionIndex, mentionCandidates.count - 1)
                    insertMention(mentionCandidates[idx])
                } else {
                    sendMessage()
                }
            },
            onSpecialKey: { key in
                switch key {
                case .upArrow:
                    guard !mentionCandidates.isEmpty else { return false }
                    mentionSelectionIndex = max(0, mentionSelectionIndex - 1)
                    return true
                case .downArrow:
                    guard !mentionCandidates.isEmpty else { return false }
                    mentionSelectionIndex = min(mentionCandidates.count - 1, mentionSelectionIndex + 1)
                    return true
                case .tab:
                    guard !mentionCandidates.isEmpty else { return false }
                    let idx = min(mentionSelectionIndex, mentionCandidates.count - 1)
                    insertMention(mentionCandidates[idx])
                    return true
                case .escape:
                    guard !mentionCandidates.isEmpty else { return false }
                    mentionCandidates = []
                    return true
                }
            },
            accessor: inputAccessor
        )
    }

    private func sendMessage() {
        inputAccessor.sync()  // NSTextView → SwiftUI 바인딩 동기화
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        let attachments = pendingAttachments.isEmpty ? nil : pendingAttachments
        inputAccessor.clear()  // NSTextView + 바인딩 + 높이 직접 초기화
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
        // 이미 방에 참여 중인 에이전트 제외
        let assignedIDs = room?.assignedAgentIDs ?? []
        let available = agentStore.subAgents.filter { !assignedIDs.contains($0.id) }
        if query.isEmpty {
            // @ 만 입력 → 전체 미참여 에이전트 목록 (최대 6명)
            mentionCandidates = Array(available.prefix(6))
        } else {
            // 쿼리로 필터
            mentionCandidates = available.filter {
                $0.name.lowercased().contains(query)
            }
        }
        mentionSelectionIndex = 0
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

    // MARK: - 파일 첨부

    private func pickFile() {
        // .nonactivatingPanel이 NSOpenPanel 클릭을 방해하므로 임시 해제 (NSColorPanel 제외)
        if NSColorPanel.shared.isVisible { NSColorPanel.shared.orderOut(nil) }
        let panels = NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.styleMask.contains(.nonactivatingPanel) && !($0 is NSColorPanel) }
        for p in panels { p.styleMask.remove(.nonactivatingPanel) }

        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)

        let openPanel = NSOpenPanel()
        var types: [UTType] = [.jpeg, .png, .gif, .webP, .pdf, .plainText, .commaSeparatedText, .json, .html, .xml, .sourceCode, .shellScript]
        if let yaml = UTType(filenameExtension: "yaml") { types.append(yaml) }
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        openPanel.allowedContentTypes = types
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.message = "첨부할 파일을 선택하세요"
        let response = openPanel.runModal()

        // 복원
        for p in panels { p.styleMask.insert(.nonactivatingPanel) }
        if wasAccessory && UtilityWindowManager.shared.windows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
        guard response == .OK else { return }
        for url in openPanel.urls {
            addFileFromURL(url)
        }
    }

    private func addFileFromURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let mime = FileAttachment.detectMimeType(for: url, data: data) else { return }
        guard let attachment = try? FileAttachment.save(data: data, mimeType: mime, originalFilename: url.lastPathComponent) else { return }
        pendingAttachments.append(attachment)
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        addFileFromURL(url)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data = data,
                          let mime = FileAttachment.mimeType(for: data),
                          let attachment = try? FileAttachment.save(data: data, mimeType: mime) else { return }
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
                Text("진행 중")
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
    @Environment(\.colorPalette) private var palette

    @State private var isExpanded = true

    var body: some View {
        CardContainer(accentColor: .purple) {
            VStack(alignment: .leading, spacing: 8) {
                // 헤더 (접이식)
                Button {
                    withAnimation(.dgStandard) { isExpanded.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.purple.opacity(0.7))
                        Text("작업 계획")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.purple.opacity(0.7))
                        Spacer()
                        Text("\(completedStepCount)/\(plan.steps.count)")
                            .font(DesignTokens.Typography.mono(DesignTokens.FontSize.xs))
                            .foregroundColor(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(plan.summary)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 3) {
                        ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                stepIcon(index: index)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.text)
                                        .font(.system(size: 11, weight: index == currentStep && status == .inProgress ? .semibold : .regular, design: .rounded))
                                        .foregroundColor(stepColor(index: index))
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let name = agentName(for: step) {
                                        Text(name)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(index == currentStep && status == .inProgress ? .orange.opacity(0.7) : .secondary.opacity(0.5))
                                    }
                                }
                                Spacer(minLength: 0)
                                if step.requiresApproval {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.orange.opacity(0.6))
                                        .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(index == currentStep && status == .inProgress
                                          ? Color.purple.opacity(0.06)
                                          : Color.clear)
                            )
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

    @MainActor private func agentName(for step: RoomStep) -> String? {
        guard let id = step.assignedAgentID,
              let agent = agentStore?.agents.first(where: { $0.id == id }) else { return nil }
        return agent.name
    }

    @ViewBuilder
    private func stepIcon(index: Int) -> some View {
        if status == .completed || index < currentStep {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.green.opacity(0.7))
        } else if index == currentStep && status == .inProgress {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange.opacity(0.7))
        } else {
            Image(systemName: "circle")
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.4))
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
}

// MARK: - 토론 진행 바

struct DiscussionProgressBar: View {
    let room: Room
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore

    /// 표시할 단계 (intake/intent 제외, needsPlan이면 .plan 동적 삽입)
    private var visiblePhases: [WorkflowPhase] {
        var phases = (room.workflowState.intent?.requiredPhases ?? [])
            .filter { $0 != .intake && $0 != .intent }
        // 사용자 직접 선택 방: assemble(팀 구성) 단계 숨김
        if room.createdBy == .user {
            let hasSubAgents = room.assignedAgentIDs.contains { id in
                agentStore.agents.first(where: { $0.id == id }).map { !$0.isMaster } ?? false
            }
            if hasSubAgents {
                phases.removeAll { $0 == .assemble }
            }
        }
        // needsPlan이 확정되면 .execute 앞에 .plan 삽입
        if room.workflowState.needsPlan, let idx = phases.firstIndex(of: .execute) {
            phases.insert(.plan, at: idx)
        }
        return phases
    }

    var body: some View {
        CardContainer(accentColor: .blue) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.blue.opacity(0.7))
                    Text("작업 진행")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.blue.opacity(0.7))
                    Spacer()
                    Text("\(completedCount)/\(visiblePhases.count)")
                        .font(DesignTokens.Typography.monoBadge)
                        .foregroundColor(.secondary)
                }

                // 단계별 체크리스트
                HStack(spacing: 0) {
                    ForEach(Array(visiblePhases.enumerated()), id: \.element) { index, phase in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.4))
                                .padding(.horizontal, 3)
                        }
                        HStack(spacing: 3) {
                            phaseIcon(phase)
                            Text(phase.displayName)
                                .font(.system(size: DesignTokens.FontSize.nano, weight: phaseWeight(phase), design: .rounded))
                                .foregroundColor(phaseTextColor(phase))
                                .lineLimit(1)
                        }
                    }
                }

                // 현재 활동 중인 에이전트 (토론: 발언 중, 작업: 작업 중)
                if let speakingName = speakingAgentName {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 12, height: 12)
                        let isDiscussion: Bool = {
                            if room.workflowState.intent == .discussion { return true }
                            switch room.workflowState.currentPhase {
                            case .build, .execute, .review: return false
                            default: return true
                            }
                        }()
                        Text("\(speakingName) \(isDiscussion ? "발언" : "작업") 중...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var completedCount: Int {
        if room.status == .completed { return visiblePhases.count }
        return visiblePhases.filter { room.workflowState.completedPhases.contains($0) }.count
    }

    @ViewBuilder
    private func phaseIcon(_ phase: WorkflowPhase) -> some View {
        if room.status == .completed || room.workflowState.completedPhases.contains(phase) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundColor(.green.opacity(0.7))
        } else if phase == room.workflowState.currentPhase {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 9))
                .foregroundColor(.orange.opacity(0.7))
        } else {
            Image(systemName: "circle")
                .font(.system(size: 9))
                .foregroundColor(.gray.opacity(0.4))
        }
    }

    private func phaseWeight(_ phase: WorkflowPhase) -> Font.Weight {
        phase == room.workflowState.currentPhase ? .bold : .regular
    }

    private func phaseTextColor(_ phase: WorkflowPhase) -> Color {
        if room.workflowState.completedPhases.contains(phase) || room.status == .completed {
            return .secondary
        } else if phase == room.workflowState.currentPhase {
            return .primary
        }
        return .secondary.opacity(0.6)
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
                    if let cmd = room.projectContext.buildCommand {
                        Text(cmd)
                            .font(DesignTokens.Typography.mono(DesignTokens.FontSize.badge))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if room.buildQA.buildRetryCount > 0 {
                    Text("\(room.buildQA.buildRetryCount)/\(room.buildQA.maxBuildRetries)")
                        .font(DesignTokens.Typography.monoStatus)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var statusText: String {
        switch room.buildQA.buildLoopStatus {
        case .building: return "빌드 실행 중..."
        case .fixing:   return "오류 수정 중..."
        case .passed:   return "빌드 성공"
        case .failed:   return "빌드 실패"
        case .idle, .none: return "빌드 대기"
        }
    }

    private var statusColor: Color {
        switch room.buildQA.buildLoopStatus {
        case .building: return .orange.opacity(0.7)
        case .fixing:   return .yellow.opacity(0.7)
        case .passed:   return .green.opacity(0.7)
        case .failed:   return .red.opacity(0.7)
        case .idle, .none: return .gray
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch room.buildQA.buildLoopStatus {
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

    /// 자동 승인 카운트다운 (nil이면 타이머 없음)
    private var autoApprovalRemaining: Int? {
        roomManager.reviewAutoApprovalRemaining[roomID]
    }

    /// 방의 최근 .approvalRequest 메시지에서 승인 제목과 내용을 추출
    private var approvalInfo: (title: String, detail: String?) {
        guard let room = roomManager.rooms.first(where: { $0.id == roomID }),
              let msg = room.messages.last(where: { $0.messageType == .approvalRequest }) else {
            return ("이해한 내용이 맞는지 확인해주세요", nil)
        }
        let content = msg.content
        if content.hasPrefix("실행 계획:") {
            return ("작업 계획을 확인해주세요", String(content.dropFirst("실행 계획:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if content.contains("이 단계는 승인이 필요합니다") {
            return ("단계 승인이 필요합니다", content)
        }
        if content.hasPrefix("토론이 완료되었습니다") {
            return ("토론 결과를 확인해주세요", String(content.dropFirst("토론이 완료되었습니다.".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if content.contains("보류된 작업") {
            return ("보류된 작업을 확인해주세요", content)
        }
        if content.contains("Review") && content.contains("실패") {
            return ("Review 실패 — 확인이 필요합니다", content)
        }
        if content.hasPrefix("설계 완료:") {
            return ("설계 결과를 확인해주세요", String(content.dropFirst("설계 완료:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if content.contains("추가할까요") {
            return ("에이전트 추가 제안", content)
        }
        if content.contains("결과를 확인해주세요") {
            return ("단계 결과를 확인해주세요", content)
        }
        return ("확인이 필요합니다", content)
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
                                let canSend = !feedbackText.trimmingCharacters(in: .whitespaces).isEmpty
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(canSend ? palette.accent : Color.gray.opacity(0.4))
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
                            roomManager.cancelReviewAutoApproval(roomID: roomID)
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
                            HStack(spacing: 6) {
                                Text("승인")
                                    .font(.system(size: 11, weight: .semibold))
                                if let remaining = autoApprovalRemaining {
                                    Text("\(remaining)s")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
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
    @State private var hoveredOption: Int?

    private var options: [String] {
        roomManager.pendingQuestionOptions[roomID] ?? []
    }

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

                // 선택지 버튼
                if !options.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            Button {
                                roomManager.answerUserQuestion(roomID: roomID, answer: option)
                            } label: {
                                HStack(spacing: 6) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16, height: 16)
                                        .background(palette.inputBackground)
                                        .continuousRadius(4)
                                    Text(option)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                                        .fill(hoveredOption == index ? palette.hoverBackground : palette.inputBackground.opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                                        .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    hoveredOption = hovering ? index : (hoveredOption == index ? nil : hoveredOption)
                                }
                            }
                        }
                    }
                }

                // 자유 입력
                HStack(spacing: 8) {
                    TextField(options.isEmpty ? "답변을 입력하세요..." : "또는 직접 입력...", text: $inputText)
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

                    let canSubmit = !inputText.trimmingCharacters(in: .whitespaces).isEmpty
                    Button { submit() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(canSubmit ? palette.accent : Color.gray.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
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

// MARK: - 토론 체크포인트 카드

struct DiscussionCheckpointCard: View {
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @Environment(\.colorPalette) private var palette
    @State private var inputText = ""
    @State private var countdown = 10
    @FocusState private var isFocused: Bool

    var body: some View {
        CardContainer(accentColor: .orange, opacity: 0.08) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.7))
                    Text("하실 말씀 있으신가요?")
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(countdown)초 후 자동 진행")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                }

                HStack(spacing: 8) {
                    TextField("방향 수정, 추가 요구사항...", text: $inputText)
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
                        .onSubmit { submitFeedback() }
                        .onChange(of: inputText) { _ in
                            countdown = 10  // 입력 중이면 타이머 리셋
                        }

                    let canSubmit = !inputText.trimmingCharacters(in: .whitespaces).isEmpty
                    Button { submitFeedback() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(canSubmit ? palette.accent : Color.gray.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)

                    Button { proceed() } label: {
                        Text("진행")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(palette.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(palette.accent.opacity(0.1))
                            .continuousRadius(8)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() }
                        else { NSCursor.pop() }
                    }
                }
            }
        }
        .onAppear {
            isFocused = true
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                if countdown > 1 {
                    countdown -= 1
                } else {
                    timer.invalidate()
                    proceed()
                }
            }
        }
    }

    private func submitFeedback() {
        let feedback = inputText.trimmingCharacters(in: .whitespaces)
        guard !feedback.isEmpty else { return }
        inputText = ""
        roomManager.answerUserQuestion(roomID: roomID, answer: feedback)
    }

    private func proceed() {
        roomManager.proceedDiscussion(roomID: roomID)
    }
}

// MARK: - Intent 선택 카드

struct IntentSelectionCard: View {
    let roomID: UUID
    let suggestedIntent: WorkflowIntent
    @EnvironmentObject var roomManager: RoomManager
    @Environment(\.colorPalette) private var palette
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    private let intents = WorkflowIntent.allCases

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
                    Text("↑↓ 선택  ↵ 확인")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                VStack(spacing: 4) {
                    ForEach(Array(intents.enumerated()), id: \.element) { index, intent in
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
                            .background(
                                index == selectedIndex
                                    ? Color.teal.opacity(0.12)
                                    : (intent == suggestedIntent ? Color.teal.opacity(0.08) : palette.inputBackground)
                            )
                            .foregroundColor(index == selectedIndex ? .teal : (intent == suggestedIntent ? .teal.opacity(0.7) : .primary))
                            .continuousRadius(DesignTokens.CozyGame.cardRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                                    .strokeBorder(
                                        index == selectedIndex ? Color.teal.opacity(0.4) : (intent == suggestedIntent ? Color.teal.opacity(0.2) : palette.cardBorder.opacity(0.1)),
                                        lineWidth: index == selectedIndex ? 1.5 : 1
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(intents.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            roomManager.selectIntent(roomID: roomID, intent: intents[selectedIndex])
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            if let num = Int(press.characters), num >= 1, num <= intents.count {
                roomManager.selectIntent(roomID: roomID, intent: intents[num - 1])
                return .handled
            }
            return .ignored
        }
        .onAppear {
            // 추천 intent를 초기 선택으로
            if let idx = intents.firstIndex(of: suggestedIntent) {
                selectedIndex = idx
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }

    private func intentIcon(_ intent: WorkflowIntent) -> String {
        intent.iconName
    }
}

// MARK: - 문서 유형 선택 카드

struct DocTypeSelectionCard: View {
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @Environment(\.colorPalette) private var palette
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    private let docTypes = DocumentType.allCases

    var body: some View {
        CardContainer(accentColor: .indigo, opacity: 0.08) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.caption)
                        .foregroundColor(.indigo.opacity(0.7))
                    Text("문서 유형을 선택해주세요")
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Text("↑↓ 선택  ↵ 확인")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                VStack(spacing: 4) {
                    ForEach(Array(docTypes.enumerated()), id: \.element) { index, docType in
                        Button {
                            roomManager.selectDocType(roomID: roomID, docType: docType)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: docType.iconName)
                                    .font(.system(size: 10))
                                    .frame(width: 14)
                                Text(docType.displayName)
                                    .font(.caption2.bold())
                                Spacer()
                                Text(docType.subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                index == selectedIndex
                                    ? Color.indigo.opacity(0.12)
                                    : palette.inputBackground
                            )
                            .foregroundColor(index == selectedIndex ? .indigo : .primary)
                            .continuousRadius(DesignTokens.CozyGame.cardRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                                    .strokeBorder(
                                        index == selectedIndex ? Color.indigo.opacity(0.4) : palette.cardBorder.opacity(0.1),
                                        lineWidth: index == selectedIndex ? 1.5 : 1
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(docTypes.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            roomManager.selectDocType(roomID: roomID, docType: docTypes[selectedIndex])
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            if let num = Int(press.characters), num >= 1, num <= docTypes.count {
                roomManager.selectDocType(roomID: roomID, docType: docTypes[num - 1])
                return .handled
            }
            return .ignored
        }
        .onAppear {
            // freeform을 초기 선택으로 (마지막 항목)
            selectedIndex = docTypes.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}

// MARK: - 에이전트 생성 제안 카드

struct AgentSuggestionCard: View {
    let suggestion: RoomAgentSuggestion
    let roomID: UUID
    var onAdd: () -> Void
    @EnvironmentObject var roomManager: RoomManager
    @Environment(\.colorPalette) private var palette

    var body: some View {
        CardContainer(accentColor: palette.accent, opacity: 0.06) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.caption)
                        .foregroundColor(palette.accent.opacity(0.7))
                    Text("에이전트 생성 제안")
                        .font(.caption2.bold())
                        .foregroundColor(palette.accent.opacity(0.7))
                    Spacer()
                    Text(suggestion.suggestedBy)
                        .font(.system(size: DesignTokens.FontSize.badge))
                        .foregroundColor(palette.textSecondary)
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

                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        roomManager.rejectAgentSuggestion(suggestionID: suggestion.id, in: roomID)
                    } label: {
                        Text("취소")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(palette.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                                    .fill(palette.inputBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                                    .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: palette.buttonShadow.opacity(0.1), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAdd()
                    } label: {
                        Text("추가")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [palette.accent.opacity(0.9), palette.accent],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                            )
                            .shadow(color: palette.buttonShadow.opacity(0.25), radius: 4, y: DesignTokens.CozyGame.buttonShadowY)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 팀 구성 확인 카드

struct TeamConfirmationCard: View {
    let state: TeamConfirmationState
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore
    @Environment(\.colorPalette) private var palette

    var body: some View {
        CardContainer(accentColor: palette.accent, opacity: 0.06) {
            VStack(alignment: .leading, spacing: 8) {
                // 헤더
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.caption)
                        .foregroundColor(palette.accent.opacity(0.7))
                    Text(state.isEditing ? "참여 전문가 변경" : "참여 전문가")
                        .font(.caption2.bold())
                        .foregroundColor(palette.accent.opacity(0.7))
                }

                if state.isEditing {
                    editingBody
                } else {
                    confirmBody
                }
            }
        }
    }

    // MARK: - 기본 모드: 확인

    private var confirmBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedAgents.isEmpty {
                Text("작업을 담당할 에이전트를 선택하세요.")
                    .font(.system(size: DesignTokens.FontSize.xs))
                    .foregroundColor(.secondary)
            } else {
                ForEach(selectedAgents) { agent in
                    agentRow(agent: agent, isSelected: true, interactive: false)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                if !candidateAgents.isEmpty || selectedAgents.isEmpty {
                    cardButton("변경") {
                        roomManager.startEditingTeam(roomID: roomID)
                    }
                }
                if !selectedAgents.isEmpty {
                    cardButton("이대로 진행", primary: true) {
                        roomManager.confirmTeam(roomID: roomID)
                    }
                } else {
                    cardButton("취소") {
                        roomManager.skipTeamConfirmation(roomID: roomID)
                    }
                }
            }
        }
    }

    // MARK: - 편집 모드

    private var editingBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 현재 선택된 + 후보를 합쳐서 표시
            let allAgents = allEditableAgents
            ForEach(allAgents) { agent in
                let isSelected = state.selectedAgentIDs.contains(agent.id)
                Button {
                    roomManager.toggleAgentInTeam(roomID: roomID, agentID: agent.id)
                } label: {
                    agentRow(agent: agent, isSelected: isSelected, interactive: true)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Spacer()
                if !state.selectedAgentIDs.isEmpty {
                    cardButton("확인", primary: true) {
                        roomManager.confirmEditedTeam(roomID: roomID)
                    }
                } else {
                    cardButton("취소") {
                        roomManager.skipTeamConfirmation(roomID: roomID)
                    }
                }
            }
        }
    }

    // MARK: - 공통 컴포넌트

    private func agentRow(agent: Agent, isSelected: Bool, interactive: Bool) -> some View {
        HStack(spacing: 10) {
            if interactive {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(isSelected ? palette.accent : .secondary)
            }
            AgentAvatarView(agent: agent, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Text(String(agent.persona.prefix(50)) + (agent.persona.count > 50 ? "..." : ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func cardButton(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(primary ? .white : palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                        .fill(primary ? palette.accent : palette.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: primary ? 0 : 1)
                )
                .shadow(color: palette.buttonShadow.opacity(0.1), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 데이터

    private var selectedAgents: [Agent] {
        state.selectedAgentIDs.compactMap { id in agentStore.agents.first(where: { $0.id == id }) }
            .sorted { $0.name < $1.name }
    }

    private var candidateAgents: [Agent] {
        state.candidateAgentIDs.compactMap { id in agentStore.agents.first(where: { $0.id == id }) }
            .sorted { $0.name < $1.name }
    }

    private var allEditableAgents: [Agent] {
        let allIDs = Array(state.selectedAgentIDs) + state.candidateAgentIDs
        let unique = Array(Set(allIDs))
        return unique.compactMap { id in agentStore.agents.first(where: { $0.id == id }) }
            .sorted { a, b in
                let aSelected = state.selectedAgentIDs.contains(a.id)
                let bSelected = state.selectedAgentIDs.contains(b.id)
                if aSelected != bSelected { return aSelected }
                return a.name < b.name
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
                    if let cmd = room.projectContext.testCommand {
                        Text(cmd)
                            .font(DesignTokens.Typography.mono(DesignTokens.FontSize.badge))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if room.buildQA.qaRetryCount > 0 {
                    Text("\(room.buildQA.qaRetryCount)/\(room.buildQA.maxQARetries)")
                        .font(DesignTokens.Typography.monoStatus)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var qaStatusText: String {
        switch room.buildQA.qaLoopStatus {
        case .testing:   return "테스트 실행 중..."
        case .analyzing: return "실패 분석/수정 중..."
        case .passed:    return "테스트 통과"
        case .failed:    return "테스트 실패"
        case .idle, .none: return "테스트 대기"
        }
    }

    private var qaStatusColor: Color {
        switch room.buildQA.qaLoopStatus {
        case .testing:   return .teal.opacity(0.7)
        case .analyzing: return .yellow.opacity(0.7)
        case .passed:    return .green.opacity(0.7)
        case .failed:    return .red.opacity(0.7)
        case .idle, .none: return .gray
        }
    }

    @ViewBuilder
    private var qaStatusIcon: some View {
        switch room.buildQA.qaLoopStatus {
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

