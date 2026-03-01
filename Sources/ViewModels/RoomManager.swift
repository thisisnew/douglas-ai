import Foundation

@MainActor
class RoomManager: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var selectedRoomID: UUID?
    /// 마스터 위임으로 자동 생성된 방 → UI에서 자동으로 창을 열기 위한 트리거
    @Published var pendingAutoOpenRoomID: UUID?
    /// 방별 현재 발언 중인 에이전트 (UI 표시용, 영속화 안 함)
    @Published var speakingAgentIDByRoom: [UUID: UUID] = [:]

    private(set) var agentStore: AgentStore?
    private(set) var providerManager: ProviderManager?
    private var timerTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    /// 방별 워크플로우 태스크 (취소 가능)
    private var roomTasks: [UUID: Task<Void, Never>] = [:]
    /// 승인 게이트 대기 중인 continuation (방 ID → continuation)
    private var approvalContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// 사용자 입력 대기 중인 continuation (방 ID → continuation)
    private var userInputContinuations: [UUID: CheckedContinuation<String, Never>] = [:]
    /// 에이전트 생성 제안 승인 대기 continuation (방 ID → continuation, Bool = 사용자 응답 여부)
    private var suggestionContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]

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

    // MARK: - 초기화

    func configure(agentStore: AgentStore, providerManager: ProviderManager) {
        self.agentStore = agentStore
        self.providerManager = providerManager
        startTimerRefresh()
    }

    // MARK: - 방 생성

    /// 마스터 위임 또는 사용자가 방 생성
    @discardableResult
    func createRoom(title: String, agentIDs: [UUID], createdBy: RoomCreator, mode: RoomMode = .task, maxDiscussionRounds: Int = 3, projectPaths: [String] = [], buildCommand: String? = nil, testCommand: String? = nil, intent: WorkflowIntent? = nil) -> Room {
        var room = Room(
            title: title,
            assignedAgentIDs: agentIDs,
            createdBy: createdBy,
            mode: mode,
            maxDiscussionRounds: maxDiscussionRounds,
            projectPaths: projectPaths,
            buildCommand: buildCommand,
            testCommand: testCommand
        )
        room.intent = intent
        rooms.append(room)
        selectedRoomID = room.id
        syncAgentStatuses()
        scheduleSave()
        return room
    }

    /// 사용자 수동 방 생성 + 바로 작업 시작
    func createManualRoom(title: String, agentIDs: [UUID], task: String, projectPaths: [String] = [], buildCommand: String? = nil, testCommand: String? = nil, intent: WorkflowIntent? = nil) {
        let room = createRoom(title: title, agentIDs: agentIDs, createdBy: .user, projectPaths: projectPaths, buildCommand: buildCommand, testCommand: testCommand, intent: intent)

        // 사용자 메시지 추가
        let userMsg = ChatMessage(role: .user, content: task)
        appendMessage(userMsg, to: room.id)

        // 워크플로우 시작 (추적 가능)
        launchWorkflow(roomID: room.id, task: task)
    }

    /// 워크플로우를 추적 가능한 Task로 시작
    func launchWorkflow(roomID: UUID, task: String) {
        roomTasks[roomID]?.cancel()
        roomTasks[roomID] = Task {
            await startRoomWorkflow(roomID: roomID, task: task)
            roomTasks.removeValue(forKey: roomID)
        }
    }

    // MARK: - 방에 메시지 추가

    func appendMessage(_ message: ChatMessage, to roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        rooms[idx].messages.append(message)
        scheduleSave()
    }

    // MARK: - 승인 게이트

    /// 승인 대기 중인 단계를 승인
    func approveStep(roomID: UUID) {
        guard let cont = approvalContinuations.removeValue(forKey: roomID) else { return }
        let msg = ChatMessage(role: .user, content: "승인")
        appendMessage(msg, to: roomID)
        cont.resume(returning: true)
    }

    /// 승인 대기 중인 단계를 거부
    func rejectStep(roomID: UUID) {
        guard let cont = approvalContinuations.removeValue(forKey: roomID) else { return }
        let msg = ChatMessage(role: .user, content: "거부")
        appendMessage(msg, to: roomID)
        // 즉시 planning으로 전환하여 승인 카드 숨김
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].transitionTo(.planning)
        }
        cont.resume(returning: false)
    }

    /// 승인 카드에서 추가 요구사항 입력 시 방 메시지에 추가
    func appendAdditionalInput(roomID: UUID, text: String) {
        let msg = ChatMessage(role: .user, content: text)
        appendMessage(msg, to: roomID)
    }

    // MARK: - 사용자 입력 게이트

    /// ask_user 도구에 대한 사용자 답변 제출
    func answerUserQuestion(roomID: UUID, answer: String) {
        guard let cont = userInputContinuations.removeValue(forKey: roomID) else { return }
        let msg = ChatMessage(role: .user, content: answer)
        appendMessage(msg, to: roomID)
        // userAnswers에 저장 (질문은 메시지에서 역추적)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            let userAnswer = UserAnswer(question: "", answer: answer)
            if rooms[idx].userAnswers == nil { rooms[idx].userAnswers = [] }
            rooms[idx].userAnswers?.append(userAnswer)
        }
        cont.resume(returning: answer)
    }

    /// 사용자가 방에 메시지 보내기
    func sendUserMessage(_ text: String, to roomID: UUID, attachments: [ImageAttachment]? = nil) async {
        let userMsg = ChatMessage(role: .user, content: text, attachments: attachments)
        appendMessage(userMsg, to: roomID)

        guard let room = rooms.first(where: { $0.id == roomID }) else { return }

        // 작업 진행 중: 추가 요건으로만 삽입 (현재 에이전트가 다음 호출에서 자연스럽게 참고)
        if room.isActive {
            let noteMsg = ChatMessage(
                role: .system,
                content: "추가 요건이 반영되었습니다."
            )
            appendMessage(noteMsg, to: roomID)
            scheduleSave()
            return
        }

        // 완료/실패 상태: 전문가에게 위임하여 응답
        let targetID = room.assignedAgentIDs.first(where: { id in
            agentStore?.agents.first(where: { $0.id == id })?.isMaster == false
        }) ?? room.assignedAgentIDs.first

        guard let agentID = targetID,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        // 방을 활성화하고 작업 중 표시
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].transitionTo(.inProgress)
        }
        speakingAgentIDByRoom[roomID] = agentID

        let context = makeToolContext(roomID: roomID)
        let history = buildRoomHistory(roomID: roomID)
        do {
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: agent.resolvedSystemPrompt,
                conversationMessages: history,
                context: context
            )
            let reply = ChatMessage(role: .assistant, content: response, agentName: agent.name)
            appendMessage(reply, to: roomID)
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "오류: \(error.localizedDescription)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }

        // 작업 완료 → 방 상태 복귀
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].transitionTo(.completed)
            rooms[idx].completedAt = Date()
        }
        scheduleSave()
    }

    // MARK: - 도구 실행 컨텍스트

    private func makeToolContext(
        roomID: UUID,
        currentAgentID: UUID? = nil,
        fileWriteTracker: FileWriteTracker? = nil
    ) -> ToolExecutionContext {
        guard let store = agentStore else { return .empty }
        let subAgents = store.subAgents
        let room = rooms.first { $0.id == roomID }
        let currentAgentName = currentAgentID.flatMap { id in
            store.agents.first { $0.id == id }?.name
        }
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
            projectPaths: room?.projectPaths ?? [],
            currentAgentID: currentAgentID,
            currentAgentName: currentAgentName,
            fileWriteTracker: fileWriteTracker,
            askUser: { @Sendable [weak self] (question: String, context: String?, options: [String]?) -> String in
                // 1) 질문 메시지 추가 + 상태 전이 (MainActor)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var content = question
                    if let ctx = context { content += "\n\n배경: \(ctx)" }
                    if let opts = options, !opts.isEmpty {
                        content += "\n\n선택지:\n" + opts.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                    }
                    let msg = ChatMessage(role: .assistant, content: content, agentName: currentAgentName, messageType: .userQuestion)
                    self.appendMessage(msg, to: roomID)
                    if let idx = self.rooms.firstIndex(where: { $0.id == roomID }) {
                        self.rooms[idx].transitionTo(.awaitingUserInput)
                    }
                    self.scheduleSave()
                }
                // 2) 사용자 답변 대기 (continuation)
                let answer: String = await withCheckedContinuation { continuation in
                    Task { @MainActor [weak self] in
                        self?.userInputContinuations[roomID] = continuation
                    }
                }
                // 3) 상태 복귀 (MainActor)
                await MainActor.run { [weak self] in
                    if let self, let idx = self.rooms.firstIndex(where: { $0.id == roomID }) {
                        self.rooms[idx].transitionTo(.planning)
                    }
                }
                return answer
            },
            currentPhase: room?.currentPhase
        )
    }

    // MARK: - 에이전트 생성 제안 관리

    /// 방에 에이전트 생성 제안 추가
    func addAgentSuggestion(_ suggestion: RoomAgentSuggestion, to roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        rooms[idx].pendingAgentSuggestions.append(suggestion)

        let msg = ChatMessage(
            role: .system,
            content: "\(suggestion.suggestedBy)이(가) '\(suggestion.name)' 에이전트 생성을 제안했습니다.\(suggestion.reason.isEmpty ? "" : " 사유: \(suggestion.reason)")",
            messageType: .suggestion
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
    }

    /// 에이전트 생성 제안 승인 → 에이전트 생성 + 방에 초대
    func approveAgentSuggestion(suggestionID: UUID, in roomID: UUID) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
              let sugIdx = rooms[roomIdx].pendingAgentSuggestions.firstIndex(where: { $0.id == suggestionID }) else { return }

        var suggestion = rooms[roomIdx].pendingAgentSuggestions[sugIdx]
        suggestion.status = .approved
        rooms[roomIdx].pendingAgentSuggestions[sugIdx] = suggestion

        // 에이전트 생성
        let providerName = suggestion.recommendedProvider ?? "Anthropic"
        let modelName = suggestion.recommendedModel ?? "claude-sonnet-4-20250514"

        let newAgent = Agent(
            name: suggestion.name,
            persona: suggestion.persona,
            providerName: providerName,
            modelName: modelName
        )
        agentStore?.addAgent(newAgent)
        addAgent(newAgent.id, to: roomID)

        let msg = ChatMessage(
            role: .system,
            content: "'\(suggestion.name)' 에이전트가 생성되어 방에 참여했습니다."
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
        resumeSuggestionContinuationIfResolved(roomID: roomID)
    }

    /// 에이전트 생성 제안 거부
    func rejectAgentSuggestion(suggestionID: UUID, in roomID: UUID) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
              let sugIdx = rooms[roomIdx].pendingAgentSuggestions.firstIndex(where: { $0.id == suggestionID }) else { return }

        rooms[roomIdx].pendingAgentSuggestions[sugIdx].status = .rejected

        let name = rooms[roomIdx].pendingAgentSuggestions[sugIdx].name
        let msg = ChatMessage(
            role: .system,
            content: "'\(name)' 에이전트 생성 제안이 건너뛰어졌습니다."
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
        resumeSuggestionContinuationIfResolved(roomID: roomID)
    }

    /// 모든 제안이 해결되면 대기 중인 continuation 재개
    func resumeSuggestionContinuationIfResolved(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let hasPending = room.pendingAgentSuggestions.contains { $0.status == .pending }
        if !hasPending, let cont = suggestionContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: true)
        }
    }

    /// 제안 응답 대기 — 사용자가 추가/건너뛰기를 누를 때까지 무한 대기
    private func waitForSuggestionResponse(roomID: UUID) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              room.pendingAgentSuggestions.contains(where: { $0.status == .pending }) else {
            return
        }

        let _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.suggestionContinuations[roomID] = cont
        }
    }

    // MARK: - 방에 에이전트 추가

    func addAgent(_ agentID: UUID, to roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        guard !rooms[idx].assignedAgentIDs.contains(agentID) else { return }
        rooms[idx].assignedAgentIDs.append(agentID)

        // 에이전트의 참조 프로젝트를 방에 병합
        if let agent = agentStore?.agents.first(where: { $0.id == agentID }) {
            for path in agent.referenceProjectPaths {
                if !rooms[idx].projectPaths.contains(path) {
                    rooms[idx].projectPaths.append(path)
                }
            }
        }

        syncAgentStatuses()
        scheduleSave()

        if let agentName = agentStore?.agents.first(where: { $0.id == agentID })?.name {
            let systemMsg = ChatMessage(role: .system, content: "\(agentName)이(가) 방에 참여했습니다.")
            appendMessage(systemMsg, to: roomID)
        }
    }

    // MARK: - 방 워크플로우 (계획 → 실행)

    /// 방의 첫 번째 에이전트가 마스터인지 확인 (마스터 주도 트리아지)
    private func isMasterLed(roomID: UUID) -> Bool {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }) else { return false }
        return agent.isMaster
    }

    /// Triage 단계: 분석 → 전문가 초대
    private func executeTriagePhase(roomID: UUID, task: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let masterID = room.assignedAgentIDs.first,
              let masterAgent = agentStore?.agents.first(where: { $0.id == masterID }),
              let provider = providerManager?.provider(named: masterAgent.providerName) else { return }

        // ── Step 1: 분석 + 요약 (도구 없이, 이미지 포함) ──
        let analyzeMsg = ChatMessage(
            role: .system,
            content: "요청을 분석하는 중..."
        )
        appendMessage(analyzeMsg, to: roomID)

        let analyzePrompt = """
        당신은 요청 분류기입니다. 작업을 수행하는 것이 아니라 분류만 합니다.

        아래 항목을 출력하세요. 다른 내용은 절대 출력하지 마세요:
        - 요청: (1문장 요약)
        - 전문가: (필요한 역할명)
        - 범위: (작업량)
        - 대상: (파일 경로, URL 등 작업 대상. 요청에 명시되어 있을 때만 출력. 없으면 이 줄 생략)

        [절대 금지] 번역, 코딩, 문서 작성, 요약, 설명 등 실제 작업 수행
        [절대 금지] 질문, 확인 요청, 추가 설명
        """

        let history = buildRoomHistory(roomID: roomID)

        var analysisText = ""
        do {
            // sendMessageWithTools(tools: []) → 이미지 전달 O, 도구 사용 X
            let analysisResponse = try await provider.sendMessageWithTools(
                model: masterAgent.modelName,
                systemPrompt: analyzePrompt,
                messages: history,
                tools: []
            )

            switch analysisResponse {
            case .text(let t): analysisText = t
            case .toolCalls: analysisText = "분석 완료"
            case .mixed(let t, _): analysisText = t
            }

            let analysisReply = ChatMessage(role: .assistant, content: analysisText, agentName: masterAgent.name)
            appendMessage(analysisReply, to: roomID)
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "분석 오류: \(error.localizedDescription)",
                agentName: masterAgent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.failed)
                rooms[i].completedAt = Date()
            }
            syncAgentStatuses()
            scheduleSave()
            return
        }

        // ── Step 1.5: 작업 대상 누락 시 사용자에게 질문 ──
        // 정보 조회성 요청은 파일/경로가 필요 없으므로 스킵
        let isInfoRequest = Self.isInfoRequest(task)
            || analysisText.contains("정보 조회") || analysisText.contains("조사") || analysisText.contains("정리")

        let codingKeywords = ["코딩", "수정", "버그", "구현", "리팩토", "배포", "빌드", "테스트", "코드"]
        let needsTarget = !isInfoRequest && codingKeywords.contains(where: { analysisText.contains($0) })
        let hasTarget = analysisText.contains("- 대상:")
        let taskHasPath = task.contains("/") || task.contains("\\") || task.contains(".swift") || task.contains(".ts") || task.contains(".js") || task.contains(".py")

        if needsTarget && !hasTarget && !taskHasPath {
            // 코딩 관련 작업인데 대상 파일/경로가 없음 → 사용자에게 질문
            let askTargetMsg = ChatMessage(
                role: .system,
                content: "작업 대상 파일이나 경로를 알려주세요.",
                messageType: .userQuestion
            )
            appendMessage(askTargetMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.awaitingUserInput)
            }
            scheduleSave()

            let targetAnswer = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                userInputContinuations[roomID] = continuation
            }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }

            // 사용자 답변을 분석 결과에 추가
            analysisText += "\n- 대상: \(targetAnswer)"
            let updatedAnalysis = ChatMessage(role: .system, content: "대상 정보가 추가되었습니다: \(targetAnswer)")
            appendMessage(updatedAnalysis, to: roomID)
        }

        // ── Step 1.6: 마스터 주도 → 사용자 컨펌 (거부 시 재분석 루프) ──
        if masterAgent.isMaster {
            var currentAnalysis = analysisText
            let maxRetries = 3

            for attempt in 0..<maxRetries {
                // 분석 결과 확인 요청
                let confirmMsg = ChatMessage(
                    role: .system,
                    content: "분석 결과를 확인해주세요. 맞으면 승인, 수정이 필요하면 거부해주세요.",
                    messageType: .approvalRequest
                )
                appendMessage(confirmMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.awaitingApproval)
                }
                scheduleSave()

                let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = continuation
                }
                approvalContinuations.removeValue(forKey: roomID)
                guard !Task.isCancelled else { return }

                if approved {
                    // 승인됨 → planning 복귀, 루프 탈출
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.planning)
                    }
                    analysisText = currentAnalysis
                    break
                }

                // 거부됨 → 사용자에게 구체적으로 질문
                if attempt < maxRetries - 1 {
                    let askMsg = ChatMessage(
                        role: .system,
                        content: "어떤 부분이 다른가요? 수정할 내용을 알려주세요.",
                        messageType: .userQuestion
                    )
                    appendMessage(askMsg, to: roomID)

                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.awaitingUserInput)
                    }
                    scheduleSave()

                    let userFeedback = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                        userInputContinuations[roomID] = continuation
                    }

                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.planning)
                    }

                    // 사용자 피드백으로 재분석 (이미지 없이 텍스트만)
                    let retryPrompt = """
                    당신은 요청 분류기입니다. 이전 분석이 거부되었습니다.

                    [이전 분석]
                    \(currentAnalysis)

                    [사용자 피드백]
                    \(userFeedback)

                    피드백을 반영하여 다시 3줄만 출력하세요:
                    - 요청: (1문장 요약)
                    - 전문가: (필요한 역할명)
                    - 범위: (작업량)

                    [절대 금지] 번역, 코딩, 문서 작성, 요약 등 실제 작업 수행
                    [절대 금지] 이미지 내용을 직접 번역하거나 분석 결과를 작성
                    3줄 외 다른 출력 금지.
                    """

                    let retryMsg = ChatMessage(role: .system, content: "피드백을 반영하여 재분석하는 중...")
                    appendMessage(retryMsg, to: roomID)

                    do {
                        // 이미지 없이 텍스트만 전달 (마스터가 작업 수행 방지)
                        let retryMessages = [
                            ConversationMessage.user("이전 분석:\n\(currentAnalysis)\n\n사용자 피드백:\n\(userFeedback)")
                        ]
                        let retryResponse = try await provider.sendMessageWithTools(
                            model: masterAgent.modelName,
                            systemPrompt: retryPrompt,
                            messages: retryMessages,
                            tools: []
                        )
                        switch retryResponse {
                        case .text(let t): currentAnalysis = t
                        case .toolCalls: currentAnalysis = "분석 완료"
                        case .mixed(let t, _): currentAnalysis = t
                        }
                        let retryReply = ChatMessage(role: .assistant, content: currentAnalysis, agentName: masterAgent.name)
                        appendMessage(retryReply, to: roomID)
                    } catch {
                        // 재분석 실패 → 이전 분석 유지
                    }
                } else {
                    // 최대 재시도 초과 → 워크플로우 종료
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.failed)
                        rooms[i].completedAt = Date()
                    }
                    let failMsg = ChatMessage(
                        role: .system,
                        content: "분석이 승인되지 않아 작업을 종료합니다.",
                        messageType: .error
                    )
                    appendMessage(failMsg, to: roomID)
                    syncAgentStatuses()
                    scheduleSave()
                    return
                }
            }
        }

        // ── Step 2: 전문가 초대 (프로그래밍적 — LLM 의존 없음, 복수 역할 지원) ──
        let availableAgents = agentStore?.subAgents.filter { !$0.isMaster } ?? []

        // 승인 전 사용자가 보낸 힌트 메시지 반영 (예: "백엔드, 프론트엔드 각각의 얘기를 듣고싶어")
        let userHints = rooms.first(where: { $0.id == roomID })?.messages
            .filter { $0.role == .user && $0.content != "승인" }
            .map(\.content)
            .joined(separator: " ") ?? ""

        // 역할 추출: 사용자 힌트에서 여러 역할 추출 → 분석 텍스트 → task 순 폴백
        var roleNames: [String] = []
        if !userHints.isEmpty {
            roleNames = Self.extractRolesFromTask(userHints)
        }
        if roleNames.isEmpty {
            if let analysisRole = Self.extractRoleName(from: analysisText) {
                roleNames = [analysisRole]
            } else {
                roleNames = Self.extractRolesFromTask(task)
            }
        }
        if roleNames.isEmpty {
            roleNames = ["전문가"]
        }

        // 각 역할에 대해 매칭 + 초대/제안
        var usedAgentIDs: Set<UUID> = []
        var hasSuggestion = false
        for roleName in roleNames {
            let available = availableAgents.filter { !usedAgentIDs.contains($0.id) }
            if let matched = Self.findMatchingAgent(roleName: roleName, among: available) {
                addAgent(matched.id, to: roomID)
                usedAgentIDs.insert(matched.id)
            } else {
                let suggestion = RoomAgentSuggestion(
                    name: roleName,
                    persona: "당신은 \(roleName)입니다. 사용자의 요청을 전문적으로 수행하세요.",
                    recommendedProvider: masterAgent.providerName,
                    recommendedModel: masterAgent.modelName,
                    reason: "작업에 필요한 '\(roleName)' 역할의 에이전트가 없습니다. 작업 규칙을 설정하여 추가해주세요.",
                    suggestedBy: masterAgent.name
                )
                addAgentSuggestion(suggestion, to: roomID)
                hasSuggestion = true
            }
        }

        // 제안이 있으면 사용자가 추가/건너뛰기를 누를 때까지 대기
        if hasSuggestion {
            await waitForSuggestionResponse(roomID: roomID)
        }

        // 전문가 미초대 시 워크플로우 종료
        if let currentRoom = rooms.first(where: { $0.id == roomID }),
           currentRoom.assignedAgentIDs.count <= 1,
           currentRoom.status == .planning {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.failed)
                rooms[i].completedAt = Date()
            }
            let failMsg = ChatMessage(
                role: .system,
                content: "전문가가 초대되지 않아 작업을 종료합니다.",
                messageType: .error
            )
            appendMessage(failMsg, to: roomID)
            syncAgentStatuses()
            scheduleSave()
        }
    }

    /// 워크플로우 진입점: intent 유무에 따라 새/레거시 분기
    func startRoomWorkflow(roomID: UUID, task: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        guard room.intent != nil else {
            await legacyStartRoomWorkflow(roomID: roomID, task: task)
            return
        }
        await executePhaseWorkflow(roomID: roomID, task: task)
    }

    /// 레거시 워크플로우: Triage → 토론 → 승인 → 계획 → 실행
    private func legacyStartRoomWorkflow(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        rooms[idx].status = .planning
        syncAgentStatuses()

        // ── Phase 0: Triage (마스터 주도 방이면 분석 + 팀 구성) ──
        if isMasterLed(roomID: roomID) {
            await executeTriagePhase(roomID: roomID, task: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.status == .planning else { return }
        }

        // Triage 후 에이전트 수 재확인
        guard let currentRoom = rooms.first(where: { $0.id == roomID }) else { return }
        let agentCount = currentRoom.assignedAgentIDs.count

        // ── Phase 1: 토론 (전문가 2명 이상일 때만) ──
        let specialistCount = executingAgentIDs(in: roomID).count
        if specialistCount >= 2 {
            let startMsg = ChatMessage(
                role: .system,
                content: "토론을 시작합니다. 참여자: \(agentCount)명 | 합의 시 자동 종료"
            )
            appendMessage(startMsg, to: roomID)

            await executeDiscussion(roomID: roomID, topic: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.status == .planning else { return }

            // 토론 브리핑 생성 (컨텍스트 압축)
            await generateBriefing(roomID: roomID, topic: task)
            guard !Task.isCancelled else { return }
        } else if agentCount <= 1 {
            // 단일 에이전트 (Triage 없이 직접 지정된 경우): 기본 계획으로 직접 실행
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = RoomPlan(summary: task, estimatedSeconds: 300, steps: [RoomStep(text: task)])
                rooms[i].timerDurationSeconds = 300
                rooms[i].timerStartedAt = Date()
                rooms[i].transitionTo(.inProgress)
            }
            scheduleSave()
            await executeRoomWork(roomID: roomID, task: task)
            return
        }

        // ── Phase 2: 계획 수립 ──
        let hadDiscussion = specialistCount >= 2
        let planningMsg = ChatMessage(
            role: .system,
            content: hadDiscussion ? "토론 결과를 바탕으로 계획을 수립하는 중..." : "계획을 수립하는 중..."
        )
        appendMessage(planningMsg, to: roomID)

        let planResult = await requestPlan(roomID: roomID, task: task)
        guard !Task.isCancelled else { return }

        guard let plan = planResult else {
            // 계획 실패 → 직접 실행 (기본 5분)
            let fallbackMsg = ChatMessage(role: .system, content: "계획 수립을 건너뛰고 바로 실행합니다.")
            appendMessage(fallbackMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = RoomPlan(summary: task, estimatedSeconds: 300, steps: [RoomStep(text: task)])
                rooms[i].timerDurationSeconds = 300
                rooms[i].timerStartedAt = Date()
                rooms[i].transitionTo(.inProgress)
            }
            await executeRoomWork(roomID: roomID, task: task)
            return
        }

        // ── Phase 2.5: 전문가 2명+ 시 계획 승인 (리서치 요청은 스킵) ──
        let specialistIDs = executingAgentIDs(in: roomID)
        if specialistIDs.count >= 2 && !Self.isInfoRequest(task) {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = plan
                rooms[i].transitionTo(.awaitingApproval)
            }

            let stepsDesc = plan.steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
            let planApprovalMsg = ChatMessage(
                role: .system,
                content: "실행 계획:\n\n\(stepsDesc)\n\n이 순서대로 진행하시겠습니까?",
                messageType: .approvalRequest
            )
            appendMessage(planApprovalMsg, to: roomID)
            scheduleSave()

            let planApproved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                approvalContinuations[roomID] = continuation
            }
            approvalContinuations.removeValue(forKey: roomID)

            guard !Task.isCancelled else { return }

            if !planApproved {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                let rejectMsg = ChatMessage(role: .system, content: "사용자가 실행 계획을 거부했습니다.")
                appendMessage(rejectMsg, to: roomID)
                syncAgentStatuses()
                scheduleSave()
                return
            }
        }

        // 계획 확정 → 타이머 시작
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].plan = plan
            rooms[i].timerDurationSeconds = plan.estimatedSeconds
            rooms[i].timerStartedAt = Date()
            rooms[i].transitionTo(.inProgress)
        }
        scheduleSave()

        // ── Phase 3: 단계별 실행 ──
        await executeRoomWork(roomID: roomID, task: task)
    }

    /// 실행 대상 에이전트 (마스터 제외)
    private func executingAgentIDs(in roomID: UUID) -> [UUID] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.assignedAgentIDs.filter { id in
            let agent = agentStore?.agents.first(where: { $0.id == id })
            return !(agent?.isMaster ?? false)
        }
    }

    // MARK: - Phase 워크플로우 (새 7단계)

    /// 새 워크플로우: intent.requiredPhases 순회 디스패치
    private func executePhaseWorkflow(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let intent = rooms[idx].intent else { return }

        rooms[idx].status = .planning
        syncAgentStatuses()

        let phases = intent.requiredPhases

        let phaseStartMsg = ChatMessage(
            role: .system,
            content: "[\(intent.displayName)] 워크플로우를 시작합니다. 단계: \(phases.map { $0.displayName }.joined(separator: " → "))",
            messageType: .phaseTransition
        )
        appendMessage(phaseStartMsg, to: roomID)

        for phase in phases {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive else { break }

            // 현재 단계 기록
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].currentPhase = phase
            }
            scheduleSave()

            let transitionMsg = ChatMessage(
                role: .system,
                content: "── \(phase.displayName) 단계 ──",
                messageType: .phaseTransition
            )
            appendMessage(transitionMsg, to: roomID)

            switch phase {
            case .intake:
                await executeIntakePhase(roomID: roomID, task: task)
            case .intent:
                // Intent는 이미 결정됨 (방 생성 시 설정)
                break
            case .clarify:
                await executeClarifyPhase(roomID: roomID, task: task)
            case .assemble:
                await executeAssemblePhase(roomID: roomID, task: task)
            case .plan:
                await executeLegacyPlanPhase(roomID: roomID, task: task)
            case .execute:
                await executeLegacyExecutePhase(roomID: roomID, task: task)
            case .review:
                await executeReviewPhase(roomID: roomID, task: task)
            }
        }

        // 워크플로우 완료
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed {
            rooms[i].currentPhase = nil
            rooms[i].status = .completed
            rooms[i].completedAt = Date()
        }
        syncAgentStatuses()
        scheduleSave()
    }

    /// Intake 단계: 입력 파싱, Jira fetch, IntakeData 저장, 플레이북 로드
    private func executeIntakePhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // 1) URL 감지
        let urls = extractURLs(from: task)

        // 2) Jira URL 감지 + fetch
        let jiraConfig = JiraConfig.shared
        var sourceType: InputSourceType = .text
        var jiraKey: String?
        var jiraData: JiraTicketSummary?

        if jiraConfig.isConfigured, jiraConfig.isJiraURL(task) {
            sourceType = .jira
            // Jira 키 추출 (PROJ-123 패턴)
            if let keyRange = task.range(of: "[A-Z][A-Z0-9]+-\\d+", options: .regularExpression) {
                jiraKey = String(task[keyRange])
            }
            // Jira API fetch
            jiraData = await fetchJiraTicketSummary(from: task)
        } else if !urls.isEmpty {
            sourceType = .url
        }

        // 3) IntakeData 저장
        let intakeData = IntakeData(
            sourceType: sourceType,
            rawInput: task,
            jiraKey: jiraKey,
            jiraData: jiraData,
            urls: urls
        )
        rooms[idx].intakeData = intakeData

        // 4) 플레이북 로드
        if let projectPath = rooms[idx].primaryProjectPath {
            if let playbook = PlaybookManager.load(from: projectPath) {
                rooms[idx].playbook = playbook
                let playbookMsg = ChatMessage(
                    role: .system,
                    content: "프로젝트 플레이북을 로드했습니다: \(playbook.userRole?.displayName ?? "역할 미설정")"
                )
                appendMessage(playbookMsg, to: roomID)
            }
        }

        // 5) 요약 메시지
        let summaryMsg = ChatMessage(
            role: .system,
            content: intakeData.asContextString()
        )
        appendMessage(summaryMsg, to: roomID)
        scheduleSave()
    }

    /// Clarify 단계: 마스터가 ask_user로 결측치 질문 (최대 5회) → 미답 시 가정 선언
    private func executeClarifyPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        // clarifyQuestionCount 초기화
        rooms[idx].clarifyQuestionCount = 0

        // 컨텍스트 구성: IntakeData + 플레이북
        var contextParts: [String] = []
        if let intakeData = rooms[idx].intakeData {
            contextParts.append(intakeData.asContextString())
        }
        if let playbook = rooms[idx].playbook {
            contextParts.append(playbook.asContextString())
        }
        let contextString = contextParts.joined(separator: "\n\n")

        let clarifySystemPrompt = """
        \(agent.resolvedSystemPrompt)

        당신은 Clarify(요건 확인) 단계를 수행하고 있습니다.
        주어진 입력 데이터를 분석하고, 작업 수행에 필요하지만 누락된 핵심 정보를 파악하세요.

        규칙:
        1. ask_user 도구로 사용자에게 핵심 질문을 하세요 (최대 5개)
        2. 한 번에 하나의 질문만 하세요
        3. 질문에 options(선택지)를 제공하면 사용자가 더 쉽게 답변할 수 있습니다
        4. 사용자가 응답하지 않거나 모호하게 답하면, 합리적인 가정을 선언하세요
        5. 모든 질문이 끝나면, 가정을 포함하여 다음 형식의 산출물을 생성하세요:

        ```artifact:assumptions title="작업 가정 선언"
        - [위험:낮음] 가정 내용 1
        - [위험:중간] 가정 내용 2
        - [위험:높음] 가정 내용 3
        ```

        질문 예시:
        - 브랜치 전략은 어떻게 되나요? (options: ["feature 브랜치", "trunk-based", "git-flow"])
        - 테스트 작성이 필요한가요?
        - 특정 코딩 컨벤션이 있나요?
        """

        let messages: [(role: String, content: String)] = [
            ("user", "\(contextString)\n\n위 입력을 분석하고, 작업 수행 전 확인이 필요한 사항을 ask_user 도구로 질문하세요. 작업: \(task)")
        ]

        let context = makeToolContext(roomID: roomID, currentAgentID: firstAgentID)

        // 계획 수립 진행 버블 추가
        let progressMsg = ChatMessage(
            role: .system,
            content: "\(agent.name) 요건 분석 중...",
            messageType: .progress
        )
        appendMessage(progressMsg, to: roomID)

        do {
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: clarifySystemPrompt,
                messages: messages,
                context: context,
                onToolActivity: { [weak self] activity in
                    Task { @MainActor in
                        let toolMsg = ChatMessage(
                            role: .assistant,
                            content: activity,
                            agentName: agent.name,
                            messageType: .toolActivity,
                            activityGroupID: progressMsg.id
                        )
                        self?.appendMessage(toolMsg, to: roomID)
                    }
                }
            )

            // 응답에서 산출물 추출
            let artifacts = ArtifactParser.extractArtifacts(from: response, producedBy: agent.name)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].artifacts.append(contentsOf: artifacts)

                // assumptions 산출물에서 가정 파싱
                for artifact in artifacts where artifact.type == .assumptions {
                    let parsedAssumptions = parseAssumptions(from: artifact.content)
                    if rooms[i].assumptions == nil { rooms[i].assumptions = [] }
                    rooms[i].assumptions?.append(contentsOf: parsedAssumptions)
                }
            }

            // 마스터 응답을 방에 추가
            let strippedResponse = ArtifactParser.stripArtifactBlocks(from: response)
            if !strippedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let responseMsg = ChatMessage(role: .assistant, content: strippedResponse, agentName: agent.name)
                appendMessage(responseMsg, to: roomID)
            }

            // 가정 요약 메시지
            if let assumptions = rooms.first(where: { $0.id == roomID })?.assumptions, !assumptions.isEmpty {
                let assumptionSummary = assumptions.map { "- [\($0.riskLevel.rawValue)] \($0.text)" }.joined(separator: "\n")
                let assumptionMsg = ChatMessage(
                    role: .system,
                    content: "가정 선언 (\(assumptions.count)건):\n\(assumptionSummary)",
                    messageType: .assumption
                )
                appendMessage(assumptionMsg, to: roomID)
            }
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "Clarify 단계 오류: \(error.localizedDescription)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }
        scheduleSave()
    }

    /// 가정 산출물 텍스트에서 WorkflowAssumption 파싱
    private func parseAssumptions(from content: String) -> [WorkflowAssumption] {
        // 형식: "- [위험:낮음] 가정 내용" 또는 "- [위험:중간] 가정 내용" 등
        let lines = content.components(separatedBy: "\n")
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [위험:") else { return nil }

            var riskLevel: WorkflowAssumption.RiskLevel = .low
            if trimmed.contains("[위험:높음]") {
                riskLevel = .high
            } else if trimmed.contains("[위험:중간]") {
                riskLevel = .medium
            }

            // 텍스트 추출: "] " 이후
            guard let bracketEnd = trimmed.range(of: "] ") else { return nil }
            let text = String(trimmed[bracketEnd.upperBound...])
            guard !text.isEmpty else { return nil }

            return WorkflowAssumption(text: text, riskLevel: riskLevel)
        }
    }

    /// Assemble 단계: 마스터 역할 산출 → 시스템 매칭/초대 → 커버리지 게이트
    private func executeAssemblePhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        // 1) 마스터에게 역할 요구사항 산출 요청
        var contextParts: [String] = []
        if let intakeData = rooms[idx].intakeData {
            contextParts.append(intakeData.asContextString())
        }
        if let assumptions = rooms[idx].assumptions, !assumptions.isEmpty {
            contextParts.append("[가정]\n" + assumptions.map { "- \($0.text)" }.joined(separator: "\n"))
        }

        let assembleSystemPrompt = """
        \(agent.resolvedSystemPrompt)

        당신은 Assemble(팀 구성) 단계를 수행하고 있습니다.
        작업 수행에 필요한 역할을 분석하고 산출물로 제출하세요.

        반드시 아래 형식으로 산출물을 생성하세요:

        ```artifact:role_requirements title="역할 요구사항"
        - [필수] 역할이름: 이 역할이 필요한 이유
        - [선택] 역할이름: 이 역할이 필요한 이유
        ```

        역할 이름 예시: 백엔드 개발자, 프론트엔드 개발자, QA 테스트 자동화, DevOps 엔지니어, 기술 문서 작성자
        """

        let messages: [(role: String, content: String)] = [
            ("user", "\(contextParts.joined(separator: "\n\n"))\n\n위 작업에 필요한 역할을 분석하세요. 작업: \(task)")
        ]

        do {
            let response = try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: assembleSystemPrompt,
                messages: messages
            )

            // 산출물 추출
            let artifacts = ArtifactParser.extractArtifacts(from: response, producedBy: agent.name)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].artifacts.append(contentsOf: artifacts)
            }

            // role_requirements 산출물에서 역할 파싱
            var requirements: [RoleRequirement] = []
            for artifact in artifacts where artifact.type == .roleRequirements {
                requirements.append(contentsOf: AgentMatcher.parseRoleRequirements(from: artifact.content))
            }

            guard !requirements.isEmpty else {
                let noReqMsg = ChatMessage(role: .system, content: "역할 요구사항이 감지되지 않았습니다. 기존 에이전트로 진행합니다.")
                appendMessage(noReqMsg, to: roomID)
                return
            }

            // 2) 시스템 매칭
            let subAgents = agentStore?.subAgents ?? []
            let matched = AgentMatcher.matchRoles(requirements: requirements, agents: subAgents)

            // 3) 매칭된 에이전트 자동 초대
            var invitedNames: [String] = []
            for req in matched where req.status == .matched {
                if let agentID = req.matchedAgentID,
                   let room = rooms.first(where: { $0.id == roomID }),
                   !room.assignedAgentIDs.contains(agentID) {
                    addAgent(agentID, to: roomID)
                    if let name = agentStore?.agents.first(where: { $0.id == agentID })?.name {
                        invitedNames.append("\(name) ← \(req.roleName)")
                    }
                }
            }

            // 4) 매칭 안 된 역할은 에이전트 생성 제안
            for req in matched where req.status == .unmatched {
                let suggestion = RoomAgentSuggestion(
                    name: req.roleName,
                    persona: "이 에이전트는 '\(req.roleName)' 역할을 수행합니다. \(req.reason)",
                    reason: req.reason,
                    suggestedBy: agent.name
                )
                addAgentSuggestion(suggestion, to: roomID)
            }

            // 4.5) 미매칭 제안이 있으면 사용자가 추가/건너뛰기할 때까지 대기
            if matched.contains(where: { $0.status == .unmatched }) {
                await waitForSuggestionResponse(roomID: roomID)
            }

            // 5) 매칭 결과 메시지
            let matchedCount = matched.filter { $0.status == .matched }.count
            let unmatchedCount = matched.filter { $0.status == .unmatched }.count
            let coverage = AgentMatcher.coverageRatio(matched)

            var resultParts: [String] = ["팀 구성 결과:"]
            resultParts.append("- 매칭: \(matchedCount)명, 미매칭: \(unmatchedCount)명")
            resultParts.append("- 커버리지: \(Int(coverage * 100))%")
            if !invitedNames.isEmpty {
                resultParts.append("- 초대됨: \(invitedNames.joined(separator: ", "))")
            }

            let resultMsg = ChatMessage(role: .system, content: resultParts.joined(separator: "\n"))
            appendMessage(resultMsg, to: roomID)

            // 6) 커버리지 게이트
            if !AgentMatcher.checkMinimumCoverage(matched) {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.awaitingUserInput)
                }
                let gateMsg = ChatMessage(
                    role: .system,
                    content: "필수 역할 커버리지가 50% 미만입니다. 에이전트 생성 제안을 검토하거나, 현재 구성으로 계속하시겠습니까?",
                    messageType: .userQuestion
                )
                appendMessage(gateMsg, to: roomID)
                scheduleSave()

                // 사용자 답변 대기
                let _ = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                    userInputContinuations[roomID] = continuation
                }
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                }
            }

        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "Assemble 단계 오류: \(error.localizedDescription)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }
        scheduleSave()
    }

    /// 레거시 Plan 단계 재사용 (토론 + 브리핑 + 승인 + 계획)
    private func executeLegacyPlanPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // 마스터 주도 방이면 Triage 단계 실행
        if isMasterLed(roomID: roomID) {
            await executeTriagePhase(roomID: roomID, task: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.status == .planning else { return }
        }

        let agentCount = rooms[idx].assignedAgentIDs.count

        // 토론 (2명 이상)
        if agentCount > 1 {
            await executeDiscussion(roomID: roomID, topic: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.status == .planning else { return }

            await generateBriefing(roomID: roomID, topic: task)
            guard !Task.isCancelled else { return }

            // 토론 후 사용자 승인
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.awaitingApproval)
            }
            let briefingSummary = rooms.first(where: { $0.id == roomID })?.briefing?.summary ?? "토론 결과"
            let approvalMsg = ChatMessage(
                role: .system,
                content: "토론이 완료되었습니다.\n\n\(briefingSummary)\n\n이대로 진행하시겠습니까?",
                messageType: .approvalRequest
            )
            appendMessage(approvalMsg, to: roomID)
            scheduleSave()

            let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                approvalContinuations[roomID] = continuation
            }
            approvalContinuations.removeValue(forKey: roomID)
            guard !Task.isCancelled else { return }

            if !approved {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                let rejectMsg = ChatMessage(role: .system, content: "사용자가 실행을 거부했습니다.")
                appendMessage(rejectMsg, to: roomID)
                syncAgentStatuses()
                scheduleSave()
                return
            }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
        }

        // 계획 수립
        let planResult = await requestPlan(roomID: roomID, task: task)
        guard !Task.isCancelled else { return }

        if let plan = planResult {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = plan
            }
        }
        scheduleSave()
    }

    /// 레거시 Execute 단계 재사용
    private func executeLegacyExecutePhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // 계획이 없으면 기본 계획 생성
        if rooms[idx].plan == nil {
            rooms[idx].plan = RoomPlan(summary: task, estimatedSeconds: 300, steps: [RoomStep(text: task)])
        }

        rooms[idx].timerDurationSeconds = rooms[idx].plan?.estimatedSeconds ?? 300
        rooms[idx].timerStartedAt = Date()
        rooms[idx].transitionTo(.inProgress)
        scheduleSave()

        await executeRoomWork(roomID: roomID, task: task)
    }

    /// Review 단계: 작업일지 + 플레이북 override 감지
    private func executeReviewPhase(roomID: UUID, task: String) async {
        // 작업일지 생성 (기존 로직 재활용)
        await generateWorkLog(roomID: roomID, task: task)

        // 플레이북 override 감지: 실제 작업에서 플레이북 설정과 다르게 진행된 부분 탐지
        guard let room = rooms.first(where: { $0.id == roomID }),
              let playbook = room.playbook,
              room.primaryProjectPath != nil else { return }

        // 산출물에서 실제 사용된 패턴 분석
        let workSummary = room.workLog?.outcome ?? ""
        var overrides: [String] = []

        // 브랜치 전략 override 감지
        if let branchPattern = playbook.branchPattern, !branchPattern.isEmpty,
           (workSummary.contains("branch") || workSummary.contains("브랜치")) {
            overrides.append("브랜치 패턴 변경 감지 (설정: \(branchPattern))")
        }

        // override가 있으면 플레이북 업데이트 제안
        if !overrides.isEmpty {
            let overrideMsg = ChatMessage(
                role: .system,
                content: "플레이북과 다른 패턴이 감지되었습니다:\n" + overrides.map { "- \($0)" }.joined(separator: "\n") + "\n\n플레이북을 업데이트하시겠습니까?"
            )
            appendMessage(overrideMsg, to: roomID)
        }

        // 리뷰 완료 메시지
        let reviewMsg = ChatMessage(
            role: .system,
            content: "검토가 완료되었습니다.",
            messageType: .phaseTransition
        )
        appendMessage(reviewMsg, to: roomID)
        scheduleSave()
    }

    // MARK: - Intake 헬퍼

    /// 텍스트에서 URL 추출
    private func extractURLs(from text: String) -> [String] {
        let pattern = "https?://[^\\s]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    /// Jira API에서 티켓 요약 fetch
    private func fetchJiraTicketSummary(from task: String) async -> JiraTicketSummary? {
        let jiraConfig = JiraConfig.shared

        guard let urlRange = task.range(of: "https://[^\\s]+", options: .regularExpression),
              let url = URL(string: String(task[urlRange])) else { return nil }

        let apiURLString = jiraConfig.apiURL(from: url.absoluteString)
        guard let apiURL = URL(string: apiURLString),
              let auth = jiraConfig.authHeader() else { return nil }

        var request = URLRequest(url: apiURL)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let fields = json["fields"] as? [String: Any] ?? [:]
            let key = json["key"] as? String ?? ""
            let summary = fields["summary"] as? String ?? ""
            let issueType = (fields["issuetype"] as? [String: Any])?["name"] as? String ?? ""
            let statusName = (fields["status"] as? [String: Any])?["name"] as? String ?? ""
            let description = extractDescription(from: fields["description"])

            return JiraTicketSummary(
                key: key,
                summary: summary,
                issueType: issueType,
                status: statusName,
                description: description
            )
        } catch {
            return nil
        }
    }

    /// Jira ADF(Atlassian Document Format) 또는 일반 텍스트에서 설명 추출
    private func extractDescription(from value: Any?) -> String {
        if let text = value as? String { return text }
        guard let adf = value as? [String: Any],
              let content = adf["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { node -> String? in
            guard let innerContent = node["content"] as? [[String: Any]] else { return nil }
            return innerContent.compactMap { inner -> String? in
                inner["text"] as? String
            }.joined()
        }.joined(separator: "\n")
    }

    /// 에이전트에게 계획 수립 요청
    private func requestPlan(roomID: UUID, task: String) async -> RoomPlan? {
        guard let room = rooms.first(where: { $0.id == roomID }) else {
            return nil
        }
        // 전문가(마스터 제외)를 계획 생성자로 선택
        let specialistID = room.assignedAgentIDs.first { id in
            guard let a = agentStore?.agents.first(where: { $0.id == id }) else { return false }
            return !(a.isMaster)
        } ?? room.assignedAgentIDs.first
        guard let firstAgentID = specialistID,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            let errorMsg = ChatMessage(
                role: .system,
                content: "에이전트 또는 API 연결을 찾을 수 없습니다."
            )
            appendMessage(errorMsg, to: roomID)
            return nil
        }

        // 브리핑 + 산출물 기반 컨텍스트 구성 (압축)
        let briefingContext: String
        if let briefing = room.briefing {
            briefingContext = briefing.asContextString()
        } else {
            // 폴백: 기존 토론 히스토리에서 요약 생성
            let history = buildDiscussionHistory(roomID: roomID, currentAgentName: agent.name)
            briefingContext = history.map { "[\($0.role)] \($0.content)" }.suffix(10).joined(separator: "\n")
        }

        let artifactContext: String
        if !room.artifacts.isEmpty {
            artifactContext = "\n\n[참고 산출물]\n" + room.artifacts.map {
                "[\($0.type.displayName)] \($0.title) (v\($0.version)):\n\($0.content)"
            }.joined(separator: "\n---\n")
        } else {
            artifactContext = ""
        }

        // 플레이북 컨텍스트 주입
        let playbookContext: String
        if let playbook = room.playbook {
            playbookContext = "\n\n[프로젝트 플레이북]\n" + playbook.asContextString()
        } else {
            playbookContext = ""
        }

        // 방 내 전문가 목록 (마스터 제외)
        let specialistNames: String
        let specialists = room.assignedAgentIDs.compactMap { id -> String? in
            guard let agent = agentStore?.agents.first(where: { $0.id == id }) else { return nil }
            if agent.isMaster { return nil }
            return agent.name
        }
        specialistNames = specialists.isEmpty ? "(없음)" : specialists.joined(separator: ", ")

        let planSystemPrompt = """
        \(agent.resolvedSystemPrompt)

        현재 작업방에 배정되었습니다. 팀원들과의 토론이 완료되었습니다.
        토론 내용을 바탕으로 반드시 아래 형식의 JSON으로 실행 계획을 제출하세요:

        {"plan": {"summary": "전체 계획 요약", "estimated_minutes": 5, "steps": [{"text": "단계 설명", "agent": "담당 에이전트 이름"}, ...]}}

        방 내 전문가: \(specialistNames)

        규칙:
        - 단계를 최소화하세요. 한 번에 할 수 있는 작업은 한 단계로 묶으세요.
        - 번역, 요약, 분석 등 단일 작업은 반드시 1단계로 작성하세요.
        - 여러 단계로 쪼개야 하는 경우는 "서로 다른 전문가가 순서대로" 작업할 때뿐입니다.
        - estimated_minutes는 현실적으로 추정하세요 (1~30분)
        - 각 step에 "agent" 필드로 담당 전문가를 지정하세요 (위 목록에서 정확한 이름 사용)
        - 마스터(PM/오케스트레이터)는 실행 대상이 아닙니다. 마스터에게 step을 배정하지 마세요.
        - 배포, 데이터 삭제 등 위험한 단계는 "requires_approval": true 추가
        - 반드시 유효한 JSON으로만 응답하세요
        """

        // 이미지 첨부 정보 포함 (첨부된 내용을 "확인하라"는 불필요한 단계 방지)
        let attachmentContext: String
        let imageAttachments = room.messages
            .compactMap { $0.attachments }
            .flatMap { $0 }
        if !imageAttachments.isEmpty {
            attachmentContext = "\n\n[사용자 첨부 이미지 \(imageAttachments.count)장 — 이미 제공됨]\n" +
                "(이미지가 이미 제공되었으므로, 사용자에게 다시 요청하지 마세요. 바로 작업하세요. 계획의 step에 파일 경로를 포함하지 마세요.)"
        } else {
            attachmentContext = ""
        }

        let planMessages: [(role: String, content: String)] = [
            ("user", "브리핑:\n\(briefingContext)\(artifactContext)\(playbookContext)\(attachmentContext)\n\n실행 계획을 JSON으로 작성해주세요. 작업: \(task)")
        ]

        do {
            let response = try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: planSystemPrompt,
                messages: planMessages
            )

            // 계획 JSON은 내부 처리용 — 사용자에게 표시하지 않음

            // JSON 파싱
            return parsePlan(from: response)
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "계획 수립 실패: \(error.localizedDescription)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            return nil
        }
    }

    /// 계획 JSON 파싱
    private func parsePlan(from response: String) -> RoomPlan? {
        let jsonString = extractJSON(from: response)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let planDict = json["plan"] as? [String: Any],
              let summary = planDict["summary"] as? String,
              let estimatedMinutes = planDict["estimated_minutes"] as? Int,
              let rawSteps = planDict["steps"] as? [Any] else {
            return nil
        }

        // 에이전트 이름 → ID 매핑 (퍼지 매칭)
        let agentNameToID: [String: UUID] = {
            guard let agents = agentStore?.subAgents else { return [:] }
            var map: [String: UUID] = [:]
            for agent in agents {
                map[agent.name.lowercased()] = agent.id
            }
            return map
        }()

        func resolveAgentID(name: String?) -> UUID? {
            guard let name = name?.lowercased() else { return nil }
            if let id = agentNameToID[name] { return id }
            // 부분 매칭
            return agentNameToID.first(where: { $0.key.contains(name) || name.contains($0.key) })?.value
        }

        // steps: plain String과 {"text":"...", "agent":"...", "requires_approval": true} 혼합 지원
        var steps: [RoomStep] = []
        for raw in rawSteps {
            if let str = raw as? String {
                steps.append(RoomStep(text: str))
            } else if let dict = raw as? [String: Any], let text = dict["text"] as? String {
                let requiresApproval = dict["requires_approval"] as? Bool ?? false
                let agentName = dict["agent"] as? String
                let agentID = resolveAgentID(name: agentName)
                steps.append(RoomStep(text: text, requiresApproval: requiresApproval, assignedAgentID: agentID))
            }
        }
        guard !steps.isEmpty else { return nil }

        return RoomPlan(
            summary: summary,
            estimatedSeconds: estimatedMinutes * 60,
            steps: steps
        )
    }

    /// JSON 추출 (ChatViewModel.extractJSON과 동일 로직)
    private func extractJSON(from text: String) -> String {
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", range: startRange.upperBound..<text.endIndex) {
            return String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startRange = text.range(of: "```\n"),
           let endRange = text.range(of: "\n```", range: startRange.upperBound..<text.endIndex) {
            return String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    /// 방의 단계별 작업 실행
    private func executeRoomWork(roomID: UUID, task: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let plan = room.plan else { return }

        // 병렬 실행 시 파일 충돌 추적용
        let tracker = FileWriteTracker()
        // 이전 단계 응답 추적 (반복 감지용)
        var previousStepResponse: String?

        for (stepIndex, step) in plan.steps.enumerated() {
            // 취소 또는 방 삭제 감지
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { break }

            // 승인 게이트: requiresApproval인 단계에서 일시 정지
            if step.requiresApproval {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.awaitingApproval)
                    rooms[i].pendingApprovalStepIndex = stepIndex
                }
                let approvalMsg = ChatMessage(
                    role: .system,
                    content: "[\(stepIndex + 1)/\(plan.steps.count)] \"\(step.text)\" — 이 단계는 승인이 필요합니다.",
                    messageType: .approvalRequest
                )
                appendMessage(approvalMsg, to: roomID)
                scheduleSave()

                let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = continuation
                }

                approvalContinuations.removeValue(forKey: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].pendingApprovalStepIndex = nil
                }

                if !approved {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.failed)
                        rooms[i].completedAt = Date()
                    }
                    let rejectMsg = ChatMessage(
                        role: .system,
                        content: "단계 \(stepIndex + 1)이 거부되어 작업을 중단합니다.",
                        messageType: .error
                    )
                    appendMessage(rejectMsg, to: roomID)
                    syncAgentStatuses()
                    scheduleSave()
                    return
                }

                // 승인됨 → inProgress 복귀
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.inProgress)
                }
                let resumeMsg = ChatMessage(
                    role: .system,
                    content: "단계 \(stepIndex + 1) 승인됨. 실행을 계속합니다."
                )
                appendMessage(resumeMsg, to: roomID)
            }

            // 현재 단계 업데이트
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].setCurrentStep(stepIndex)
            }

            // 단계별 충돌 추적 초기화
            await tracker.reset()

            // 진행률 메시지: 짧은 "~하는 중" 스타일
            let shortLabel = Self.shortenStepLabel(step.text)
            let progressMsg = ChatMessage(
                role: .system,
                content: shortLabel,
                messageType: .progress
            )
            appendMessage(progressMsg, to: roomID)

            // 실행 대상: 마스터 제외, 전문가만
            let targetAgentIDs: [UUID]
            if let assignedID = step.assignedAgentID {
                targetAgentIDs = [assignedID]
            } else {
                let specialists = executingAgentIDs(in: roomID)
                targetAgentIDs = specialists.isEmpty ? room.assignedAgentIDs : specialists
            }

            // 에이전트 실행, 하나라도 실패하면 워크플로우 중단
            var stepFailed = false
            await withTaskGroup(of: Bool.self) { group in
                for agentID in targetAgentIDs {
                    group.addTask { [self] in
                        await self.executeStep(
                            step: step.text,
                            fullTask: task,
                            agentID: agentID,
                            roomID: roomID,
                            stepIndex: stepIndex,
                            totalSteps: plan.steps.count,
                            fileWriteTracker: tracker,
                            progressGroupID: progressMsg.id
                        )
                    }
                }
                for await success in group {
                    if !success { stepFailed = true }
                }
            }

            if stepFailed {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                let failMsg = ChatMessage(
                    role: .system,
                    content: "단계 \(stepIndex + 1) 실행 실패로 워크플로우를 중단합니다.",
                    messageType: .error
                )
                appendMessage(failMsg, to: roomID)
                syncAgentStatuses()
                scheduleSave()
                return
            }

            // 충돌 감지 경고
            let conflicts = await tracker.getConflicts()
            if !conflicts.isEmpty {
                let conflictPaths = conflicts.map { $0.path }.joined(separator: ", ")
                let warnMsg = ChatMessage(
                    role: .system,
                    content: "⚠️ 파일 충돌 감지: \(conflictPaths). 에이전트 간 동일 파일 수정 발생.",
                    messageType: .error
                )
                appendMessage(warnMsg, to: roomID)
            }

            // 연속 응답 유사도 감지: 에이전트가 같은 응답을 반복하면 중단
            if let currentRoom = rooms.first(where: { $0.id == roomID }) {
                let latestResponse = currentRoom.messages
                    .last(where: { $0.role == .assistant && ($0.messageType == .text || $0.messageType == .toolActivity) })?
                    .content ?? ""
                if let prev = previousStepResponse, !prev.isEmpty, !latestResponse.isEmpty {
                    let similarity = Self.wordOverlapSimilarity(prev, latestResponse)
                    if similarity > 0.6 {
                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].transitionTo(.failed)
                            rooms[i].completedAt = Date()
                        }
                        let stuckMsg = ChatMessage(
                            role: .system,
                            content: "에이전트가 동일한 응답을 반복하여 워크플로우를 중단합니다.",
                            messageType: .error
                        )
                        appendMessage(stuckMsg, to: roomID)
                        syncAgentStatuses()
                        scheduleSave()
                        return
                    }
                }
                previousStepResponse = latestResponse
            }

            // 빌드/QA 루프는 에이전트 주도로 실행 (계획 단계에서 에이전트가 직접 shell_exec으로 처리)
        }

        // 완료: 먼저 상태 변경 후 작업일지 생성 (상태가 inProgress인 동안 추가 메시지가 묻히는 문제 방지)
        if rooms.first(where: { $0.id == roomID })?.status == .inProgress {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.completed)
                rooms[i].completedAt = Date()
            }
            syncAgentStatuses()

            let doneMsg = ChatMessage(role: .system, content: "모든 작업이 완료되었습니다.")
            appendMessage(doneMsg, to: roomID)
            scheduleSave()

            // 작업일지는 방 상태 확정 후 비동기 생성
            await generateWorkLog(roomID: roomID, task: task)
        } else {
            syncAgentStatuses()
            scheduleSave()
        }
    }

    /// step 텍스트를 짧은 "~하는 중" 스타일로 변환
    static func shortenStepLabel(_ text: String) -> String {
        // 핵심 키워드 추출: 첫 번째 의미 있는 동사/명사 구문
        let cleaned = text
            .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // 긴 텍스트면 첫 문장/절만 사용 (마침표, 쉼표, 줄바꿈 기준)
        let firstClause: String
        if let range = cleaned.rangeOfCharacter(from: CharacterSet(charactersIn: ".,\n")) {
            firstClause = String(cleaned[cleaned.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        } else {
            firstClause = cleaned
        }

        // 최대 20자로 자르고 "하는 중" 접미사
        let maxLen = 20
        let truncated: String
        if firstClause.count > maxLen {
            truncated = String(firstClause.prefix(maxLen)) + "…"
        } else {
            truncated = firstClause
        }

        // 이미 "~중" 으로 끝나면 그대로 반환
        if truncated.hasSuffix("중") {
            return truncated
        }

        return "\(truncated) 하는 중…"
    }

    /// 개별 에이전트의 단계 실행. 성공 시 true, 실패 시 false.
    @discardableResult
    private func executeStep(
        step: String,
        fullTask: String,
        agentID: UUID,
        roomID: UUID,
        stepIndex: Int,
        totalSteps: Int,
        fileWriteTracker: FileWriteTracker? = nil,
        progressGroupID: UUID? = nil
    ) async -> Bool {
        guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return false }

        let room = rooms.first(where: { $0.id == roomID })

        // 브리핑 기반 컨텍스트 (압축) + 최근 메시지 + 첫 사용자 메시지(이미지 포함) 보장
        var history: [ConversationMessage] = []
        if let briefing = room?.briefing {
            history.append(ConversationMessage.user("작업 브리핑:\n\(briefing.asContextString())"))
        }

        // 첫 사용자 메시지(이미지 첨부 포함)를 항상 포함
        let recentHistory = buildRoomHistory(roomID: roomID, limit: 5)
        if let room = room,
           let firstUserMsg = room.messages.first(where: { $0.role == .user && $0.messageType == .text }),
           firstUserMsg.attachments != nil && !(firstUserMsg.attachments?.isEmpty ?? true),
           !recentHistory.contains(where: { $0.attachments != nil && !($0.attachments?.isEmpty ?? true) }) {
            history.append(ConversationMessage(
                role: "user", content: firstUserMsg.content,
                toolCalls: nil, toolCallID: nil, attachments: firstUserMsg.attachments
            ))
        }
        history.append(contentsOf: recentHistory)

        // 산출물 컨텍스트 구성
        let artifactContext: String
        if let room = room, !room.artifacts.isEmpty {
            artifactContext = "\n\n[참고 산출물]\n" + room.artifacts.map {
                "[\($0.type.displayName)] \($0.title) (v\($0.version)):\n\($0.content)"
            }.joined(separator: "\n---\n")
        } else {
            artifactContext = ""
        }

        let isLastStep = stepIndex == totalSteps - 1
        let stepPrompt: String
        if isLastStep || totalSteps == 1 {
            stepPrompt = """
            [작업 \(stepIndex + 1)/\(totalSteps)] \(step)
            \(artifactContext)

            이것이 최종 단계입니다. 사용자에게 전달할 완성된 결과물을 직접 작성하세요.
            과정 설명이나 단계 번호 없이, 결과물만 깔끔하게 출력하세요.
            """
        } else {
            stepPrompt = """
            [작업 \(stepIndex + 1)/\(totalSteps)] \(step)
            \(artifactContext)

            중간 단계입니다. 다음 단계에 필요한 핵심 데이터만 간결하게 출력하세요 (3줄 이내).
            전체 결과물은 마지막 단계에서 작성합니다.
            """
        }

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)
            speakingAgentIDByRoom[roomID] = agentID

            let context = makeToolContext(roomID: roomID, currentAgentID: agentID, fileWriteTracker: fileWriteTracker)
            let messagesWithStep = history + [ConversationMessage.user(stepPrompt)]
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: agent.resolvedSystemPrompt,
                conversationMessages: messagesWithStep,
                context: context,
                onToolActivity: { [weak self] activity in
                    Task { @MainActor in
                        let toolMsg = ChatMessage(
                            role: .assistant,
                            content: activity,
                            agentName: agent.name,
                            messageType: .toolActivity,
                            activityGroupID: progressGroupID
                        )
                        self?.appendMessage(toolMsg, to: roomID)
                    }
                }
            )

            if speakingAgentIDByRoom[roomID] == agentID {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
            }

            // 중간 단계는 toolActivity(접힘), 마지막 단계만 일반 메시지로 표시
            if isLastStep || totalSteps == 1 {
                let reply = ChatMessage(role: .assistant, content: response, agentName: agent.name)
                appendMessage(reply, to: roomID)
            } else {
                let reply = ChatMessage(role: .assistant, content: response, agentName: agent.name, messageType: .toolActivity)
                appendMessage(reply, to: roomID)
            }
            return true
        } catch {
            if speakingAgentIDByRoom[roomID] == agentID {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
            }
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "단계 실행 오류: \(error.localizedDescription)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            return false
        }
    }

    // MARK: - 빌드 루프

    /// 빌드→실패→에이전트 수정→재빌드 루프. 성공 시 true, 최대 재시도 초과 시 false.
    private func runBuildLoop(
        roomID: UUID,
        buildCommand: String,
        projectPath: String,
        fileWriteTracker: FileWriteTracker?
    ) async -> Bool {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return false }
        let maxRetries = room.maxBuildRetries

        // 빌드 루프 상태 초기화
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildLoopStatus = .building
            rooms[i].buildRetryCount = 0
        }

        let buildMsg = ChatMessage(
            role: .system,
            content: "빌드 실행 중: `\(buildCommand)`",
            messageType: .buildStatus
        )
        appendMessage(buildMsg, to: roomID)

        let result = await BuildLoopRunner.runBuild(command: buildCommand, workingDirectory: projectPath)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].lastBuildResult = result
        }

        if result.success {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildLoopStatus = .passed
            }
            let successMsg = ChatMessage(
                role: .system,
                content: "빌드 성공",
                messageType: .buildStatus
            )
            appendMessage(successMsg, to: roomID)
            return true
        }

        // 빌드 실패 → 수정 루프
        for retry in 1...maxRetries {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { return false }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildLoopStatus = .fixing
                rooms[i].buildRetryCount = retry
            }

            let failMsg = ChatMessage(
                role: .system,
                content: "빌드 실패 (시도 \(retry)/\(maxRetries)). 에이전트에게 수정 요청 중...",
                messageType: .buildStatus
            )
            appendMessage(failMsg, to: roomID)

            // 첫 번째 에이전트에게 수정 요청
            let lastOutput = rooms.first(where: { $0.id == roomID })?.lastBuildResult?.output ?? ""
            let fixPrompt = BuildLoopRunner.buildFixPrompt(
                buildCommand: buildCommand,
                buildOutput: lastOutput,
                retryNumber: retry,
                maxRetries: maxRetries
            )

            if let firstAgentID = room.assignedAgentIDs.first {
                await executeStep(
                    step: fixPrompt,
                    fullTask: "빌드 오류 수정",
                    agentID: firstAgentID,
                    roomID: roomID,
                    stepIndex: 0,
                    totalSteps: 1,
                    fileWriteTracker: fileWriteTracker
                )
            }

            // 재빌드
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildLoopStatus = .building
            }

            let rebuildMsg = ChatMessage(
                role: .system,
                content: "재빌드 실행 중... (시도 \(retry)/\(maxRetries))",
                messageType: .buildStatus
            )
            appendMessage(rebuildMsg, to: roomID)

            let retryResult = await BuildLoopRunner.runBuild(command: buildCommand, workingDirectory: projectPath)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].lastBuildResult = retryResult
            }

            if retryResult.success {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].buildLoopStatus = .passed
                }
                let successMsg = ChatMessage(
                    role: .system,
                    content: "빌드 성공 (시도 \(retry) 후)",
                    messageType: .buildStatus
                )
                appendMessage(successMsg, to: roomID)
                return true
            }
        }

        // 최대 재시도 초과
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildLoopStatus = .failed
        }
        return false
    }

    // MARK: - QA 루프

    /// 테스트→실패→에이전트 수정→재테스트 루프. 성공 시 true, 최대 재시도 초과 시 false.
    private func runQALoop(
        roomID: UUID,
        testCommand: String,
        projectPath: String,
        fileWriteTracker: FileWriteTracker?
    ) async -> Bool {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return false }
        let maxRetries = room.maxQARetries

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].qaLoopStatus = .testing
            rooms[i].qaRetryCount = 0
        }

        let testMsg = ChatMessage(
            role: .system,
            content: "테스트 실행 중: `\(testCommand)`",
            messageType: .qaStatus
        )
        appendMessage(testMsg, to: roomID)

        let result = await BuildLoopRunner.runTests(command: testCommand, workingDirectory: projectPath)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].lastQAResult = result
        }

        if result.success {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].qaLoopStatus = .passed
            }
            let successMsg = ChatMessage(
                role: .system,
                content: "테스트 통과",
                messageType: .qaStatus
            )
            appendMessage(successMsg, to: roomID)
            return true
        }

        // 테스트 실패 → 수정 루프
        for retry in 1...maxRetries {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { return false }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].qaLoopStatus = .analyzing
                rooms[i].qaRetryCount = retry
            }

            let failMsg = ChatMessage(
                role: .system,
                content: "테스트 실패 (시도 \(retry)/\(maxRetries)). 에이전트에게 수정 요청 중...",
                messageType: .qaStatus
            )
            appendMessage(failMsg, to: roomID)

            let lastOutput = rooms.first(where: { $0.id == roomID })?.lastQAResult?.output ?? ""
            let fixPrompt = BuildLoopRunner.qaFixPrompt(
                testCommand: testCommand,
                testOutput: lastOutput,
                retryNumber: retry,
                maxRetries: maxRetries
            )

            // QA 에이전트 우선, 없으면 첫 번째 에이전트
            let fixAgentID = qaAgentID(in: room) ?? room.assignedAgentIDs.first
            if let agentID = fixAgentID {
                await executeStep(
                    step: fixPrompt,
                    fullTask: "테스트 실패 수정",
                    agentID: agentID,
                    roomID: roomID,
                    stepIndex: 0,
                    totalSteps: 1,
                    fileWriteTracker: fileWriteTracker
                )
            }

            // 재테스트
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].qaLoopStatus = .testing
            }

            let retestMsg = ChatMessage(
                role: .system,
                content: "재테스트 실행 중... (시도 \(retry)/\(maxRetries))",
                messageType: .qaStatus
            )
            appendMessage(retestMsg, to: roomID)

            let retryResult = await BuildLoopRunner.runTests(command: testCommand, workingDirectory: projectPath)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].lastQAResult = retryResult
            }

            if retryResult.success {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].qaLoopStatus = .passed
                }
                let successMsg = ChatMessage(
                    role: .system,
                    content: "테스트 통과 (시도 \(retry) 후)",
                    messageType: .qaStatus
                )
                appendMessage(successMsg, to: roomID)
                return true
            }
        }

        // 최대 재시도 초과
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].qaLoopStatus = .failed
        }
        return false
    }

    /// QA 에이전트 우선 선택 (이름/페르소나에 QA 키워드 포함 에이전트 우선)
    private func qaAgentID(in room: Room) -> UUID? {
        for agentID in room.assignedAgentIDs {
            if let agent = agentStore?.agents.first(where: { $0.id == agentID }),
               agent.name.lowercased().contains("qa") || agent.persona.lowercased().contains("qa") {
                return agentID
            }
        }
        return nil
    }

    // MARK: - 토론 실행

    /// 합의 기반 토론 실행 (합의 도달 시 자동 종료, 최대 10라운드)
    private func executeDiscussion(roomID: UUID, topic: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let maxSafetyRounds = min(room.maxDiscussionRounds, 3)

        for round in 0..<maxSafetyRounds {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive else { break }

            // 라운드 업데이트
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].currentRound = round
            }

            let roundMsg = ChatMessage(
                role: .system,
                content: "── 토론 라운드 \(round + 1) ──",
                messageType: .discussionRound
            )
            appendMessage(roundMsg, to: roomID)

            // 각 에이전트가 순차적으로 발언 + 합의 여부 수집
            var agreedCount = 0
            let agentIDs = room.assignedAgentIDs

            for agentID in agentIDs {
                guard !Task.isCancelled,
                      let current = rooms.first(where: { $0.id == roomID }),
                      current.isActive else { break }

                let agreed = await executeDiscussionTurn(
                    topic: topic,
                    agentID: agentID,
                    roomID: roomID,
                    round: round
                )
                if agreed { agreedCount += 1 }
            }

            // 전원 합의 → 토론 종료
            if agreedCount == agentIDs.count && agentIDs.count > 0 {
                let consensusMsg = ChatMessage(
                    role: .system,
                    content: "전원 합의 도달. 토론을 마무리합니다."
                )
                appendMessage(consensusMsg, to: roomID)
                break
            }

            // 최소 2라운드 이상 + 과반 합의 → 종료
            if round >= 1 && agreedCount > agentIDs.count / 2 {
                let consensusMsg = ChatMessage(
                    role: .system,
                    content: "과반 합의 도달. 토론을 마무리합니다."
                )
                appendMessage(consensusMsg, to: roomID)
                break
            }
        }

        let doneMsg = ChatMessage(role: .system, content: "토론이 완료되었습니다. 계획 수립으로 넘어갑니다.")
        appendMessage(doneMsg, to: roomID)
        scheduleSave()
    }

    /// 개별 에이전트의 토론 턴. 합의 여부를 Bool로 리턴.
    @discardableResult
    private func executeDiscussionTurn(
        topic: String,
        agentID: UUID,
        roomID: UUID,
        round: Int
    ) async -> Bool {
        guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return false }

        // 토론 히스토리 (이미지는 존재 여부만 알림 — 실제 작업은 실행 단계에서)
        let roomRef = rooms.first(where: { $0.id == roomID })
        var history: [ConversationMessage] = []
        // 첫 사용자 메시지: 이미지 첨부 시 텍스트로 존재 알림 (파일 전달 안 함)
        if let firstUserMsg = roomRef?.messages.first(where: { $0.role == .user && $0.messageType == .text }) {
            var content = firstUserMsg.content
            if let attachments = firstUserMsg.attachments, !attachments.isEmpty {
                content += "\n\n[첨부 이미지 \(attachments.count)장 — 실행 단계에서 확인 가능]"
            }
            history.append(ConversationMessage.user(content))
        }
        // 토론 히스토리 추가
        let discussionMsgs = buildDiscussionHistory(roomID: roomID, currentAgentName: agent.name)
        history.append(contentsOf: discussionMsgs.map { msg in
            ConversationMessage(role: msg.role, content: msg.content, toolCalls: nil, toolCallID: nil, attachments: nil)
        })

        // 동료 목록: 이름(역할) 형태로 구성, PM과 전문가 구분
        let otherAgents = roomRef?.assignedAgentIDs
            .compactMap { id in agentStore?.agents.first(where: { $0.id == id }) }
            .filter { $0.id != agentID } ?? []
        let pmName = otherAgents.first(where: { $0.isMaster })?.name
        let specialists = otherAgents.filter { !$0.isMaster }
        let specialistDesc = specialists.map { $0.name }.joined(separator: ", ")
        let otherNames = otherAgents.map { $0.name }.joined(separator: ", ")

        // 마스터(오케스트레이터) 여부 판별
        let isMasterAgent = agent.isMaster

        let discussionPrompt: String
        if isMasterAgent {
            // 마스터: 요구사항 전달만, 직접 작업 금지
            discussionPrompt = """
            당신은 PM/오케스트레이터입니다. 토론에서의 역할:
            - 전문가에게 사용자의 요구사항을 간결하게 전달
            - 전문가의 질문에 답변
            - 작업 방향이 맞는지 확인하고, 전문가의 업무를 대신 수행하지 않습니다

            [절대 금지] 번역, 코딩, 문서 작성 등 실제 작업 수행
            [절대 금지] 전문가의 업무를 대신 수행

            [회의실] \(topic)
            라운드 \(round + 1) | 전문가: \(specialistDesc)

            2문장 이내로 발언하세요.
            발언 마지막 줄에 [합의] 또는 [계속] 태그를 붙이세요.
            """
        } else {
            // 전문가: 자기 역할에 맞는 작업
            let pmNote = pmName != nil ? "\(pmName!)은 PM입니다. 전문적인 질문은 다른 전문가에게 직접 하세요." : ""
            discussionPrompt = """
            \(agent.resolvedSystemPrompt)

            [회의실] \(topic)
            라운드 \(round + 1) | 동료: \(otherNames)
            \(pmNote)

            첨부된 이미지나 파일이 있으면 내용을 확인하고 참고하세요.
            2-4문장으로 핵심만 말하세요.
            발언 마지막 줄에 [합의] 또는 [계속] 태그를 붙이세요.
            """
        }

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)
            speakingAgentIDByRoom[roomID] = agentID

            let responseContent = try await provider.sendMessageWithTools(
                model: agent.modelName,
                systemPrompt: discussionPrompt,
                messages: history,
                tools: []
            )
            let response: String
            switch responseContent {
            case .text(let t): response = t
            case .toolCalls: response = "[합의]"
            case .mixed(let t, _): response = t
            }

            speakingAgentIDByRoom.removeValue(forKey: roomID)

            // [합의] 태그 확인 후 메시지에서 태그 제거
            let agreed = response.contains("[합의]")
            let cleanResponse = response
                .replacingOccurrences(of: "[합의]", with: "")
                .replacingOccurrences(of: "[계속]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 산출물 파싱 → Room에 저장
            let newArtifacts = ArtifactParser.extractArtifacts(from: cleanResponse, producedBy: agent.name)
            if !newArtifacts.isEmpty, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                for artifact in newArtifacts {
                    if let existingIdx = rooms[i].artifacts.firstIndex(where: {
                        $0.type == artifact.type && $0.title == artifact.title
                    }) {
                        var updated = artifact
                        updated.version = rooms[i].artifacts[existingIdx].version + 1
                        rooms[i].artifacts[existingIdx] = updated
                    } else {
                        rooms[i].artifacts.append(artifact)
                    }
                }
            }
            let displayResponse = ArtifactParser.stripArtifactBlocks(from: cleanResponse)

            let reply = ChatMessage(role: .assistant, content: displayResponse.isEmpty ? cleanResponse : displayResponse, agentName: agent.name, messageType: .discussion)
            appendMessage(reply, to: roomID)

            return agreed
        } catch {
            speakingAgentIDByRoom.removeValue(forKey: roomID)
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "발언 실패: \(error.localizedDescription)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            return false
        }
    }

    /// 토론 브리핑 생성 (컨텍스트 압축)
    private func generateBriefing(roomID: UUID, topic: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        let summaryMsg = ChatMessage(role: .system, content: "토론 브리핑을 생성하는 중...")
        appendMessage(summaryMsg, to: roomID)

        let history = buildDiscussionHistory(roomID: roomID, currentAgentName: nil)

        // 산출물 목록도 포함
        let artifactList = room.artifacts.isEmpty ? "" :
            "\n\n산출물 목록:\n" + room.artifacts.map { "- [\($0.type.displayName)] \($0.title)" }.joined(separator: "\n")

        let briefingPrompt = """
        토론 내용을 분석하여 실행팀을 위한 브리핑 문서를 JSON으로 작성하세요.\(artifactList)

        반드시 아래 형식의 JSON으로만 응답하세요:
        {"summary": "작업 요약 2-3문장", "key_decisions": ["결정1", "결정2"], "agent_responsibilities": {"에이전트명": "담당역할"}, "open_issues": ["미결사항"]}

        규칙:
        - summary: 팀이 합의한 방향과 핵심 목표 (2-3문장)
        - key_decisions: 토론에서 확정된 결정사항 (3-5개)
        - agent_responsibilities: 각 참여자의 담당 역할 (토론에서 드러난 전문성 기반)
        - open_issues: 추가 논의가 필요한 미결 사항 (없으면 빈 배열)
        - 반드시 유효한 JSON으로만 응답하세요
        """

        do {
            let response = try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: briefingPrompt,
                messages: history
            )

            // JSON 파싱 → RoomBriefing
            if let briefing = parseBriefing(from: response) {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].briefing = briefing
                }
                let reply = ChatMessage(
                    role: .assistant,
                    content: briefing.asContextString(),
                    agentName: "토론 정리",
                    messageType: .summary
                )
                appendMessage(reply, to: roomID)
            } else {
                // JSON 파싱 실패 → 폴백 브리핑
                let fallback = RoomBriefing(
                    summary: response.prefix(500).description,
                    keyDecisions: [],
                    agentResponsibilities: [:],
                    openIssues: []
                )
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].briefing = fallback
                }
                let reply = ChatMessage(
                    role: .assistant,
                    content: response,
                    agentName: "토론 정리",
                    messageType: .summary
                )
                appendMessage(reply, to: roomID)
            }
        } catch {
            let errorMsg = ChatMessage(
                role: .system,
                content: "브리핑 생성 실패: \(error.localizedDescription)",
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }
    }

    /// 브리핑 JSON 파싱
    private func parseBriefing(from response: String) -> RoomBriefing? {
        let jsonString = extractJSON(from: response)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["summary"] as? String else {
            return nil
        }
        let keyDecisions = json["key_decisions"] as? [String] ?? []
        let responsibilities = json["agent_responsibilities"] as? [String: String] ?? [:]
        let openIssues = json["open_issues"] as? [String] ?? []
        return RoomBriefing(
            summary: summary,
            keyDecisions: keyDecisions,
            agentResponsibilities: responsibilities,
            openIssues: openIssues
        )
    }

    /// 토론용 히스토리 빌드 (에이전트 이름을 명시하여 누가 말했는지 구분)
    private func buildDiscussionHistory(roomID: UUID, currentAgentName: String?) -> [(role: String, content: String)] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.messages
            .filter { $0.messageType == .text || $0.messageType == .discussion || $0.messageType == .discussionRound }
            .suffix(40)
            .map { msg in
                let role: String
                let content: String
                switch msg.role {
                case .user:
                    role = "user"
                    content = msg.content
                case .assistant:
                    // 자신의 발언은 assistant, 다른 에이전트 발언은 user로 (컨텍스트 구분)
                    if let agentName = msg.agentName, agentName == currentAgentName {
                        role = "assistant"
                        content = msg.content
                    } else {
                        role = "user"
                        content = "[\(msg.agentName ?? "에이전트")의 발언]: \(msg.content)"
                    }
                case .system:
                    role = "user"
                    content = "[시스템]: \(msg.content)"
                }
                return (role: role, content: content)
            }
    }

    // MARK: - 유사도 계산

    /// 두 텍스트의 단어 집합 Jaccard 유사도 (0.0~1.0)
    /// 분석 결과에서 "전문가:" 라인의 역할명을 추출
    static func extractRoleName(from analysisText: String) -> String? {
        for line in analysisText.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "- 전문가: 다국어 번역 전문가 (이미지 OCR + 번역)" 형태
            guard trimmed.contains("전문가"), let colonRange = trimmed.range(of: ":") else { continue }
            var role = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            // 괄호 이후 제거: "다국어 번역 전문가 (설명)" → "다국어 번역 전문가"
            if let parenIdx = role.firstIndex(of: "(") {
                role = String(role[..<parenIdx]).trimmingCharacters(in: .whitespaces)
            }
            if !role.isEmpty { return role }
        }
        return nil
    }

    /// 태스크 텍스트에서 역할 키워드 추출 (단일 — 레거시 호환)
    static func extractRoleFromTask(_ task: String) -> String {
        return extractRolesFromTask(task).first ?? "전문가"
    }

    /// 정보 조회/리서치성 요청인지 판별 (계획 승인 스킵 등에 사용)
    static func isInfoRequest(_ task: String) -> Bool {
        let infoKeywords = ["트렌드", "알려", "듣고", "설명", "비교", "추천", "조사", "정리", "요약", "조회", "정보", "알고싶", "궁금", "찾아"]
        return infoKeywords.contains(where: { task.contains($0) })
    }

    /// 태스크 텍스트에서 모든 역할 키워드 추출 (복수)
    static func extractRolesFromTask(_ task: String) -> [String] {
        let keywords: [(pattern: String, role: String)] = [
            // 더 구체적인 키워드를 먼저 매칭 (프론트엔드/백엔드 구분)
            ("프론트엔드", "프론트엔드 개발자"),
            ("프론트", "프론트엔드 개발자"),
            ("frontend", "프론트엔드 개발자"),
            ("백엔드", "백엔드 개발자"),
            ("backend", "백엔드 개발자"),
            ("번역", "번역 전문가"),
            ("翻訳", "번역 전문가"),
            ("translate", "번역 전문가"),
            ("코딩", "개발자"),
            ("개발", "개발자"),
            ("구현", "개발자"),
            ("코드", "개발자"),
            ("테스트", "QA 엔지니어"),
            ("디자인", "디자이너"),
            ("기획", "기획자"),
            ("문서", "테크라이터"),
            ("분석", "분석가"),
            ("리뷰", "코드 리뷰어"),
            ("배포", "DevOps 엔지니어"),
        ]
        let lowered = task.lowercased()
        var roles: [String] = []
        var seen: Set<String> = []
        for kw in keywords {
            if lowered.contains(kw.pattern) && !seen.contains(kw.role) {
                roles.append(kw.role)
                seen.insert(kw.role)
            }
        }
        // 구체적 역할이 있으면 범용 "개발자" 제거 (예: 프론트엔드 + 백엔드 → "개발자" 불필요)
        let specificDevRoles = roles.filter { $0 != "개발자" && $0.contains("개발자") }
        if !specificDevRoles.isEmpty {
            roles.removeAll { $0 == "개발자" }
        }
        return roles
    }

    /// 역할명과 기존 에이전트 이름을 비교하여 가장 유사한 에이전트 반환
    static func findMatchingAgent(roleName: String, among agents: [Agent]) -> Agent? {
        guard !agents.isEmpty else { return nil }
        let roleLower = roleName.lowercased()
        // 상충 키워드 쌍: 한쪽이 roleName에 있고 다른 쪽이 agentName에 있으면 매칭 금지
        let conflictPairs: [(String, String)] = [
            ("프론트엔드", "백엔드"), ("frontend", "backend"),
            ("프론트", "백엔드"), ("백엔드", "프론트"),
            ("ios", "android"), ("web", "app"),
        ]

        var bestMatch: (agent: Agent, score: Int) = (agents[0], 0)
        for agent in agents {
            let nameLower = agent.name.lowercased()
            var score = 0
            // 정확 일치
            if roleLower == nameLower { return agent }

            // 상충 키워드 검사
            var conflicted = false
            for (a, b) in conflictPairs {
                if (roleLower.contains(a) && nameLower.contains(b)) ||
                   (roleLower.contains(b) && nameLower.contains(a)) {
                    conflicted = true
                    break
                }
            }
            if conflicted { continue }

            // 부분 문자열 포함 (한국어 대응: "번역가" ⊂ "번역 전문가")
            if roleLower.contains(nameLower) || nameLower.contains(roleLower) {
                score += 10
            }
            // 핵심 키워드 겹침 (2글자 이상 공통 부분문자열)
            let roleWords = roleLower.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
            let nameWords = nameLower.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
            for rw in roleWords {
                for nw in nameWords {
                    if rw.count >= 2 && nw.count >= 2 && (rw.contains(nw) || nw.contains(rw)) {
                        score += 5
                    }
                }
            }
            if score > bestMatch.score {
                bestMatch = (agent, score)
            }
        }
        return bestMatch.score >= 5 ? bestMatch.agent : nil
    }

    static func wordOverlapSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init))
        let wordsB = Set(b.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0.0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union)
    }

    // MARK: - 작업일지 생성

    private func generateWorkLog(roomID: UUID, task: String) async {
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
            let response = try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: logPrompt,
                messages: history + [("user", "작업: \(task)")]
            )

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
                rooms[i].workLog = log
            }

            let logMsg = ChatMessage(role: .system, content: "작업일지가 생성되었습니다.")
            appendMessage(logMsg, to: roomID)
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
            rooms[i].workLog = log
        }
        scheduleSave()
    }

    // MARK: - 방 상태 관리

    func completeRoom(_ roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        // 진행 중인 워크플로우 취소
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        // 대기 중인 continuation 해제
        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = userInputContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: "")
        }
        if let cont = suggestionContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        guard rooms[idx].transitionTo(.completed) else { return }
        rooms[idx].completedAt = Date()

        // 작업일지 생성 (수동 완료 시에도)
        let task = rooms[idx].messages.first(where: { $0.role == .user })?.content ?? rooms[idx].title
        Task { await generateWorkLog(roomID: roomID, task: task) }

        syncAgentStatuses()
        scheduleSave()
    }

    /// 사용자가 승인 카드에서 취소 → 작업 종료
    func cancelRoom(roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = userInputContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: "")
        }
        if let cont = suggestionContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        rooms[idx].transitionTo(.failed)
        rooms[idx].completedAt = Date()
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
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        // 대기 중인 승인 continuation 해제
        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }

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
            default: newStatus = .busy   // 3개+ 방 참여 시 바쁨
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
    private func buildSimpleHistory(roomID: UUID) -> [(role: String, content: String)] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.messages
            .filter { $0.messageType == .text }
            .suffix(20)
            .map { msg in
                let role: String
                switch msg.role {
                case .user:      role = "user"
                case .assistant: role = "assistant"
                case .system:    role = "user"
                }
                return (role: role, content: msg.content)
            }
    }

    /// ConversationMessage 히스토리 (이미지 첨부 포함, smartSend용)
    private func buildRoomHistory(roomID: UUID, limit: Int = 20) -> [ConversationMessage] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.messages
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
                    content: msg.content,
                    toolCalls: nil,
                    toolCallID: nil,
                    attachments: msg.attachments
                )
            }
    }

    // MARK: - 영속화

    private static var roomDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentmanager")
        let dir = appSupport.appendingPathComponent("DOUGLAS/rooms", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveRooms()
        }
    }

    private func saveRooms() {
        let dir = Self.roomDirectory
        for room in rooms {
            let file = dir.appendingPathComponent("\(room.id.uuidString).json")
            if let data = try? JSONEncoder().encode(room) {
                try? data.write(to: file)
            }
        }
    }

    func loadRooms() {
        let dir = Self.roomDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        var loaded: [Room] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let room = try? JSONDecoder().decode(Room.self, from: data) else { continue }
            loaded.append(room)
        }
        rooms = loaded.sorted { $0.createdAt > $1.createdAt }
    }
}
