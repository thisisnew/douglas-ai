import Foundation

@MainActor
class RoomManager: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var selectedRoomID: UUID?
    /// 마스터 위임으로 자동 생성된 방 → UI에서 자동으로 창을 열기 위한 트리거
    @Published var pendingAutoOpenRoomID: UUID?
    /// 방별 현재 발언 중인 에이전트 (UI 표시용, 영속화 안 함)
    @Published var speakingAgentIDByRoom: [UUID: UUID] = [:]
    /// Intent 선택 대기 중인 방 (방 ID → LLM 추천 intent)
    @Published var pendingIntentSelection: [UUID: WorkflowIntent] = [:]

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
    /// Intent 선택 대기 중인 continuation (방 ID → continuation)
    private var intentContinuations: [UUID: CheckedContinuation<WorkflowIntent, Never>] = [:]
    /// 이전 사이클 완료 시점의 에이전트 수 (후속 사이클에서 에이전트 변동 감지용)
    private var previousCycleAgentCount: [UUID: Int] = [:]

    /// 플러그인 이벤트 디스패치 (PluginManager가 설정)
    var pluginEventDelegate: ((PluginEvent) -> Void)?

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
        room.intent = intent
        rooms.append(room)
        selectedRoomID = room.id
        syncAgentStatuses()
        scheduleSave()
        pluginEventDelegate?(.roomCreated(roomID: room.id, title: room.title))
        return room
    }

    /// 사용자 수동 방 생성 + 바로 작업 시작
    func createManualRoom(title: String, agentIDs: [UUID], task: String, projectPaths: [String] = [], buildCommand: String? = nil, testCommand: String? = nil, intent: WorkflowIntent? = nil) {
        // 마스터를 첫 번째로 배치 (intake/clarify는 항상 마스터가 수행)
        var orderedIDs = agentIDs
        if let masterID = agentStore?.masterAgent?.id {
            orderedIDs.removeAll { $0 == masterID }
            orderedIDs.insert(masterID, at: 0)
        }
        let room = createRoom(title: title, agentIDs: orderedIDs, createdBy: .user, projectPaths: projectPaths, buildCommand: buildCommand, testCommand: testCommand, intent: intent)

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
        pluginEventDelegate?(.messageAdded(roomID: roomID, message: message))
    }

    // MARK: - 승인 게이트

    /// 승인 대기 중인 단계를 승인
    func approveStep(roomID: UUID) {
        let msg = ChatMessage(role: .user, content: "승인")
        appendMessage(msg, to: roomID)

        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: true)
        } else {
            // 워크플로우 없음 (예전 방/앱 재시작) → 워크플로우 재시작
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            let task = rooms[idx].title
            rooms[idx].transitionTo(.planning)
            launchWorkflow(roomID: roomID, task: task)
        }
    }

    /// 승인 대기 중인 단계를 거부 (수정 요청)
    func rejectStep(roomID: UUID) {
        let msg = ChatMessage(role: .system, content: "수정 요청")
        appendMessage(msg, to: roomID)

        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            cont.resume(returning: false)
        } else {
            // 워크플로우 없음 (예전 방/앱 재시작) → 방 취소
            cancelRoom(roomID: roomID)
        }
    }

    /// 승인 카드에서 추가 요구사항 입력 시 방 메시지에 추가
    func appendAdditionalInput(roomID: UUID, text: String) {
        let msg = ChatMessage(role: .user, content: text)
        appendMessage(msg, to: roomID)
    }

    // MARK: - Intent 선택 게이트

    /// 사용자가 Intent를 선택
    func selectIntent(roomID: UUID, intent: WorkflowIntent) {
        pendingIntentSelection.removeValue(forKey: roomID)
        let msg = ChatMessage(role: .user, content: "\(intent.displayName) 선택")
        appendMessage(msg, to: roomID)

        if let cont = intentContinuations.removeValue(forKey: roomID) {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            cont.resume(returning: intent)
        } else {
            // 워크플로우 없음 (앱 재시작 등) → intent 설정 후 워크플로우 재시작
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            rooms[idx].intent = intent
            rooms[idx].transitionTo(.planning)
            launchWorkflow(roomID: roomID, task: rooms[idx].title)
        }
    }

    // MARK: - 사용자 입력 게이트

    /// ask_user 도구에 대한 사용자 답변 제출
    func answerUserQuestion(roomID: UUID, answer: String) {
        let msg = ChatMessage(role: .user, content: answer)
        appendMessage(msg, to: roomID)
        // userAnswers에 저장 (질문은 메시지에서 역추적)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            let userAnswer = UserAnswer(question: "", answer: answer)
            if rooms[idx].userAnswers == nil { rooms[idx].userAnswers = [] }
            rooms[idx].userAnswers?.append(userAnswer)
        }

        if let cont = userInputContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: answer)
        } else {
            // 워크플로우 없음 (앱 재시작 등) → 워크플로우 재시작
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            let task = rooms[idx].title
            rooms[idx].transitionTo(.planning)
            launchWorkflow(roomID: roomID, task: task)
        }
    }

    /// 사용자가 방에 메시지 보내기
    func sendUserMessage(_ text: String, to roomID: UUID, attachments: [ImageAttachment]? = nil) async {
        // /@멘션 파싱: 에이전트 초대 + 순수 텍스트 분리
        let allSubAgents = agentStore?.subAgents ?? []
        let parsed = MentionParser.parse(text, agents: allSubAgents)
        for agent in parsed.mentions {
            addAgent(agent.id, to: roomID)
        }
        let cleanText = parsed.cleanText

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

        // 완료/실패 상태: 후속 사이클 시작
        let task = cleanText.isEmpty ? text : cleanText
        roomTasks[roomID]?.cancel()
        roomTasks[roomID] = Task {
            await launchFollowUpCycle(roomID: roomID, task: task)
            roomTasks.removeValue(forKey: roomID)
        }
    }

    /// 후속 사이클: 완료/실패 방에서 후속 질문 시 assemble부터 경량 워크플로우 재실행
    private func launchFollowUpCycle(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // 이전 작업 컨텍스트 주입 (방 재활성화 전에 workLog 캡처)
        if let workLog = rooms[idx].workLog {
            let contextMsg = ChatMessage(
                role: .system,
                content: workLog.asContextString()
            )
            appendMessage(contextMsg, to: roomID)
        }

        // 방 재활성화
        rooms[idx].transitionTo(.planning)
        rooms[idx].completedAt = nil

        // Intent 재분류 (새 질문 기준)
        // quickClassify 성공 = 규칙 매칭(확신 높음), nil = LLM/fallback 필요(확신 낮음)
        let ruleBasedIntent = IntentClassifier.quickClassify(task)
        var resolvedIntent = ruleBasedIntent
        if resolvedIntent == nil {
            if let firstAgentID = rooms[idx].assignedAgentIDs.first,
               let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
               let provider = providerManager?.provider(named: agent.providerName) {
                resolvedIntent = await IntentClassifier.classifyWithLLM(
                    task: task, provider: provider, model: agent.modelName
                )
            }
        }
        rooms[idx].intent = resolvedIntent ?? .quickAnswer

        syncAgentStatuses()

        // 후속 사이클 스킵 범위 결정:
        // - 규칙 기반 quickAnswer 확정 + 에이전트 변동 없음 → clarify/assemble 스킵 (즉답은 빠르게)
        // - 에이전트가 새로 추가됐으면 → assemble 수행 (새 에이전트 통합)
        // - 그 외 (LLM/fallback으로 분류됨) → clarify 수행 (의도 확인 필요)
        var completedPhases: Set<WorkflowPhase> = [.intake, .intent]
        let specialists = executingAgentIDs(in: roomID)
        let previousAgentCount = previousCycleAgentCount[roomID] ?? specialists.count
        let agentsChanged = specialists.count != previousAgentCount
        if ruleBasedIntent == .quickAnswer && !specialists.isEmpty && !agentsChanged {
            completedPhases.insert(.clarify)
            completedPhases.insert(.assemble)
        }
        // 현재 에이전트 수 기록 (다음 후속 사이클 비교용)
        previousCycleAgentCount[roomID] = specialists.count

        while true {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive,
                  let currentIntent = currentRoom.intent else { break }

            let phases = currentIntent.requiredPhases
            guard let nextPhase = phases.first(where: { !completedPhases.contains($0) }) else { break }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].currentPhase = nextPhase
            }
            scheduleSave()

            switch nextPhase {
            case .intake, .intent:
                break
            case .clarify:
                await executeClarifyPhase(roomID: roomID, task: task)
            case .assemble:
                await executeAssemblePhase(roomID: roomID, task: task)
            case .plan:
                let intent = rooms.first(where: { $0.id == roomID })?.intent ?? .quickAnswer
                await executePlanPhase(roomID: roomID, task: task, intent: intent)
            case .execute:
                let intent = rooms.first(where: { $0.id == roomID })?.intent ?? .quickAnswer
                await executeExecutePhase(roomID: roomID, task: task, intent: intent)
            case .review:
                await executeReviewPhase(roomID: roomID, task: task)
            }

            completedPhases.insert(nextPhase)
        }

        // 완료 (review 단계에서 이미 완료 처리된 경우 스킵)
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed && rooms[i].status != .completed {
            rooms[i].currentPhase = nil
            rooms[i].status = .completed
            rooms[i].completedAt = Date()
            pluginEventDelegate?(.roomCompleted(roomID: roomID, title: rooms[i].title))
        }
        syncAgentStatuses()
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
        addAgent(newAgent.id, to: roomID, silent: true)

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

    func addAgent(_ agentID: UUID, to roomID: UUID, silent: Bool = false) {
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

        if !silent, let agentName = agentStore?.agents.first(where: { $0.id == agentID })?.name {
            let systemMsg = ChatMessage(role: .system, content: "\(agentName)이(가) 방에 참여했습니다.")
            appendMessage(systemMsg, to: roomID)
        }
    }

    // MARK: - 방 워크플로우

    /// 워크플로우 진입점: 항상 Intent 기반 Phase 워크플로우
    func startRoomWorkflow(roomID: UUID, task: String) async {
        // intent 미설정 → quickClassify 시도 (nil이면 executeIntentPhase에서 사용자 선택)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }), rooms[idx].intent == nil {
            rooms[idx].intent = IntentClassifier.quickClassify(task)
            // quickClassify 실패 시 nil 유지 → executeIntentPhase에서 처리
        }
        await executePhaseWorkflow(roomID: roomID, task: task)
    }

    // legacyStartRoomWorkflow 삭제됨 — 모든 워크플로우는 executePhaseWorkflow를 통해 Intent 기반으로 실행

    /// 실행 대상 에이전트 (마스터 제외)
    private func executingAgentIDs(in roomID: UUID) -> [UUID] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.assignedAgentIDs.filter { id in
            let agent = agentStore?.agents.first(where: { $0.id == id })
            return !(agent?.isMaster ?? false)
        }
    }

    // MARK: - Phase 워크플로우 (새 7단계)

    /// 새 워크플로우: intent.requiredPhases 동적 순회
    /// intent 단계에서 LLM 재분류 후 남은 단계가 자동으로 재계산됨
    /// 워크플로우 전체 타임아웃 (초)
    private static let workflowTimeoutSeconds: TimeInterval = 600 // 10분

    private func executePhaseWorkflow(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        rooms[idx].status = .planning
        syncAgentStatuses()

        var workflowStart = Date()
        var completedPhases: Set<WorkflowPhase> = []

        while true {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive else { break }

            // 타임아웃 체크
            if Date().timeIntervalSince(workflowStart) > Self.workflowTimeoutSeconds {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                let timeoutMsg = ChatMessage(
                    role: .system,
                    content: "워크플로우가 제한 시간(10분)을 초과하여 자동 종료되었습니다.",
                    messageType: .error
                )
                appendMessage(timeoutMsg, to: roomID)
                syncAgentStatuses()
                scheduleSave()
                return
            }

            let currentIntent = currentRoom.intent ?? .quickAnswer
            // 현재 intent 기준으로 다음 미완료 phase 찾기
            let phases = currentIntent.requiredPhases
            guard let nextPhase = phases.first(where: { !completedPhases.contains($0) }) else { break }

            // 현재 단계 기록 (내부 상태만, UI 메시지 없음)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].currentPhase = nextPhase
            }
            scheduleSave()

            switch nextPhase {
            case .intake:
                await executeIntakePhase(roomID: roomID, task: task)
            case .intent:
                await executeIntentPhase(roomID: roomID, task: task)
            case .clarify:
                await executeClarifyPhase(roomID: roomID, task: task)
            case .assemble:
                await executeAssemblePhase(roomID: roomID, task: task)
            case .plan:
                let intent = rooms.first(where: { $0.id == roomID })?.intent ?? .quickAnswer
                await executePlanPhase(roomID: roomID, task: task, intent: intent)
            case .execute:
                let intent = rooms.first(where: { $0.id == roomID })?.intent ?? .quickAnswer
                await executeExecutePhase(roomID: roomID, task: task, intent: intent)
            case .review:
                await executeReviewPhase(roomID: roomID, task: task)
            }

            completedPhases.insert(nextPhase)
            workflowStart = Date() // 단계 완료 후 타이머 리셋 (사용자 대기 시간으로 인한 타임아웃 방지)
        }

        // 워크플로우 완료
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed {
            rooms[i].currentPhase = nil
            rooms[i].status = .completed
            rooms[i].completedAt = Date()
            pluginEventDelegate?(.roomCompleted(roomID: roomID, title: rooms[i].title))
        }
        syncAgentStatuses()
        scheduleSave()
    }

    /// Intent 단계: quickClassify 결과에 따라 LLM 재분류 또는 사용자 선택
    private func executeIntentPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let currentIntent = rooms[idx].intent

        // 1) quickClassify가 nil → LLM 추천 후 사용자에게 선택 카드 표시
        if currentIntent == nil {
            guard let firstAgentID = rooms[idx].assignedAgentIDs.first,
                  let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
                  let provider = providerManager?.provider(named: agent.providerName) else {
                rooms[idx].intent = .implementation
                return
            }

            let suggested = await IntentClassifier.classifyWithLLM(
                task: task,
                provider: provider,
                model: agent.modelName
            )

            // 사용자 선택 UI 표시
            pendingIntentSelection[roomID] = suggested

            let selectedIntent = await withCheckedContinuation { (cont: CheckedContinuation<WorkflowIntent, Never>) in
                intentContinuations[roomID] = cont
            }

            rooms[idx].intent = selectedIntent
            postIntentExplanation(roomID: roomID)
            scheduleSave()
            return
        }

        // 2) quickClassify가 정확한 결과를 반환한 경우 (implementation이 아닌 경우) 재분류 불필요
        guard currentIntent == .implementation else {
            postIntentExplanation(roomID: roomID)
            return
        }

        // 3) implementation → LLM으로 재분류 시도
        guard let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            postIntentExplanation(roomID: roomID)
            return
        }

        let newIntent = await IntentClassifier.classifyWithLLM(
            task: task,
            provider: provider,
            model: agent.modelName
        )

        // intent가 변경되면 업데이트 → while 루프가 새 requiredPhases로 재계산
        if newIntent != currentIntent {
            rooms[idx].intent = newIntent
        }
        postIntentExplanation(roomID: roomID)
        scheduleSave()
    }

    /// Intent 확정 후 사용자에게 워크플로우 설명 메시지 표시
    private func postIntentExplanation(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let intent = room.intent else { return }

        let msg = ChatMessage(
            role: .system,
            content: "[\(intent.displayName)] \(intent.subtitle)\n진행: \(intent.phaseSummary)",
            messageType: .phaseTransition
        )
        appendMessage(msg, to: roomID)
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

        // 4) 플레이북 로드 (내부 데이터만, UI 메시지 없음)
        if let projectPath = rooms[idx].primaryProjectPath {
            if let playbook = PlaybookManager.load(from: projectPath) {
                rooms[idx].playbook = playbook
            }
        }
        scheduleSave()
    }

    /// Clarify 단계: 복명복창 — DOUGLAS가 이해한 내용을 요약하고 사용자 컨펌까지 무한 루프
    private func executeClarifyPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        // 컨텍스트 구성: IntakeData + 플레이북
        var contextParts: [String] = []
        if let intakeData = rooms[idx].intakeData {
            contextParts.append(intakeData.asContextString())
        }
        if let playbook = rooms[idx].playbook {
            contextParts.append(playbook.asContextString())
        }
        let contextString = contextParts.joined(separator: "\n\n")

        // Intent 정보
        let intentName = rooms[idx].intent?.displayName ?? "구현"

        // 이미지 첨부 파일 수집 (LLM에 직접 전달)
        let imageAttachments = rooms[idx].messages
            .compactMap { $0.attachments }
            .flatMap { $0 }

        let clarifySystemPrompt = """
        \(agent.resolvedSystemPrompt)

        당신은 요건 확인(Clarify) 단계를 수행하고 있습니다.
        사용자의 요청을 정확히 이해했는지 복명복창(확인)만 합니다.

        아래 형식으로 이해한 내용을 요약하세요:
        - 작업 유형: \(intentName)
        - 요청 내용: (1-2문장 요약)
        - 핵심 요구사항: (불릿 포인트)
        - 예상 산출물: (무엇이 나와야 하는지)

        [절대 금지]
        - 위 4개 항목 외의 내용을 출력하지 마세요.
        - 질문에 대한 답변, 개념 설명, 해결책을 작성하지 마세요.
        - 작업을 수행하지 마세요. 이 단계는 확인만 합니다.
        - 위 형식 이후에 추가 텍스트를 붙이지 마세요.
        """

        var currentSummary = ""

        // 무한 루프: 사용자가 승인할 때까지 반복
        while true {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            // 1) DOUGLAS가 이해한 내용 요약 생성 (이미지 포함)
            let clarifyMessages: [ConversationMessage]
            if currentSummary.isEmpty {
                let userContent = "\(contextString)\n\n위 요청을 분석하고, 이해한 내용을 정리해주세요. 작업: \(task)"
                clarifyMessages = [ConversationMessage.user(userContent, attachments: imageAttachments.isEmpty ? nil : imageAttachments)]
            } else {
                // 사용자 피드백 반영 재요약
                let history = buildRoomHistory(roomID: roomID)
                    .map { "\($0.role): \($0.content ?? "")" }
                    .suffix(5)
                    .joined(separator: "\n")
                let feedbackContent = "이전 요약:\n\(currentSummary)\n\n사용자 피드백:\n\(history)\n\n피드백을 반영하여 다시 요약하세요."
                clarifyMessages = [ConversationMessage.user(feedbackContent, attachments: imageAttachments.isEmpty ? nil : imageAttachments)]
            }

            do {
                let responseContent = try await provider.sendMessageWithTools(
                    model: agent.modelName,
                    systemPrompt: clarifySystemPrompt,
                    messages: clarifyMessages,
                    tools: []
                )
                let response: String
                switch responseContent {
                case .text(let t): response = t
                case .mixed(let t, _): response = t
                case .toolCalls: response = "(요약 생성 실패)"
                }
                currentSummary = response

                let summaryMsg = ChatMessage(role: .assistant, content: response, agentName: agent.name)
                appendMessage(summaryMsg, to: roomID)
            } catch {
                let errorMsg = ChatMessage(
                    role: .assistant,
                    content: "요건 확인 오류: \(error.userFacingMessage)",
                    agentName: agent.name,
                    messageType: .error
                )
                appendMessage(errorMsg, to: roomID)
                return
            }

            // 2) 사용자에게 컨펌 요청 (복명복창 요약 자체가 확인 요청)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.awaitingApproval)
            }
            syncAgentStatuses()
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
                break
            }

            // 3) 거부됨 → ApprovalCard에서 이미 피드백 입력된 경우 스킵
            let hasInlineFeedback: Bool = {
                guard let room = rooms.first(where: { $0.id == roomID }) else { return false }
                // "수정 요청" 직전 메시지가 사용자 메시지이면 인라인 피드백 있음
                guard let rejectIdx = room.messages.lastIndex(where: { $0.content == "수정 요청" && $0.role == .system }) else { return false }
                let prevIdx = rejectIdx - 1
                guard prevIdx >= 0 else { return false }
                return room.messages[prevIdx].role == .user
            }()

            if !hasInlineFeedback {
                let askMsg = ChatMessage(
                    role: .system,
                    content: "어떤 부분을 수정해야 하나요?",
                    messageType: .userQuestion
                )
                appendMessage(askMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.awaitingUserInput)
                }
                scheduleSave()

                let _ = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                    userInputContinuations[roomID] = continuation
                }
            }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            // 피드백 반영하여 재요약 (루프 계속)
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

        // clarify 피드백을 포함한 확장 task (directMatches + LLM에 사용)
        let userMessages = rooms[idx].messages
            .filter { $0.role == .user }
            .map { $0.content }
        let enrichedTask = ([task] + userMessages).joined(separator: " ")

        // 1) 마스터에게 역할 요구사항 산출 요청
        var contextParts: [String] = []
        if let intakeData = rooms[idx].intakeData {
            contextParts.append(intakeData.asContextString())
        }
        if let assumptions = rooms[idx].assumptions, !assumptions.isEmpty {
            contextParts.append("[가정]\n" + assumptions.map { "- \($0.text)" }.joined(separator: "\n"))
        }
        if let workLog = rooms[idx].workLog {
            contextParts.append(workLog.asContextString())
        }

        let intentName = rooms[idx].intent?.displayName ?? "구현"
        // 기존 에이전트 목록 구성
        let subAgents = agentStore?.subAgents ?? []
        let agentRoster = subAgents.isEmpty ? "(없음)" : subAgents.map { "- \($0.name)" }.joined(separator: "\n")

        let intent = rooms[idx].intent
        let maxAgentHint: String
        switch intent {
        case .quickAnswer:
            maxAgentHint = "이 작업은 즉답(quickAnswer)이므로 **반드시 1명만** 요청하세요. 가장 적합한 전문가 1명만 선택하세요."
        case .research, .documentation:
            maxAgentHint = "이 작업은 **최대 2명**이면 충분합니다."
        default:
            maxAgentHint = "불확실하면 적게 요청하세요 (1~2명이면 충분한 경우가 많습니다)."
        }

        let assembleSystemPrompt = """
        \(agent.resolvedSystemPrompt)

        당신은 Assemble(팀 구성) 단계를 수행하고 있습니다.
        작업 유형은 **\(intentName)**입니다.

        작업에 **직접적으로** 필요한 역할만 최소한으로 요청하세요.
        작업과 무관한 역할은 절대 포함하지 마세요.
        \(maxAgentHint)

        사용자의 요청을 정확히 읽고, 요청된 관점의 전문가만 초대하세요.
        예: "프론트엔드 관점에서" → 프론트엔드 전문가만. 백엔드 전문가는 불필요.

        현재 사용 가능한 에이전트:
        \(agentRoster)

        반드시 아래 형식으로 산출물을 생성하세요:

        ```artifact:role_requirements title="역할 요구사항"
        - [필수] 역할이름: 이 역할이 필요한 이유
        - [선택] 역할이름: 이 역할이 필요한 이유
        ```

        주의:
        - 기존 에이전트가 있으면 반드시 위 목록의 **정확한 이름**을 사용하세요
        - 목록에 적합한 에이전트가 없을 때만 새 이름을 사용하세요
        """

        // 사전 매칭: 사용자 요청에서 기존 에이전트 이름 키워드 직접 탐색
        // "QA에게 자문" → "QA 전문가" 직접 매칭 (LLM 우회)
        // "프론트" → "프론트엔드 개발자" 접두어 매칭도 지원
        let taskLowered = enrichedTask.lowercased()
        let taskWords = taskLowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        let directMatches = subAgents.filter { sub in
            let nameKeywords = sub.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 && !AgentMatcher.isGenericSuffix($0) }
            return nameKeywords.contains(where: { keyword in
                // 정확 매칭: task에 키워드 포함 (ex: "백엔드" in task)
                taskLowered.contains(keyword) ||
                // 접두어 매칭: task 단어가 키워드의 접두어 (ex: "프론트" → "프론트엔드")
                taskWords.contains(where: { word in keyword.hasPrefix(word) && word.count >= 2 })
            })
        }

        if !directMatches.isEmpty {
            // directMatches: 사용자가 이름을 직접 언급한 에이전트 → 제한 없이 전부 초대
            var invitedNames: [String] = []
            for sub in directMatches {
                if let room = rooms.first(where: { $0.id == roomID }),
                   !room.assignedAgentIDs.contains(sub.id) {
                    addAgent(sub.id, to: roomID, silent: true)
                    invitedNames.append(sub.name)
                }
            }
            if !invitedNames.isEmpty {
                let joinMsg = ChatMessage(
                    role: .system,
                    content: "\(invitedNames.joined(separator: ", "))이(가) 방에 참여했습니다."
                )
                appendMessage(joinMsg, to: roomID)
            }
            scheduleSave()
            return
        }

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

            if requirements.isEmpty {
                // 기존 전문가가 있으면 그대로 진행
                let existingSpecialists = executingAgentIDs(in: roomID)
                if !existingSpecialists.isEmpty {
                    return
                }

                // 전문가 없음 → 생성 제안 (후속 질문 대응을 위해 모든 intent 공통)
                let suggestion = RoomAgentSuggestion(
                    name: "\(intentName) 전문가",
                    persona: "'\(intentName)' 작업을 수행하는 전문가입니다. 작업: \(task)",
                    reason: "작업 수행에 전문가가 필요합니다.",
                    suggestedBy: agent.name
                )
                addAgentSuggestion(suggestion, to: roomID)
                await waitForSuggestionResponse(roomID: roomID)
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
            let hadUnmatched = matched.contains(where: { $0.status == .unmatched })
            if hadUnmatched {
                await waitForSuggestionResponse(roomID: roomID)
            }

            // 5) 커버리지 게이트 (생성 제안이 처리된 경우 스킵 — 사용자가 이미 결정함)
            if !hadUnmatched, !AgentMatcher.checkMinimumCoverage(matched) {
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
                content: "Assemble 단계 오류: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }
        scheduleSave()
    }


    /// Plan 단계: Intent의 planMode에 따라 분기
    private func executePlanPhase(roomID: UUID, task: String, intent: WorkflowIntent) async {
        switch intent.planMode {
        case .skip:
            // quickAnswer: Plan 스킵
            break
        case .lite:
            await executePlanLite(roomID: roomID, task: task, intent: intent)
        case .exec:
            await executePlanExec(roomID: roomID, task: task, intent: intent)
        }
    }

    /// Plan-lite: 토론(필요 시) → 산출물 정리 (RoomPlan 생성 안 함)
    private func executePlanLite(roomID: UUID, task: String, intent: WorkflowIntent) async {
        let specialistCount = executingAgentIDs(in: roomID).count

        if specialistCount >= 2 && intent.requiresDiscussion {
            // 전문가 2명 이상: 토론 → 브리핑
            let startMsg = ChatMessage(
                role: .system,
                content: "토론을 시작합니다. 참여자: \(specialistCount)명 | 합의 시 자동 종료"
            )
            appendMessage(startMsg, to: roomID)

            await executeDiscussion(roomID: roomID, topic: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            await generateBriefing(roomID: roomID, topic: task)
            guard !Task.isCancelled else { return }
        } else if specialistCount == 1 {
            // 전문가 1명: 혼자 분석
            await executeSoloAnalysis(roomID: roomID, task: task)
            guard !Task.isCancelled else { return }
        }
        scheduleSave()
    }

    /// Plan-exec: 토론(필요 시) → 브리핑 → 계획 수립 → 승인(필요 시)
    private func executePlanExec(roomID: UUID, task: String, intent: WorkflowIntent) async {
        let specialistCount = executingAgentIDs(in: roomID).count

        if specialistCount >= 2 && intent.requiresDiscussion {
            // 전문가 2명 이상: 토론 → 브리핑
            let startMsg = ChatMessage(
                role: .system,
                content: "토론을 시작합니다. 참여자: \(specialistCount)명 | 합의 시 자동 종료"
            )
            appendMessage(startMsg, to: roomID)

            await executeDiscussion(roomID: roomID, topic: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            await generateBriefing(roomID: roomID, topic: task)
            guard !Task.isCancelled else { return }
        } else if specialistCount == 1 {
            // 전문가 1명: 혼자 분석
            await executeSoloAnalysis(roomID: roomID, task: task)
            guard !Task.isCancelled else { return }
        }

        // 계획 수립 (PlanCard UI로 표시되므로 별도 메시지 불필요)
        var currentPlan = await requestPlan(roomID: roomID, task: task)
        guard !Task.isCancelled else { return }

        if let plan = currentPlan {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = plan
            }
        }

        // 승인 (필요한 Intent만) — 거부 시 피드백 → 재계획 루프
        if intent.requiresApproval, currentPlan != nil {
            let maxAttempts = 3
            var attempts = 0

            while true {
                guard !Task.isCancelled,
                      let idx = rooms.firstIndex(where: { $0.id == roomID }),
                      rooms[idx].isActive else { return }

                rooms[idx].transitionTo(.awaitingApproval)
                syncAgentStatuses()

                let plan = currentPlan!
                let stepsDesc = plan.steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
                let approvalMsg = ChatMessage(
                    role: .system,
                    content: "실행 계획:\n\n\(stepsDesc)\n\n이 순서대로 진행하시겠습니까?",
                    messageType: .approvalRequest
                )
                appendMessage(approvalMsg, to: roomID)
                scheduleSave()

                let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = continuation
                }
                approvalContinuations.removeValue(forKey: roomID)
                guard !Task.isCancelled else { return }

                if approved {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.planning)
                    }
                    break
                }

                // 거부됨 — 피드백 추출 + 재계획
                attempts += 1
                if attempts >= maxAttempts {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.failed)
                        rooms[i].completedAt = Date()
                    }
                    let failMsg = ChatMessage(role: .system, content: "계획 수정 한도(\(maxAttempts)회)를 초과했습니다.")
                    appendMessage(failMsg, to: roomID)
                    syncAgentStatuses()
                    scheduleSave()
                    return
                }

                // 마지막 사용자 메시지에서 피드백 추출
                let feedback = rooms.first(where: { $0.id == roomID })?
                    .messages.last(where: { $0.role == .user })?.content

                let replanMsg = ChatMessage(
                    role: .system,
                    content: "피드백을 반영하여 계획을 수정합니다..."
                )
                appendMessage(replanMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                }

                let newPlan = await requestPlan(roomID: roomID, task: task, previousPlan: currentPlan, feedback: feedback)
                guard !Task.isCancelled else { return }

                if let plan = newPlan {
                    currentPlan = plan
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].plan = plan
                    }
                } else {
                    // 재계획 실패
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.failed)
                        rooms[i].completedAt = Date()
                    }
                    syncAgentStatuses()
                    scheduleSave()
                    return
                }
            }
        }
        scheduleSave()
    }

    /// Execute 단계: Intent에 따라 즉답 vs 표준 실행 분기
    private func executeExecutePhase(roomID: UUID, task: String, intent: WorkflowIntent) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        if intent == .quickAnswer {
            // quickAnswer: 전문가 1명이 바로 답변
            await executeQuickAnswer(roomID: roomID, task: task)
        } else {
            // 표준 실행: 계획 기반 단계별 실행
            if rooms[idx].plan == nil {
                rooms[idx].plan = RoomPlan(summary: task, estimatedSeconds: 300, steps: [RoomStep(text: task)])
            }

            rooms[idx].timerDurationSeconds = rooms[idx].plan?.estimatedSeconds ?? 300
            rooms[idx].timerStartedAt = Date()
            rooms[idx].transitionTo(.inProgress)
            scheduleSave()

            await executeRoomWork(roomID: roomID, task: task)
        }
    }

    /// quickAnswer 실행: 최적 전문가 1명이 도구 포함 즉답 (전문가 없으면 마스터 폴백)
    private func executeQuickAnswer(roomID: UUID, task: String) async {
        let specialistIDs = executingAgentIDs(in: roomID)
        let room = rooms.first(where: { $0.id == roomID })

        // 경량 라우팅: 전문가 2명+ → 마스터가 최적 1명 지명
        let candidateID: UUID?
        if specialistIDs.count >= 2 {
            candidateID = await routeQuickAnswer(roomID: roomID, task: task, specialistIDs: specialistIDs)
                ?? specialistIDs.first
        } else {
            candidateID = specialistIDs.first ?? room?.assignedAgentIDs.first
        }

        guard let agentID = candidateID,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].transitionTo(.inProgress)
        }
        speakingAgentIDByRoom[roomID] = agentID

        let context = makeToolContext(roomID: roomID, currentAgentID: agentID)
        var history: [ConversationMessage] = []
        if let workLog = rooms.first(where: { $0.id == roomID })?.workLog {
            history.append(ConversationMessage.user("[이전 작업 컨텍스트]\n\(workLog.asContextString())"))
        }
        history.append(contentsOf: buildRoomHistory(roomID: roomID))

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
                content: "오류: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
    }

    /// 경량 라우팅: 마스터가 즉답에 최적인 전문가 1명을 지명
    /// LLM 1회 호출로 에이전트 이름만 반환받음. 실패 시 nil (호출측에서 첫 번째 폴백)
    private func routeQuickAnswer(roomID: UUID, task: String, specialistIDs: [UUID]) async -> UUID? {
        // 마스터 에이전트 + 프로바이더 확보
        guard let masterID = rooms.first(where: { $0.id == roomID })?.assignedAgentIDs.first,
              let master = agentStore?.agents.first(where: { $0.id == masterID }),
              let provider = providerManager?.provider(named: master.providerName) else { return nil }

        let roster = specialistIDs.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })
        }.map { "- \($0.name): \($0.persona.prefix(60))" }.joined(separator: "\n")

        let prompt = """
        아래 전문가 중 이 질문에 가장 적합한 1명의 **이름만** 출력하세요. 다른 내용은 절대 출력하지 마세요.

        전문가:
        \(roster)

        질문: \(task)
        """

        do {
            let response = try await provider.sendMessage(
                model: master.modelName,
                systemPrompt: "당신은 질문 라우터입니다. 전문가 이름만 한 줄로 출력하세요.",
                messages: [("user", prompt)]
            )
            let name = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "- ", with: "")
            return specialistIDs.first { id in
                agentStore?.agents.first(where: { $0.id == id })?.name == name
            }
        } catch {
            return nil
        }
    }

    /// 전문가 1명 Solo 분석: 토론 없이 혼자 분석하여 결과 공유 (전문가 없으면 마스터 폴백)
    private func executeSoloAnalysis(roomID: UUID, task: String) async {
        let specialistIDs = executingAgentIDs(in: roomID)
        let room = rooms.first(where: { $0.id == roomID })
        let candidateID = specialistIDs.first ?? room?.assignedAgentIDs.first
        guard let agentID = candidateID,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        speakingAgentIDByRoom[roomID] = agentID

        let soloPrompt = """
        \(agent.resolvedSystemPrompt)

        현재 작업방에서 아래 작업에 대해 혼자 분석합니다.
        핵심 사항, 접근 방향, 주의점을 정리해주세요.
        """

        let history = buildRoomHistory(roomID: roomID)
        let context = makeToolContext(roomID: roomID, currentAgentID: agentID)

        do {
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: soloPrompt,
                conversationMessages: history,
                context: context
            )
            let reply = ChatMessage(role: .assistant, content: response, agentName: agent.name)
            appendMessage(reply, to: roomID)
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "분석 오류: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
    }

    /// Review 단계: 방 완료 후 작업일지 비동기 생성 (TypingIndicator 노출 방지)
    private func executeReviewPhase(roomID: UUID, task: String) async {
        // 먼저 방 완료 처리 → TypingIndicator 숨김
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed {
            rooms[i].currentPhase = nil
            rooms[i].status = .completed
            rooms[i].completedAt = Date()
            pluginEventDelegate?(.roomCompleted(roomID: roomID, title: rooms[i].title))
        }
        syncAgentStatuses()
        scheduleSave()

        // 완료 후 작업일지 비동기 생성 (UI에 "발언 중" 안 뜸)
        await generateWorkLog(roomID: roomID, task: task)

        // 플레이북 override 감지
        guard let room = rooms.first(where: { $0.id == roomID }),
              let playbook = room.playbook,
              room.primaryProjectPath != nil else { return }

        let workSummary = room.workLog?.outcome ?? ""
        var overrides: [String] = []

        if let branchPattern = playbook.branchPattern, !branchPattern.isEmpty,
           (workSummary.contains("branch") || workSummary.contains("브랜치")) {
            overrides.append("브랜치 패턴 변경 감지 (설정: \(branchPattern))")
        }

        if !overrides.isEmpty {
            let overrideMsg = ChatMessage(
                role: .system,
                content: "플레이북과 다른 패턴이 감지되었습니다:\n" + overrides.map { "- \($0)" }.joined(separator: "\n") + "\n\n플레이북을 업데이트하시겠습니까?"
            )
            appendMessage(overrideMsg, to: roomID)
        }
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
    private func requestPlan(roomID: UUID, task: String, previousPlan: RoomPlan? = nil, feedback: String? = nil) async -> RoomPlan? {
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
        - 마스터(진행자/오케스트레이터)는 실행 대상이 아닙니다. 마스터에게 step을 배정하지 마세요.
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

        // 재계획 컨텍스트 (이전 계획이 거부된 경우)
        var replanContext = ""
        if let prev = previousPlan {
            let prevSteps = prev.steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
            replanContext = "\n\n[이전 계획 — 사용자가 거부함]\n\(prev.summary)\n단계:\n\(prevSteps)"
            if let fb = feedback, !fb.isEmpty {
                replanContext += "\n\n[사용자 피드백]\n\(fb)\n\n위 피드백을 반영하여 계획을 다시 수립하세요."
            } else {
                replanContext += "\n\n사용자가 이전 계획을 거부했습니다. 다른 접근 방식으로 계획을 다시 수립하세요."
            }
        }

        let planMessages: [(role: String, content: String)] = [
            ("user", "브리핑:\n\(briefingContext)\(artifactContext)\(playbookContext)\(attachmentContext)\(replanContext)\n\n실행 계획을 JSON으로 작성해주세요. 작업: \(task)")
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
                content: "계획 수립 실패: \(error.userFacingMessage)",
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
        // 뒤에서부터 검색하여 중첩 코드블록(```json 안의 ```) 잘림 방지
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", options: .backwards, range: startRange.upperBound..<text.endIndex),
           endRange.lowerBound > startRange.upperBound {
            return String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startRange = text.range(of: "```\n"),
           let endRange = text.range(of: "\n```", options: .backwards, range: startRange.upperBound..<text.endIndex),
           endRange.lowerBound > startRange.upperBound {
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
                syncAgentStatuses()
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

            // 에이전트 실행 — 실패 시 1회 재시도, 전원 실패만 워크플로우 중단
            var failedAgentIDs: [UUID] = []
            await withTaskGroup(of: (UUID, Bool).self) { group in
                for agentID in targetAgentIDs {
                    group.addTask { [self] in
                        let success = await self.executeStep(
                            step: step.text,
                            fullTask: task,
                            agentID: agentID,
                            roomID: roomID,
                            stepIndex: stepIndex,
                            totalSteps: plan.steps.count,
                            fileWriteTracker: tracker,
                            progressGroupID: progressMsg.id
                        )
                        return (agentID, success)
                    }
                }
                for await (agentID, success) in group {
                    if !success { failedAgentIDs.append(agentID) }
                }
            }

            // 실패한 에이전트 1회 재시도
            if !failedAgentIDs.isEmpty {
                var stillFailed: [UUID] = []
                for agentID in failedAgentIDs {
                    let retryMsg = ChatMessage(
                        role: .system,
                        content: "에이전트 재시도 중...",
                        agentName: agentStore?.agents.first(where: { $0.id == agentID })?.name,
                        messageType: .progress
                    )
                    appendMessage(retryMsg, to: roomID)
                    let success = await executeStep(
                        step: step.text,
                        fullTask: task,
                        agentID: agentID,
                        roomID: roomID,
                        stepIndex: stepIndex,
                        totalSteps: plan.steps.count,
                        fileWriteTracker: tracker,
                        progressGroupID: progressMsg.id
                    )
                    if !success { stillFailed.append(agentID) }
                }
                failedAgentIDs = stillFailed
            }

            let succeededCount = targetAgentIDs.count - failedAgentIDs.count

            // 전원 실패 → 워크플로우 중단 (에이전트가 있었는데 전부 실패한 경우만)
            if succeededCount == 0 && !targetAgentIDs.isEmpty {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                let failMsg = ChatMessage(
                    role: .system,
                    content: "단계 \(stepIndex + 1): 모든 에이전트 실패로 워크플로우를 중단합니다.",
                    messageType: .error
                )
                appendMessage(failMsg, to: roomID)
                syncAgentStatuses()
                scheduleSave()
                return
            }

            // 일부 실패 → 경고 후 계속 진행
            if !failedAgentIDs.isEmpty {
                let failedNames = failedAgentIDs.compactMap { id in
                    agentStore?.agents.first(where: { $0.id == id })?.name
                }.joined(separator: ", ")
                let warnMsg = ChatMessage(
                    role: .system,
                    content: "⚠️ 단계 \(stepIndex + 1): \(failedNames) 실패 (재시도 포함). 나머지 에이전트로 계속 진행합니다.",
                    messageType: .error
                )
                appendMessage(warnMsg, to: roomID)
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
            // 에이전트 수 스냅샷 (다음 후속 사이클에서 변동 감지용)
            previousCycleAgentCount[roomID] = executingAgentIDs(in: roomID).count
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
                toolCalls: nil, toolCallID: nil, attachments: firstUserMsg.attachments,
                isError: false
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
                content: "단계 실행 오류: \(error.userFacingMessage)",
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

    /// 합의 기반 토론 실행 (합의 도달 시 자동 종료, 최대 3라운드)
    private func executeDiscussion(roomID: UUID, topic: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let maxSafetyRounds = 3

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

            var earlyConsensus = false
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

                // 진행자가 합의 선언 + 2라운드 이상 → 나머지 발언 스킵 (반복 방지)
                let isMaster = agentStore?.agents.first(where: { $0.id == agentID })?.isMaster ?? false
                if isMaster && agreed && round >= 1 {
                    earlyConsensus = true
                    break
                }
            }

            // 전원 합의 또는 진행자 조기 종료 → 토론 종료
            if earlyConsensus || (agreedCount == agentIDs.count && agentIDs.count > 0) {
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
            ConversationMessage(role: msg.role, content: msg.content, toolCalls: nil, toolCallID: nil, attachments: nil, isError: false)
        })

        // 동료 목록: 이름(역할) 형태로 구성, 진행자와 전문가 구분
        let otherAgents = roomRef?.assignedAgentIDs
            .compactMap { id in agentStore?.agents.first(where: { $0.id == id }) }
            .filter { $0.id != agentID } ?? []
        let masterAgent = otherAgents.first(where: { $0.isMaster })
        let specialists = otherAgents.filter { !$0.isMaster }
        let specialistDesc = specialists.map { $0.name }.joined(separator: ", ")
        let otherNames = otherAgents.map { $0.name }.joined(separator: ", ")

        // 마스터(오케스트레이터) 여부 판별
        let isMasterAgent = agent.isMaster

        let discussionPrompt: String
        if isMasterAgent {
            // 마스터: 요구사항 전달만, 직접 작업 금지
            discussionPrompt = """
            당신은 \(agent.name)입니다. 이 토론의 진행자 역할을 합니다:
            - 전문가에게 사용자의 요구사항을 간결하게 전달
            - 전문가의 질문에 답변
            - 작업 방향이 맞는지 확인하고, 전문가의 업무를 대신 수행하지 않습니다

            [절대 금지] 다른 에이전트(\(specialistDesc)) 역할로 발언하거나, 그들의 발언을 대신 작성
            [절대 금지] **[백엔드 개발자]** 등 다른 이름으로 발언 — 반드시 \(agent.name)으로만 발언
            [절대 금지] 번역, 코딩, 문서 작성 등 실제 작업 수행

            [회의실] \(topic)
            라운드 \(round + 1) | 전문가: \(specialistDesc)

            \(agent.name)으로서 2문장 이내로 발언하세요. 전문가들은 별도로 자기 차례에 발언합니다.
            이름 헤더(**[이름]** 등)를 붙이지 마세요. UI가 화자를 표시합니다.
            발언 마지막 줄에 [합의] 또는 [계속] 태그를 붙이세요.
            """
        } else {
            // 전문가: 자기 역할에 맞는 작업
            let masterNote = masterAgent != nil ? "\(masterAgent!.name)은 진행자입니다. 전문적인 질문은 다른 전문가에게 직접 하세요." : ""
            discussionPrompt = """
            \(agent.resolvedSystemPrompt)

            [회의실] \(topic)
            라운드 \(round + 1) | 동료: \(otherNames)
            \(masterNote)

            첨부된 이미지나 파일이 있으면 내용을 확인하고 참고하세요.
            2-4문장으로 핵심만 말하세요.
            이름 헤더(**[이름]** 등)를 붙이지 마세요. UI가 화자를 표시합니다.
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

            // 합의 감지 (퍼지 매칭 포함) 후 DecisionLog 기록
            let agreed = Self.detectConsensus(in: response)
            if agreed, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                let decision = Self.parseDecisionContent(from: response) ?? "합의 도달"
                let entry = DecisionEntry(
                    round: round,
                    decision: decision,
                    supporters: [agent.name]
                )
                rooms[i].decisionLog.append(entry)
            }
            let cleanResponse = response
                .replacingOccurrences(of: "\\[합의(?::[^\\]]*)?\\]", with: "", options: .regularExpression)
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
                content: "발언 실패: \(error.userFacingMessage)",
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
                content: "브리핑 생성 실패: \(error.userFacingMessage)",
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

    // MARK: - 유틸리티

    /// [합의: 내용] 태그에서 내용 추출
    /// 퍼지 합의 감지: [합의] 태그 우선, 없으면 한국어 합의 표현 탐지
    static func detectConsensus(in response: String) -> Bool {
        // 1) 명시적 태그 — 가장 신뢰도 높음
        if response.contains("[합의") { return true }

        // 2) 명시적 반대/계속 태그 — 확실한 비합의
        if response.contains("[계속]") { return false }

        // 3) 퍼지: 합의 표현 vs 반대 표현 비교
        let lower = response.lowercased()
        let agreePhrases = [
            "동의합니다", "합의합니다", "찬성합니다",
            "이의 없습니다", "이의없습니다",
            "좋은 계획", "좋은 방향", "좋은 접근",
            "이 방향으로 진행", "이대로 진행",
            "agree", "consensus", "lgtm",
        ]
        let disagreePhrases = [
            "반대합니다", "다른 의견", "다른 접근",
            "재고해", "재검토", "우려가 있", "우려됩니다",
            "수정이 필요", "보완이 필요", "disagree",
        ]

        let hasAgree = agreePhrases.contains { lower.contains($0) }
        let hasDisagree = disagreePhrases.contains { lower.contains($0) }

        // 합의 표현이 있고 반대 표현이 없으면 합의
        return hasAgree && !hasDisagree
    }

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
        if let cont = intentContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: .implementation)
        }
        pendingIntentSelection.removeValue(forKey: roomID)
        guard rooms[idx].transitionTo(.completed) else { return }
        rooms[idx].completedAt = Date()
        // 에이전트 수 스냅샷 (다음 후속 사이클에서 변동 감지용)
        previousCycleAgentCount[roomID] = executingAgentIDs(in: roomID).count

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
        if let cont = intentContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: .implementation)
        }
        pendingIntentSelection.removeValue(forKey: roomID)
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
        // 대기 중인 모든 continuation 해제 (누수 방지)
        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = userInputContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: "")
        }
        if let cont = suggestionContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = intentContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: .implementation)
        }
        pendingIntentSelection.removeValue(forKey: roomID)

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
                    attachments: msg.attachments,
                    isError: false
                )
            }
    }

    // MARK: - 영속화

    /// 테스트에서 임시 디렉토리로 교체 가능 (프로덕션에서는 nil)
    static var roomDirectoryOverride: URL?

    private static var roomDirectory: URL {
        if let override = roomDirectoryOverride {
            try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
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

    func saveRooms() {
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
        var failedFiles: [URL] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let room = try? JSONDecoder().decode(Room.self, from: data) {
                loaded.append(room)
            } else {
                failedFiles.append(file)
            }
        }
        // 디코드 실패한 고아 JSON 파일 삭제
        for file in failedFiles {
            try? FileManager.default.removeItem(at: file)
        }
        rooms = loaded.sorted { $0.createdAt > $1.createdAt }
        // 완료된 방 프루닝 — 최근 30개만 유지
        pruneCompletedRooms(maxKeep: 30)
        syncAgentStatuses()
    }

    /// 완료된 방이 maxKeep 개를 초과하면 오래된 순서대로 삭제
    private func pruneCompletedRooms(maxKeep: Int) {
        let completed = rooms
            .filter { !$0.isActive }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        guard completed.count > maxKeep else { return }
        let toRemove = completed.suffix(from: maxKeep)
        let dir = Self.roomDirectory
        for room in toRemove {
            // 첨부 이미지 파일 삭제
            for msg in room.messages {
                msg.attachments?.forEach { $0.delete() }
            }
            // JSON 파일 삭제
            let file = dir.appendingPathComponent("\(room.id.uuidString).json")
            try? FileManager.default.removeItem(at: file)
        }
        let removeIDs = Set(toRemove.map { $0.id })
        rooms.removeAll { removeIDs.contains($0.id) }
    }
}
