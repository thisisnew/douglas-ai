import Foundation

/// 에이전트 응답 끝에 붙은 선택지 텍스트 제거 (예: "1. 다음(구현) 2. 수정할래요 x. 나가기")
func stripTrailingOptions(_ text: String) -> String {
    // 마지막 수 줄 이내에서 번호+선택지 패턴을 감지하여 제거
    let lines = text.components(separatedBy: "\n")
    guard lines.count >= 2 else { return text }

    // 뒤에서부터 빈 줄 + 코드블록 닫는 마커(```) 스킵
    var endIndex = lines.count
    while endIndex > 0 {
        let trimmed = lines[endIndex - 1].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.allSatisfy({ $0 == "`" }) {
            endIndex -= 1
        } else {
            break
        }
    }

    // 선택지 라인 패턴: "1." "2." "x." 또는 "1)" 등으로 시작 + 짧은 텍스트
    let optionPattern = #"^\s*(\d+|[xX])\s*[.)]\s*.+"#
    guard let regex = try? NSRegularExpression(pattern: optionPattern) else { return text }

    var optionStart = endIndex
    var optionCount = 0
    for i in stride(from: endIndex - 1, through: max(0, endIndex - 6), by: -1) {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        let range = NSRange(line.startIndex..., in: line)
        if regex.firstMatch(in: line, range: range) != nil {
            optionStart = i
            optionCount += 1
        } else {
            break
        }
    }

    // 선택지 2개 이상일 때만 제거 (단일 번호 항목은 일반 내용일 수 있음)
    guard optionCount >= 2 else { return text }

    // 선택지 바로 위의 구분선(---)도 함께 제거
    var cleanStart = optionStart
    if cleanStart > 0 {
        let above = lines[cleanStart - 1].trimmingCharacters(in: .whitespaces)
        if !above.isEmpty && above.allSatisfy({ $0 == "-" }) {
            cleanStart -= 1
        }
    }

    let kept = Array(lines[0..<cleanStart])
    return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Clarify 응답에서 Jira/인증 관련 환각 문장 제거 (안전망)
func stripHallucinatedAuthLines(_ text: String) -> String {
    let patterns: [String] = [
        "인증 정보", "API 토큰", "자격증명", "설정되어 있지",
        "MCP 도구", "MCP 서버", "직접 호출할 수 있는",
        "직접 제공", "직접 확인해", "연결되어 있지 않",
        "접근할 수 없", "접근 권한", "Jira API를 직접",
    ]

    let lines = text.components(separatedBy: "\n")
    let filtered = lines.filter { line in
        !patterns.contains(where: { line.contains($0) })
    }

    return filtered.joined(separator: "\n")
        .replacingOccurrences(of: "\n\n\n", with: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// LLM 응답의 `~/` 경로를 절대경로로 확장
func expandTildePaths(_ text: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return text.replacingOccurrences(of: "~/", with: "\(home)/")
}

/// clarify 응답에서 [delegation] 블록을 파싱하여 DelegationInfo 반환
/// 파싱 실패 시 .open 폴백 (기존 assemble 흐름)
func parseDelegationBlock(_ text: String) -> DelegationInfo {
    guard let startRange = text.range(of: "[delegation]"),
          let endRange = text.range(of: "[/delegation]"),
          startRange.upperBound < endRange.lowerBound else {
        return DelegationInfo(type: .open, agentNames: [])
    }

    let blockContent = String(text[startRange.upperBound..<endRange.lowerBound])
    let lines = blockContent.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

    var type: DelegationInfo.DelegationType = .open
    var agentNames: [String] = []

    for line in lines {
        if line.lowercased().hasPrefix("type:") {
            let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased()
            if value == "explicit" { type = .explicit }
        } else if line.lowercased().hasPrefix("agents:") {
            let value = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            agentNames = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }

    return DelegationInfo(type: type, agentNames: agentNames)
}

/// [delegation]...[/delegation] 블록을 텍스트에서 제거
func stripDelegationBlock(_ text: String) -> String {
    guard let startRange = text.range(of: "[delegation]"),
          let endRange = text.range(of: "[/delegation]") else {
        return text
    }
    var result = text
    result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 스트리밍 청크 누적용 스레드-안전 버퍼 (NSLock 동기화)
final class StreamBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = ""
    var current: String {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func append(_ chunk: String) -> String {
        lock.lock()
        _value += chunk
        let result = _value
        lock.unlock()
        return result
    }
}

/// 팀 구성 확인 게이트 상태
struct TeamConfirmationState: Equatable {
    /// 현재 선택된 에이전트 (자동 매칭된 + 사용자 추가)
    var selectedAgentIDs: Set<UUID>
    /// 추가 가능한 에이전트 (방에 없는 서브에이전트)
    var candidateAgentIDs: [UUID]
    /// "구성 변경" 편집 모드 여부
    var isEditing: Bool = false
}

@MainActor
class RoomManager: ObservableObject, WorkflowHost {
    @Published var rooms: [Room] = []
    @Published var selectedRoomID: UUID?
    /// 마스터 위임으로 자동 생성된 방 → UI에서 자동으로 창을 열기 위한 트리거
    @Published var pendingAutoOpenRoomID: UUID?
    /// 방별 현재 발언 중인 에이전트 (UI 표시용, 영속화 안 함)
    @Published var speakingAgentIDByRoom: [UUID: UUID] = [:]
    /// Intent 선택 대기 중인 방 (방 ID → LLM 추천 intent)
    @Published var pendingIntentSelection: [UUID: WorkflowIntent] = [:]
    /// 문서 유형 선택 대기 중인 방 (향후 재활용 가능)
    @Published var pendingDocTypeSelection: [UUID: Bool] = [:]
    /// 팀 구성 확인 대기 중인 방 (방 ID → 확인 상태)
    @Published var pendingTeamConfirmation: [UUID: TeamConfirmationState] = [:]
    /// 리뷰 게이트 자동 승인 카운트다운 (방 ID → 남은 초)
    @Published var reviewAutoApprovalRemaining: [UUID: Int] = [:]

    private(set) var agentStore: AgentStore?
    private(set) var providerManager: ProviderManager?
    private var timerTask: Task<Void, Never>?
    var saveTask: Task<Void, Never>?
    /// 방별 워크플로우 태스크 (취소 가능)
    var roomTasks: [UUID: Task<Void, Never>] = [:]
    /// 시스템 프롬프트 캐시 — 같은 에이전트+규칙 조합의 반복 생성 방지
    var systemPromptCache = SystemPromptCache()
    /// 승인/입력 게이트 관리자 — 모든 continuation 소유
    let approvalGates = ApprovalGateManager()
    /// 리뷰 게이트 자동 승인 타이머 태스크 (취소용) — internal for extension access
    var reviewAutoApprovalTasks: [UUID: Task<Void, Never>] = [:]
    /// 이전 사이클 완료 시점의 에이전트 수 (후속 사이클에서 에이전트 변동 감지용)
    var previousCycleAgentCount: [UUID: Int] = [:]
    /// ask_user 도구의 선택지 (방 ID → 옵션 목록) — UserInputCard에서 버튼으로 표시
    @Published var pendingQuestionOptions: [UUID: [String]] = [:]

    /// 플러그인 이벤트 디스패치 (PluginManager가 설정)
    var pluginEventDelegate: ((PluginEvent) -> Void)?

    /// 플러그인 도구 인터셉트 (PluginManager가 설정)
    var pluginInterceptToolDelegate: ((String, [String: String]) async -> ToolInterceptResult)?

    /// 플러그인 주입 skillTags 조회 (PluginManager가 설정)
    var pluginSkillTagsProvider: ((_ agent: Agent) -> [String])?

    /// 플러그인 주입 규칙 조회 (PluginManager가 설정)
    var pluginRulesProvider: ((_ agent: Agent) -> [String])?

    /// Hook dispatch (HookManager가 설정)
    var hookDispatch: ((_ trigger: HookTrigger, _ context: HookContext) async -> [HookResult])?

    deinit {
        timerTask?.cancel()
        saveTask?.cancel()
        for task in roomTasks.values { task.cancel() }
        for task in reviewAutoApprovalTasks.values { task.cancel() }
    }

    // MARK: - 계산 프로퍼티

    var activeRooms: [Room] {
        rooms.filter { $0.isActive }.sorted { $0.createdAt > $1.createdAt }
    }

    var completedRooms: [Room] {
        rooms.filter { !$0.isActive }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    var selectedRoom: Room? {
        guard let id = selectedRoomID else { return nil }
        return rooms.first { $0.id == id }
    }

    /// 마스터 에이전트(진행자) 이름 — 시스템 메시지에 사용
    var masterAgentName: String {
        agentStore?.masterAgent?.name ?? "DOUGLAS"
    }

    // MARK: - WorkflowHost

    func room(for id: UUID) -> Room? {
        rooms.first(where: { $0.id == id })
    }

    func updateRoom(id: UUID, _ mutate: (inout Room) -> Void) {
        guard let idx = rooms.firstIndex(where: { $0.id == id }) else { return }
        mutate(&rooms[idx])
    }

    // MARK: - 초기화

    func configure(agentStore: AgentStore, providerManager: ProviderManager) {
        self.agentStore = agentStore
        self.providerManager = providerManager
        startTimerRefresh()
    }

    // MARK: - 방 생성

    /// 마스터 위임 또는 사용자가 방 생성
    @discardableResult
    func createRoom(title: String, agentIDs: [UUID], createdBy: RoomCreator, mode: RoomMode = .task, projectPaths: [String] = [], buildCommand: String? = nil, testCommand: String? = nil, intent: WorkflowIntent? = nil) -> Room {
        var room = Room(
            title: title,
            assignedAgentIDs: agentIDs,
            createdBy: createdBy,
            mode: mode,
            projectPaths: projectPaths,
            buildCommand: buildCommand,
            testCommand: testCommand
        )
        if let intent { room.workflowState.setIntent(intent) }

        // 초기 에이전트의 참조 프로젝트를 방에 병합
        for agentID in agentIDs {
            if let agent = agentStore?.agents.first(where: { $0.id == agentID }) {
                for path in agent.referenceProjectPaths {
                    if !room.projectContext.projectPaths.contains(path) {
                        room.projectContext.projectPaths.append(path)
                    }
                }
            }
        }

        rooms.append(room)
        selectedRoomID = room.id
        syncAgentStatuses()
        scheduleSave()
        pluginEventDelegate?(.roomCreated(roomID: room.id, title: room.title))
        return room
    }

    /// 사용자 수동 방 생성 + 바로 작업 시작. 생성된 roomID 반환.
    @discardableResult
    func createManualRoom(title: String, agentIDs: [UUID], task: String, projectPaths: [String] = [], buildCommand: String? = nil, testCommand: String? = nil, intent: WorkflowIntent? = nil, attachments: [FileAttachment]? = nil) -> UUID {
        // 마스터를 첫 번째로 배치 (intake/clarify는 항상 마스터가 수행)
        var orderedIDs = agentIDs
        if let masterID = agentStore?.masterAgent?.id {
            orderedIDs.removeAll { $0 == masterID }
            orderedIDs.insert(masterID, at: 0)
        }
        let room = createRoom(title: title, agentIDs: orderedIDs, createdBy: .user, projectPaths: projectPaths, buildCommand: buildCommand, testCommand: testCommand, intent: intent)

        // 사용자 메시지 추가
        let userMsg = ChatMessage(role: .user, content: task, attachments: attachments)
        appendMessage(userMsg, to: room.id)

        // 워크플로우 시작 (추적 가능)
        launchWorkflow(roomID: room.id, task: task)
        return room.id
    }

    /// 워크플로우를 추적 가능한 Task로 시작
    func launchWorkflow(roomID: UUID, task: String) {
        roomTasks[roomID]?.cancel()
        roomTasks[roomID] = Task { [weak self] in
            await self?.startRoomWorkflow(roomID: roomID, task: task)
            self?.roomTasks.removeValue(forKey: roomID)
        }
    }

    // MARK: - Hook Dispatch

    /// Hook 실행 후 결과를 시스템 메시지로 표시
    func dispatchHookAndNotify(trigger: HookTrigger, roomID: UUID, roomTitle: String?) {
        guard let hookDispatch else { return }
        Task {
            let results = await hookDispatch(trigger, HookContext(roomID: roomID, roomTitle: roomTitle))
            guard let text = results.summaryText else { return }
            await MainActor.run {
                let msg = ChatMessage(role: .system, content: text, messageType: .progress)
                self.appendMessage(msg, to: roomID)
            }
        }
    }

    // MARK: - 방에 메시지 추가

    func appendMessage(_ message: ChatMessage, to roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        rooms[idx].messages.append(message)
        scheduleSave()
        pluginEventDelegate?(.messageAdded(roomID: roomID, message: message))
    }

    /// 특정 메시지 앞에 삽입 (도구 활동을 스트리밍 placeholder 앞에 배치할 때 사용)
    func insertMessage(_ message: ChatMessage, to roomID: UUID, beforeMessageID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        if let insertIdx = rooms[idx].messages.firstIndex(where: { $0.id == beforeMessageID }) {
            rooms[idx].messages.insert(message, at: insertIdx)
        } else {
            rooms[idx].messages.append(message)
        }
        scheduleSave()
        pluginEventDelegate?(.messageAdded(roomID: roomID, message: message))
    }

    /// 스트리밍: 기존 메시지 content를 in-place로 업데이트
    func updateMessageContent(_ messageID: UUID, newContent: String, in roomID: UUID) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
              let msgIdx = rooms[roomIdx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        rooms[roomIdx].messages[msgIdx].content = newContent
    }

    // MARK: - Phase Activity Tracking

    /// LLM 호출을 ProgressActivityBubble로 추적하는 헬퍼.
    /// .progress 부모 + llm_call 시작 + body 실행 + llm_result/llm_error 완료.
    @discardableResult
    func trackPhaseActivity(
        roomID: UUID,
        label: String,
        agentName: String?,
        modelName: String,
        providerName: String,
        body: @escaping (_ onToolActivity: @escaping (String, ToolActivityDetail?) -> Void) async throws -> String
    ) async throws -> (response: String, progressGroupID: UUID) {
        let progressMsg = ChatMessage(
            role: .system,
            content: label,
            messageType: .progress
        )
        appendMessage(progressMsg, to: roomID)
        let groupID = progressMsg.id

        // 시작 활동: 모델 + 단계 정보
        let startDetail = ToolActivityDetail(
            toolName: "llm_call",
            subject: "\(providerName) · \(modelName)",
            contentPreview: nil,
            isError: false
        )
        let startMsg = ChatMessage(
            role: .assistant,
            content: label,
            agentName: agentName,
            messageType: .toolActivity,
            activityGroupID: groupID,
            toolDetail: startDetail
        )
        appendMessage(startMsg, to: roomID)

        let onToolActivity: (String, ToolActivityDetail?) -> Void = { [weak self] activity, detail in
            guard let self else { return }
            Task { @MainActor in
                let toolMsg = ChatMessage(
                    role: .assistant,
                    content: activity,
                    agentName: agentName,
                    messageType: .toolActivity,
                    activityGroupID: groupID,
                    toolDetail: detail
                )
                self.appendMessage(toolMsg, to: roomID)
            }
        }

        let startTime = Date()
        do {
            let response = try await body(onToolActivity)
            let duration = Date().timeIntervalSince(startTime)
            let durationStr = duration < 60
                ? String(format: "%.1f초", duration)
                : String(format: "%d분 %.0f초", Int(duration) / 60, duration.truncatingRemainder(dividingBy: 60))
            let resultDetail = ToolActivityDetail(
                toolName: "llm_result",
                subject: "\(durationStr) | \(response.count)자",
                contentPreview: nil,
                isError: false
            )
            let resultActivity = ChatMessage(
                role: .assistant,
                content: "응답 완료 (\(durationStr))",
                agentName: agentName,
                messageType: .toolActivity,
                activityGroupID: groupID,
                toolDetail: resultDetail
            )
            appendMessage(resultActivity, to: roomID)
            return (response, groupID)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            let durationStr = String(format: "%.1f초", duration)
            let errorDetail = ToolActivityDetail(
                toolName: "llm_error",
                subject: error.userFacingMessage,
                contentPreview: nil,
                isError: true
            )
            let errorActivity = ChatMessage(
                role: .assistant,
                content: "오류 (\(durationStr)): \(error.userFacingMessage)",
                agentName: agentName,
                messageType: .toolActivity,
                activityGroupID: groupID,
                toolDetail: errorDetail
            )
            appendMessage(errorActivity, to: roomID)
            throw error
        }
    }

    // 문서 처리 메서드 → RoomManager+Document.swift

    // MARK: - 카테고리 기반 모델 오버라이드


    // MARK: - 도구 실행 컨텍스트

    func makeToolContext(
        roomID: UUID,
        currentAgentID: UUID? = nil,
        fileWriteTracker: FileWriteTracker? = nil,
        workingDirectoryOverride: String? = nil
    ) -> ToolExecutionContext {
        guard let store = agentStore else { return .empty }
        let subAgents = store.subAgents
        let room = rooms.first { $0.id == roomID }
        let currentAgent = currentAgentID.flatMap { id in
            store.agents.first { $0.id == id }
        }
        let currentAgentName = currentAgent?.name

        // 단계별 workingDirectory 오버라이드: 지정된 경로를 projectPaths[0]으로 배치
        let resolvedPaths: [String] = {
            var paths = room?.effectiveProjectPaths ?? []
            guard let override = workingDirectoryOverride else { return paths }
            paths.removeAll { $0 == override }
            paths.insert(override, at: 0)
            return paths
        }()

        return ToolExecutionContext(
            roomID: roomID,
            agentsByName: Dictionary(uniqueKeysWithValues: subAgents.map { ($0.name, $0.id) }),
            agentListString: subAgents
                .map { "- \($0.name) [\($0.providerName)/\($0.modelName)]" }
                .joined(separator: "\n"),
            inviteAgent: { @Sendable [weak self] (agentID: UUID) -> Bool in
                await MainActor.run { [weak self] in
                    self?.addAgent(agentID, to: roomID)
                    return true
                }
            },
            suggestAgentCreation: { @Sendable [weak self] (suggestion: RoomAgentSuggestion) -> Bool in
                await MainActor.run { [weak self] in
                    self?.addAgentSuggestion(suggestion, to: roomID)
                    return true
                }
            },
            projectPaths: resolvedPaths,
            currentAgentID: currentAgentID,
            currentAgentName: currentAgentName,
            agentPermissions: currentAgent?.actionPermissions ?? [],
            fileWriteTracker: fileWriteTracker,
            askUser: { @Sendable [weak self] (question: String, context: String?, options: [String]?) -> String in
                // 1) 질문 메시지 추가 + 상태 전이 (MainActor)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var content = question
                    if let ctx = context { content += "\n\n배경: \(ctx)" }
                    // 선택지는 메시지에 텍스트로 넣지 않고 UI 버튼으로 표시
                    if let opts = options, !opts.isEmpty {
                        self.pendingQuestionOptions[roomID] = opts
                    } else {
                        self.pendingQuestionOptions.removeValue(forKey: roomID)
                    }
                    let msg = ChatMessage(role: .assistant, content: content, agentName: currentAgentName, messageType: .userQuestion)
                    self.appendMessage(msg, to: roomID)
                    if let idx = self.rooms.firstIndex(where: { $0.id == roomID }) {
                        self.rooms[idx].transitionTo(.awaitingUserInput)
                    }
                    self.scheduleSave()
                }
                // 2) 사용자 답변 대기 (approvalGates)
                guard let self else { return "" }
                let answer: String = await self.approvalGates.waitForUserInput(roomID: roomID)
                // 3) 상태 복귀 (MainActor) — 취소/완료된 방이면 무시
                await MainActor.run { [weak self] in
                    if let self, let idx = self.rooms.firstIndex(where: { $0.id == roomID }),
                       self.rooms[idx].isActive {
                        self.rooms[idx].transitionTo(.planning)
                    }
                }
                return answer
            },
            currentPhase: room?.workflowState.currentPhase,
            fetchPendingUserMessages: {
                // 컨텍스트 생성 시점의 메시지 수를 기준점으로 캡처
                let baselineCount = room?.messages.count ?? 0
                let checkpoint = MessageCheckpoint(baselineCount)
                return { @Sendable [weak self] () async -> [ConversationMessage] in
                    await MainActor.run { [weak self] () -> [ConversationMessage] in
                        guard let self, let room = self.rooms.first(where: { $0.id == roomID }) else { return [] }
                        let currentCount = room.messages.count
                        let base = checkpoint.value
                        guard currentCount > base else { return [] }
                        let newMsgs = room.messages[base..<currentCount].compactMap { msg -> ConversationMessage? in
                            guard msg.role == .user, msg.messageType == .text,
                                  !msg.content.isEmpty else { return nil }
                            return .user(msg.content)
                        }
                        if !newMsgs.isEmpty {
                            checkpoint.value = currentCount
                        }
                        return newMsgs
                    }
                }
            }(),
            dispatchPluginEvent: { @Sendable [weak self] event in
                Task { @MainActor [weak self] in
                    self?.pluginEventDelegate?(event)
                }
            },
            interceptTool: { @Sendable [weak self] toolName, arguments in
                guard let delegate = await MainActor.run(body: { self?.pluginInterceptToolDelegate }) else {
                    return .passthrough
                }
                return await delegate(toolName, arguments)
            }
        )
    }

    // 에이전트 생성 제안 + 방 에이전트 추가 메서드 → RoomManager+AgentSuggestion.swift
    // 워크플로우 실행 메서드 → RoomManager+Workflow.swift
    // 빌드/QA + 토론 메서드 → RoomManager+Discussion.swift


    // MARK: - 유틸리티

    static func parseDecisionContent(from text: String) -> String? {
        // [합의: 내용] 형태
        if let range = text.range(of: "\\[합의:\\s*([^\\]]+)\\]", options: .regularExpression) {
            let matched = String(text[range])
            // ":" 이후 내용 추출
            if let colonIdx = matched.firstIndex(of: ":") {
                let content = matched[matched.index(after: colonIdx)..<matched.index(before: matched.endIndex)]
                    .trimmingCharacters(in: .whitespaces)
                return content.isEmpty ? nil : content
            }
        }
        return nil
    }

    static func wordOverlapSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init))
        let wordsB = Set(b.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0.0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union)
    }

    // MARK: - 방 제목 자동 추출

    /// clarify 요약에서 "요청 내용:" 줄을 추출하여 방 제목으로 사용
    static func extractTitleFromClarifySummary(_ summary: String) -> String {
        for line in summary.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "- 요청 내용: ..." 또는 "요청 내용: ..." 패턴
            if let range = trimmed.range(of: "요청 내용:", options: .caseInsensitive) {
                var title = String(trimmed[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                // 마크다운 볼드 제거
                title = title.replacingOccurrences(of: "**", with: "")
                if title.count > 30 {
                    title = String(title.prefix(28)) + "…"
                }
                return title.isEmpty ? "" : title
            }
        }
        return ""
    }

    // MARK: - 작업일지 생성

    func generateWorkLog(roomID: UUID, task: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            // API 없어도 기본 일지는 생성
            createFallbackLog(roomID: roomID, task: task)
            return
        }

        let participants = room.assignedAgentIDs.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })?.name
        }
        let duration = Int(Date().timeIntervalSince(room.createdAt))

        let history = buildDiscussionHistory(roomID: roomID, currentAgentName: nil)

        let logPrompt = """
        아래 작업방의 전체 과정을 작업일지로 정리하세요.

        형식 (반드시 이 형식만 사용):
        [결과] 한 줄 요약
        [토론] 핵심 합의 사항 (1-2줄)
        [계획] 실행한 단계 요약 (1-2줄)
        [비고] 특이사항 또는 후속 작업 (있으면)

        총 5줄 이내. 군더더기 없이 팩트만.
        """

        do {
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "작업일지를 생성하는 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { _ in
                // sendRouterMessage: 도구 비활성화 (작업일지 생성 중 파일 수정 방지)
                try await provider.sendRouterMessage(
                    model: agent.modelName,
                    systemPrompt: logPrompt,
                    messages: history + [("user", "작업: \(task)")]
                )
            }

            // 토론 요약 추출 (summary 타입 메시지에서)
            let discussionSummary = room.messages
                .first(where: { $0.messageType == .summary })?.content ?? ""
            let planSummary = room.plan?.summary ?? ""

            let log = WorkLog(
                roomTitle: room.title,
                participants: participants,
                task: task,
                discussionSummary: discussionSummary,
                planSummary: planSummary,
                outcome: response,
                durationSeconds: duration
            )

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].setWorkLog(log)
            }

            scheduleSave()
        } catch {
            createFallbackLog(roomID: roomID, task: task)
        }
    }

    private func createFallbackLog(roomID: UUID, task: String) {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let participants = room.assignedAgentIDs.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })?.name
        }
        let duration = Int(Date().timeIntervalSince(room.createdAt))

        let log = WorkLog(
            roomTitle: room.title,
            participants: participants,
            task: task,
            discussionSummary: room.messages.first(where: { $0.messageType == .summary })?.content ?? "",
            planSummary: room.plan?.summary ?? "",
            outcome: "작업 완료",
            durationSeconds: duration
        )

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].setWorkLog(log)
        }
        scheduleSave()
    }

    // MARK: - 방 상태 관리

    func completeRoom(_ roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        // 진행 중인 워크플로우 취소
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        cleanupWorktree(roomID: roomID)
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        // 대기 중인 continuation 해제
        approvalGates.cancelAll(for: roomID)
        pendingTeamConfirmation.removeValue(forKey: roomID)
        pendingIntentSelection.removeValue(forKey: roomID)
        pendingDocTypeSelection.removeValue(forKey: roomID)
        rooms[idx].complete()
        // 에이전트 수 스냅샷 (다음 후속 사이클에서 변동 감지용)
        previousCycleAgentCount[roomID] = executingAgentIDs(in: roomID).count

        // 작업일지 생성 (수동 완료 시에도, 이미 있으면 중복 생성 방지)
        if rooms[idx].workLog == nil {
            let task = rooms[idx].messages.first(where: { $0.role == .user })?.content ?? rooms[idx].title
            Task { await generateWorkLog(roomID: roomID, task: task) }
        }

        syncAgentStatuses()
        scheduleSave()

        // Hook dispatch: 작업 완료 → 결과를 시스템 메시지로 표시
        let roomTitle = rooms[idx].title
        dispatchHookAndNotify(trigger: .roomCompleted, roomID: roomID, roomTitle: roomTitle)
    }

    /// 사용자가 승인 카드에서 취소 → 작업 종료
    func cancelRoom(roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        cleanupWorktree(roomID: roomID)
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        approvalGates.cancelAll(for: roomID)
        pendingTeamConfirmation.removeValue(forKey: roomID)
        pendingIntentSelection.removeValue(forKey: roomID)
        pendingDocTypeSelection.removeValue(forKey: roomID)
        rooms[idx].cancel()
        let msg = ChatMessage(role: .system, content: "사용자가 작업을 취소했습니다.", messageType: .error)
        appendMessage(msg, to: roomID)
        syncAgentStatuses()
        scheduleSave()
    }

    func completeRooms(_ roomIDs: Set<UUID>) {
        for roomID in roomIDs {
            completeRoom(roomID)
        }
    }

    func deleteRooms(_ roomIDs: Set<UUID>) {
        for roomID in roomIDs {
            deleteRoom(roomID)
        }
    }

    func deleteRoom(_ roomID: UUID) {
        // 진행 중인 워크플로우 취소
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        cleanupWorktree(roomID: roomID)
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        // 대기 중인 모든 continuation 해제 (누수 방지)
        approvalGates.cancelAll(for: roomID)
        pendingTeamConfirmation.removeValue(forKey: roomID)
        pendingIntentSelection.removeValue(forKey: roomID)
        pendingDocTypeSelection.removeValue(forKey: roomID)

        // 첨부 이미지 파일 삭제
        if let room = rooms.first(where: { $0.id == roomID }) {
            for msg in room.messages {
                msg.attachments?.forEach { $0.delete() }
            }
        }

        rooms.removeAll { $0.id == roomID }
        if selectedRoomID == roomID { selectedRoomID = nil }

        // 저장 파일 삭제
        let file = Self.roomDirectory.appendingPathComponent("\(roomID.uuidString).json")
        try? FileManager.default.removeItem(at: file)

        syncAgentStatuses()
        scheduleSave()
    }

    // MARK: - 에이전트 상태 동기화

    func syncAgentStatuses() {
        guard let agentStore = agentStore else { return }

        for agent in agentStore.agents where !agent.isMaster {
            let activeCount = rooms.filter { room in
                room.isActive && room.assignedAgentIDs.contains(agent.id)
            }.count

            let newStatus: AgentStatus
            switch activeCount {
            case 0: newStatus = .idle
            case 1...2: newStatus = .working
            default: newStatus = .busy   // 3개+ 활성 방 참여 시 바쁨
            }

            if agent.status != .error {
                agentStore.updateStatus(agentID: agent.id, status: newStatus)
            }
        }
    }

    /// 에이전트가 참여 중인 활성 방 수
    func activeRoomCount(for agentID: UUID) -> Int {
        rooms.filter { $0.isActive && $0.assignedAgentIDs.contains(agentID) }.count
    }

    /// 에이전트가 속한 전체 방 수 (완료 포함)
    func totalRoomCount(for agentID: UUID) -> Int {
        rooms.filter { $0.assignedAgentIDs.contains(agentID) }.count
    }

    // MARK: - 타이머

    private func startTimerRefresh() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                // @Published 변경 트리거 (remainingSeconds는 computed이므로 UI 갱신용)
                if rooms.contains(where: { $0.status == .inProgress }) {
                    objectWillChange.send()
                }
            }
        }
    }

    // MARK: - 대화 히스토리

    /// 간단한 (role, content) 튜플 히스토리 (토론/요약 등 내부 호출용)
    /// ConversationMessage 히스토리 (이미지 첨부 포함, smartSend용)
    func buildRoomHistory(roomID: UUID, limit: Int = 20, afterIndex: Int? = nil) -> [ConversationMessage] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        let base: ArraySlice<ChatMessage>
        if let offset = afterIndex, offset < room.messages.count {
            base = room.messages[offset...]
        } else {
            base = room.messages[...]
        }
        return base
            .filter { $0.messageType == .text }
            .suffix(limit)
            .map { msg in
                let role: String
                switch msg.role {
                case .user:      role = "user"
                case .assistant: role = "assistant"
                case .system:    role = "user"
                }
                return ConversationMessage(
                    role: role,
                    content: msg.content.count > 2000
                        ? String(msg.content.prefix(2000)) + "…"
                        : msg.content,
                    toolCalls: nil,
                    toolCallID: nil,
                    attachments: msg.attachments,
                    isError: false
                )
            }
    }

    // MARK: - 한글 조사 헬퍼

    /// 마지막 글자의 받침 유무에 따라 "이"/"가" 반환
    func subjectParticle(for name: String) -> String {
        guard let last = name.last else { return "이" }
        guard let scalar = last.unicodeScalars.first else { return "이" }
        let v = scalar.value
        guard (0xAC00...0xD7A3).contains(v) else { return "가" }   // 비한글(영문 등)
        return (v - 0xAC00) % 28 == 0 ? "가" : "이"               // 받침 없으면 "가"
    }
}
