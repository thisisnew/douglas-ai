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

                // 빌드 상태 카드 (빌드 루프 활성 시)
                if let buildStatus = room.buildLoopStatus, buildStatus != .idle {
                    BuildStatusCard(room: room)
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
                            roomAttachmentThumbnail(att)
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

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(canSend ? .accentColor : .gray)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
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

    @ViewBuilder
    private func roomAttachmentThumbnail(_ attachment: ImageAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            if let data = try? attachment.loadData(), let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }

            Button {
                attachment.delete()
                pendingAttachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

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
        VStack(alignment: .leading, spacing: 4) {
            // 헤더 (접이식)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
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
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                // 요약
                Text(plan.summary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // 단계 목록
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 6) {
                        stepIcon(index: index)
                        Text(step)
                            .font(.caption2)
                            .foregroundColor(stepColor(index: index))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
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
        .padding(8)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 4) {
            // 헤더 (접이식)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
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
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                                    .font(.system(size: 8, design: .monospaced))
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
        .padding(8)
        .background(Color.indigo.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - 빌드 상태 카드

struct BuildStatusCard: View {
    let room: Room

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
                if let cmd = room.buildCommand {
                    Text(cmd)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if room.buildRetryCount > 0 {
                Text("\(room.buildRetryCount)/\(room.maxBuildRetries)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(statusColor.opacity(0.06))
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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
