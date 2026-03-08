import SwiftUI

/// 채팅 하단에 표시되는 작업 진행 중 애니메이션
/// 클릭하면 현재 단계의 세부 활동(모델 정보, 도구 사용, 소요시간)이 펼쳐짐
struct TypingIndicator: View {
    @Environment(\.colorPalette) private var palette
    let roomID: UUID
    let agentStore: AgentStore
    @EnvironmentObject var roomManager: RoomManager
    @State private var dotPhase = 0
    @State private var isExpanded = false
    @State private var expandedActivityIDs: Set<UUID> = []

    /// roomManager에서 실시간 room 상태를 읽음 (snapshot이 아닌 live)
    private var room: Room? {
        roomManager.rooms.first(where: { $0.id == roomID })
    }

    /// 현재 발언 중인 에이전트 (토론 턴)
    private var speakingAgent: Agent? {
        if let speakingID = roomManager.speakingAgentIDByRoom[roomID],
           let agent = agentStore.agents.first(where: { $0.id == speakingID }) {
            return agent
        }
        return nil
    }

    /// 마스터가 주도하는 단계: intake~assemble + plan
    private var isMasterPhase: Bool {
        guard let phase = room?.workflowState.currentPhase else { return true }
        switch phase {
        case .intake, .intent, .clarify, .assemble, .plan:
            return true
        default:
            return false
        }
    }

    /// 작업 중인 에이전트 (발언자가 아닌 경우)
    private var workingAgent: Agent? {
        guard let room else { return nil }
        if isMasterPhase {
            // 초기 단계: 마스터를 바로 반환 (status 체크 불필요 — syncAgentStatuses가 마스터를 건너뜀)
            if let master = room.assignedAgentIDs.lazy.compactMap({ id in
                agentStore.agents.first(where: { $0.id == id && $0.isMaster })
            }).first {
                return master
            }
        }
        // 실행 단계 또는 마스터 없음: 서브 에이전트 우선
        for id in room.assignedAgentIDs {
            if let agent = agentStore.agents.first(where: { $0.id == id }),
               !agent.isMaster,
               agent.status == .working || agent.status == .busy {
                return agent
            }
        }
        for id in room.assignedAgentIDs {
            if let agent = agentStore.agents.first(where: { $0.id == id }),
               agent.status == .working || agent.status == .busy {
                return agent
            }
        }
        return nil
    }

    /// 토론 vs 작업 구분: discussion intent이거나 design 단계면 "발언 중", build/execute면 "작업 중"
    private var isDiscussionPhase: Bool {
        guard let room else { return false }
        if room.workflowState.intent == .discussion { return true }
        switch room.workflowState.currentPhase {
        case .build, .execute, .review:
            return false
        default:
            return true
        }
    }

    private var statusText: String {
        let verb = isDiscussionPhase ? "발언 중" : "작업 중"
        // 1순위: 명시적 발언자 (speakingAgentIDByRoom — LLM 호출 중 설정됨)
        if let agent = speakingAgent {
            return agent.isMaster ? "DOUGLAS 분석 중" : "\(agent.name) \(verb)"
        }
        // 2순위: 토론 요약 중 (plan 단계 + 브리핑 미생성 + 토론 이력 있음)
        if let room, room.workflowState.currentPhase == .plan && room.discussion.briefing == nil
            && room.messages.contains(where: { $0.messageType == .discussionRound }) {
            return "토론을 요약하는 중"
        }
        // 3순위: 에이전트 활동 중 (agent.status 기반 — 마스터 단계에서는 마스터 우선)
        if let agent = workingAgent {
            return agent.isMaster ? "DOUGLAS 분석 중" : "\(agent.name) \(verb)"
        }
        // 기본
        return "DOUGLAS 분석 중"
    }

    /// 마지막 활성 progress 그룹의 활동 메시지들 — roomManager에서 실시간 읽기
    private var activeActivities: [ChatMessage] {
        guard let room, room.isActive else { return [] }
        let progressMessages = room.messages.filter { $0.messageType == .progress }
        guard let lastProgress = progressMessages.last else { return [] }
        return room.messages.filter { $0.activityGroupID == lastProgress.id }
    }

    var body: some View {
        if room != nil {
            VStack(spacing: 0) {
                // 헤더 (항상 보임) — 클릭으로 세부 활동 펼침
                Button {
                    guard !activeActivities.isEmpty else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    headerView
                }
                .buttonStyle(.plain)

                // 확장 영역: 세부 활동 로그
                if isExpanded, !activeActivities.isEmpty {
                    expandedView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - 헤더

    /// 현재 실행 중인 단계 정보
    private var currentStepInfo: (number: Int, total: Int, label: String)? {
        guard let room, let plan = room.plan,
              room.currentStepIndex < plan.steps.count,
              [WorkflowPhase.build, .execute].contains(room.workflowState.currentPhase) else { return nil }
        return (room.currentStepIndex + 1, plan.steps.count, plan.steps[room.currentStepIndex].text)
    }

    /// 최근 파일 수정 활동 (접힌 상태에서도 표시)
    private var lastFileWriteDetail: ToolActivityDetail? {
        activeActivities.last(where: {
            ["file_write", "Edit", "Write"].contains($0.toolDetail?.toolName ?? "")
        })?.toolDetail
    }

    private var headerView: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = elapsedSeconds(at: context.date)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // 점 3개 바운스 애니메이션
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(palette.accent.opacity(0.7))
                                .frame(width: 6, height: 6)
                                .offset(y: dotPhase == i ? -4 : 0)
                                .scaleEffect(dotPhase == i ? 1.2 : 1.0)
                        }
                    }

                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))

                    if elapsed >= 3 {
                        Text(elapsedLabel(elapsed))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.35))
                    }

                    // 최근 활동 요약 (접힌 상태에서 한 줄로 표시)
                    if !isExpanded, let lastDetail = activeActivities.last?.toolDetail {
                        Text("· \(lastDetail.displayName)\(lastDetail.subject.map { " \(shortenPath($0))" } ?? "")")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    // 활동 개수 뱃지 + 펼침 화살표
                    if !activeActivities.isEmpty {
                        Text("\(activeActivities.count)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(Capsule())

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }

                // 현재 단계 정보 (Build/Execute 중에만 표시)
                if let info = currentStepInfo {
                    HStack(spacing: 4) {
                        Text("단계 \(info.number)/\(info.total):")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(palette.accent.opacity(0.7))
                        Text(info.label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(palette.accent.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.leading, 26) // 점 애니메이션 너비만큼 들여쓰기
                }

                // 파일 수정 활동 (접힌 상태에서도 항상 표시)
                if let writeDetail = lastFileWriteDetail {
                    Text("· \(writeDetail.displayName) \(shortenPath(writeDetail.subject ?? ""))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                        .lineLimit(1)
                        .padding(.leading, 26)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                .fill(palette.panelGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: palette.sidebarShadow, radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.dgSpring) {
                    dotPhase = (dotPhase + 1) % 3
                }
            }
        }
    }

    // MARK: - 확장 영역 (활동 로그)

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(activeActivities) { activity in
                activityRow(activity)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func activityRow(_ activity: ChatMessage) -> some View {
        let hasPreview = activity.toolDetail?.contentPreview != nil
        let isDetailExpanded = expandedActivityIDs.contains(activity.id)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard hasPreview else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isDetailExpanded {
                        expandedActivityIDs.remove(activity.id)
                    } else {
                        expandedActivityIDs.insert(activity.id)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: activityIcon(activity))
                        .font(.system(size: 9))
                        .foregroundColor(activityColor(activity))
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 1) {
                        // 한국어 도구명 + 대상 (subject와 중복 시 content 대신 displayName 사용)
                        if let detail = activity.toolDetail {
                            Text("\(detail.displayName)\(detail.subject.map { " → \(shortenPath($0))" } ?? "")")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.6))
                                .lineLimit(2)
                        } else {
                            Text(activity.content)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.6))
                                .lineLimit(2)
                        }

                        // 파일 경로 전체 (subject가 경로일 때)
                        if let subject = activity.toolDetail?.subject,
                           isFilePath(subject) {
                            Text(subject)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.45))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()

                    if hasPreview {
                        Image(systemName: isDetailExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary.opacity(0.3))
                    }

                    Text(timeLabel(activity.timestamp))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)

            // 상세 미리보기 (확장 시)
            if isDetailExpanded, let preview = activity.toolDetail?.contentPreview {
                previewBlock(preview)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 상세 미리보기 블록
    private func previewBlock(_ preview: String) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(preview)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.inputBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.vertical, 2)
    }

    /// 경로 축약 (파일명만 표시)
    private func shortenPath(_ path: String) -> String {
        guard path.contains("/") else { return path }
        let components = path.components(separatedBy: "/")
        if components.count > 3 {
            return "…/" + components.suffix(2).joined(separator: "/")
        }
        return path
    }

    /// subject가 파일 경로인지 판별
    private func isFilePath(_ text: String) -> Bool {
        text.hasPrefix("/") || text.hasPrefix("~/") || text.contains(".swift") || text.contains(".java") || text.contains(".ts")
    }

    // MARK: - Helpers

    private func activityIcon(_ activity: ChatMessage) -> String {
        guard let detail = activity.toolDetail else { return "arrow.right.circle" }
        if detail.isError { return "xmark.circle" }
        switch detail.toolName {
        case "llm_call":   return "arrow.up.circle"
        case "llm_result": return "checkmark.circle.fill"
        case "llm_error":  return "xmark.octagon"
        case "file_read", "Read":   return "doc.text"
        case "file_write", "Write": return "doc.badge.plus"
        case "shell_exec", "Bash":  return "terminal"
        case "web_search", "WebSearch": return "magnifyingglass"
        case "web_fetch", "WebFetch":   return "globe"
        case "Glob":  return "folder.badge.questionmark"
        case "Grep":  return "text.magnifyingglass"
        case "Edit":  return "pencil"
        default:      return "checkmark.circle"
        }
    }

    private func activityColor(_ activity: ChatMessage) -> Color {
        guard let detail = activity.toolDetail else { return .secondary.opacity(0.5) }
        return detail.isError ? .red.opacity(0.6) : .green.opacity(0.6)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 마지막 메시지 이후 경과 시간
    private func elapsedSeconds(at date: Date) -> Int {
        guard let room else { return 0 }
        let lastMessageTime = room.messages.last?.timestamp ?? room.createdAt
        return max(0, Int(date.timeIntervalSince(lastMessageTime)))
    }

    private func elapsedLabel(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)초"
        }
        let min = seconds / 60
        let sec = seconds % 60
        return "\(min)분 \(sec)초"
    }
}
