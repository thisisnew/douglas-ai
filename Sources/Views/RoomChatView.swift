import SwiftUI
import UniformTypeIdentifiers

// MARK: - 방 채팅 뷰

struct RoomChatView: View {
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore
    @State private var inputText = ""
    @State private var pendingAttachments: [ImageAttachment] = []
    @State private var showDeleteConfirm = false
    @FocusState private var isInputFocused: Bool

    private var room: Room? {
        roomManager.rooms.first { $0.id == roomID }
    }

    var body: some View {
        if let room = room {
            VStack(spacing: 0) {
                // 방 헤더
                roomHeader(room)

                Divider()

                // 토론 진행 바 (계획 수립 전)
                if room.plan == nil && room.status == .planning {
                    DiscussionProgressBar(room: room)
                }

                // 산출물 바 (산출물이 있을 때)
                if !room.artifacts.isEmpty {
                    ArtifactListBar(artifacts: room.artifacts)
                }

                // 에이전트 생성 제안 카드
                ForEach(room.pendingAgentSuggestions.filter { $0.status == .pending }) { suggestion in
                    AgentSuggestionCard(suggestion: suggestion, roomID: room.id)
                }

                // 승인 대기 카드 (승인 게이트 활성 시)
                if room.status == .awaitingApproval {
                    ApprovalCard(roomID: room.id)
                }

                // 사용자 입력 카드 (ask_user 도구 활성 시)
                if room.status == .awaitingUserInput {
                    UserInputCard(roomID: room.id)
                }

                // 계획 카드 (계획 수립 후)
                if let plan = room.plan {
                    PlanCard(plan: plan, currentStep: room.currentStepIndex, status: room.status)
                }

                // 메시지 목록
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(room.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: room.messages.count) { _, _ in
                        if let last = room.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                // 입력 영역
                if room.isActive {
                    inputArea(room)
                }
            }
        }
    }

    // MARK: - 방 헤더

    private func roomHeader(_ room: Room) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(room.title)
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer()

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
                        NSApp.keyWindow?.close()
                    }
                } message: {
                    Text("진행 중인 작업이 있으면 즉시 중단됩니다.")
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
                                    isSpeaking ? Color.green : Color(nsColor: .windowBackgroundColor),
                                    lineWidth: isSpeaking ? 2 : 1
                                )
                            )
                            .opacity(isSpeaking ? 1.0 : 0.7)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
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

            HStack(spacing: 8) {
                // 이미지 첨부 버튼
                Button(action: pickImage) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("이미지 첨부")

                TextField("메시지를 입력하세요...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                SendButton(canSend: canSend, isLoading: false, action: sendMessage)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
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
        Task { await roomManager.sendUserMessage(text.isEmpty ? "[이미지]" : text, to: roomID, attachments: attachments) }
    }

    // MARK: - 이미지 첨부

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .gif, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "첨부할 이미지를 선택하세요"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
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
                Text(room.discussionProgressText)
                    .font(.caption2)
                    .foregroundColor(DesignTokens.RoomStatusColor.color(for: .planning))
            case .inProgress:
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text("진행중")
                    .font(.caption2)
                    .foregroundColor(.orange)
            case .awaitingApproval:
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.yellow)
                Text("승인 대기")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            case .awaitingUserInput:
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.cyan)
                Text("입력 대기")
                    .font(.caption2)
                    .foregroundColor(.cyan)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
                Text("완료")
                    .font(.caption2)
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                Text("실패")
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Text("·")
                .foregroundColor(.secondary.opacity(0.4))
            Text(Self.shortDateFormatter.string(from: room.createdAt))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d HH:mm"
        return f
    }()
}

// MARK: - 계획 카드

struct PlanCard: View {
    let plan: RoomPlan
    let currentStep: Int
    let status: RoomStatus

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
                            .font(.caption2)
                            .foregroundColor(.purple)
                        Text("작업 계획")
                            .font(.caption2.bold())
                            .foregroundColor(.purple)
                        Spacer()
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
                                    .foregroundColor(.orange)
                            }
                            Text(step.text)
                                .font(.caption2)
                                .foregroundColor(stepColor(index: index))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(index: Int) -> some View {
        if status == .completed || index < currentStep {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundColor(.green)
        } else if index == currentStep && status == .inProgress {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 9))
                .foregroundColor(.orange)
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
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text("토론 진행")
                        .font(.caption2.bold())
                        .foregroundColor(.blue)
                    Spacer()
                    Text(room.discussionProgressText)
                        .font(DesignTokens.Typography.monoBadge)
                        .foregroundColor(.secondary)
                }

            // 프로그레스 바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.1))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * progressRatio, height: 4)
                }
            }
            .frame(height: 4)

            // 현재 발언 중인 에이전트 또는 참여자 수
            if let speakingName = speakingAgentName {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 12, height: 12)
                    Text("\(speakingName) 발언 중...")
                        .font(.caption2)
                        .foregroundColor(.green)
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
        guard room.maxDiscussionRounds > 0 else { return 0 }
        return CGFloat(room.currentRound) / CGFloat(room.maxDiscussionRounds)
    }

    private var speakingAgentName: String? {
        guard let agentID = roomManager.speakingAgentIDByRoom[room.id] else { return nil }
        return agentStore.agents.first(where: { $0.id == agentID })?.name
    }
}

// MARK: - 산출물 목록 바

struct ArtifactListBar: View {
    let artifacts: [DiscussionArtifact]
    @State private var isExpanded = true
    @State private var expandedArtifactID: UUID?

    var body: some View {
        CardContainer(accentColor: .indigo) {
            VStack(alignment: .leading, spacing: 4) {
                // 헤더 (접이식)
                Button {
                    withAnimation(.dgStandard) { isExpanded.toggle() }
                } label: {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.caption2)
                        .foregroundColor(.indigo)
                    Text("산출물 (\(artifacts.count))")
                        .font(.caption2.bold())
                        .foregroundColor(.indigo)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(artifacts) { artifact in
                    Button {
                        withAnimation(.dgStandard) {
                            if expandedArtifactID == artifact.id {
                                expandedArtifactID = nil
                            } else {
                                expandedArtifactID = artifact.id
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: artifact.type.icon)
                                    .font(.system(size: 9))
                                    .foregroundColor(.indigo)
                                Text(artifact.title)
                                    .font(.caption2.bold())
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text("v\(artifact.version)")
                                    .font(DesignTokens.Typography.mono(DesignTokens.FontSize.nano))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(artifact.producedBy)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }

                            if expandedArtifactID == artifact.id {
                                Text(artifact.content)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            }
        }
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
        case .building: return .orange
        case .fixing:   return .yellow
        case .passed:   return .green
        case .failed:   return .red
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
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
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
    @State private var additionalInput: String = ""

    var body: some View {
        CardContainer(accentColor: .yellow, opacity: 0.08) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text("분석 결과를 확인해주세요")
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                    Spacer()
                }

                TextEditor(text: $additionalInput)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 36, maxHeight: 80)
                    .padding(6)
                    .background(DesignTokens.Colors.inputBackground)
                    .continuousRadius(DesignTokens.Radius.md)
                    .overlay(
                        Group {
                            if additionalInput.isEmpty {
                                Text("추가 요구사항이 있으면 입력하세요...")
                                    .font(.callout)
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.leading, 10)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }, alignment: .topLeading
                    )

                HStack(spacing: 8) {
                    Spacer()
                    Button("취소") {
                        roomManager.rejectStep(roomID: roomID)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DesignTokens.Colors.inputBackground)
                    .continuousRadius(DesignTokens.Radius.md)

                    Button(additionalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "승인" : "추가 후 승인") {
                        if !additionalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            roomManager.appendAdditionalInput(roomID: roomID, text: additionalInput.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        roomManager.approveStep(roomID: roomID)
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .continuousRadius(DesignTokens.Radius.md)
                }
            }
        }
    }
}

// MARK: - 사용자 입력 카드

struct UserInputCard: View {
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        CardContainer(accentColor: .cyan, opacity: 0.08) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.cyan)
                    Text("에이전트가 추가 정보를 요청합니다")
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                }

                HStack(spacing: 8) {
                    TextField("답변을 입력하세요...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(6)
                        .background(Color.primary.opacity(DesignTokens.Opacity.inputBg))
                        .continuousRadius(DesignTokens.Radius.md)
                        .focused($isFocused)
                        .onSubmit { submit() }

                    Button("전송") { submit() }
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.cyan)
                        .continuousRadius(DesignTokens.Radius.md)
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

// MARK: - 에이전트 생성 제안 카드

struct AgentSuggestionCard: View {
    let suggestion: RoomAgentSuggestion
    let roomID: UUID
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore
    @State private var showAddSheet = false

    var body: some View {
        CardContainer(accentColor: .orange, opacity: 0.06) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("에이전트 생성 제안")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
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
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .continuousRadius(DesignTokens.Radius.md)

                    Button("추가") {
                        showAddSheet = true
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .continuousRadius(DesignTokens.Radius.md)
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
                    roomManager.addAgent(newAgent.id, to: roomID)
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
        case .testing:   return .teal
        case .analyzing: return .yellow
        case .passed:    return .green
        case .failed:    return .red
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
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.shield.fill")
                .font(.caption)
                .foregroundColor(.red)
        case .idle, .none:
            Image(systemName: "checkmark.shield")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}
