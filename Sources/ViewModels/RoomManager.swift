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
    func createRoom(title: String, agentIDs: [UUID], createdBy: RoomCreator, mode: RoomMode = .task, maxDiscussionRounds: Int = 3, projectPath: String? = nil, buildCommand: String? = nil, testCommand: String? = nil) -> Room {
        let room = Room(
            title: title,
            assignedAgentIDs: agentIDs,
            createdBy: createdBy,
            mode: mode,
            maxDiscussionRounds: maxDiscussionRounds,
            projectPath: projectPath,
            buildCommand: buildCommand,
            testCommand: testCommand
        )
        rooms.append(room)
        selectedRoomID = room.id
        syncAgentStatuses()
        scheduleSave()
        return room
    }

    /// 사용자 수동 방 생성 + 바로 작업 시작
    func createManualRoom(title: String, agentIDs: [UUID], task: String, projectPath: String? = nil, buildCommand: String? = nil, testCommand: String? = nil) {
        let room = createRoom(title: title, agentIDs: agentIDs, createdBy: .user, projectPath: projectPath, buildCommand: buildCommand, testCommand: testCommand)

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
        cont.resume(returning: false)
    }

    /// 사용자가 방에 메시지 보내기
    func sendUserMessage(_ text: String, to roomID: UUID, attachments: [ImageAttachment]? = nil) async {
        let userMsg = ChatMessage(role: .user, content: text, attachments: attachments)
        appendMessage(userMsg, to: roomID)

        guard let room = rooms.first(where: { $0.id == roomID }) else { return }

        // 방의 에이전트들에게 추가 지시
        let context = makeToolContext(roomID: roomID)
        for agentID in room.assignedAgentIDs {
            guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
                  let provider = providerManager?.provider(named: agent.providerName) else { continue }

            let history = buildRoomHistory(roomID: roomID)
            do {
                let response = try await ToolExecutor.smartSend(
                    provider: provider,
                    agent: agent,
                    systemPrompt: agent.persona,
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
        }
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
            projectPath: room?.projectPath,
            currentAgentID: currentAgentID,
            currentAgentName: currentAgentName,
            fileWriteTracker: fileWriteTracker
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
        let preset = resolvePreset(suggestion.recommendedPreset)
        let providerName = suggestion.recommendedProvider ?? "Anthropic"
        let modelName = suggestion.recommendedModel ?? "claude-sonnet-4-20250514"

        let newAgent = Agent(
            name: suggestion.name,
            persona: suggestion.persona,
            providerName: providerName,
            modelName: modelName,
            capabilityPreset: preset
        )
        agentStore?.addAgent(newAgent)
        addAgent(newAgent.id, to: roomID)

        let msg = ChatMessage(
            role: .system,
            content: "'\(suggestion.name)' 에이전트가 생성되어 방에 참여했습니다."
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
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
    }

    /// 프리셋 문자열 → CapabilityPreset 변환
    private func resolvePreset(_ str: String?) -> CapabilityPreset {
        guard let str else { return .developer }
        return CapabilityPreset(rawValue: str) ?? .developer
    }

    // MARK: - 방에 에이전트 추가

    func addAgent(_ agentID: UUID, to roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        guard !rooms[idx].assignedAgentIDs.contains(agentID) else { return }
        rooms[idx].assignedAgentIDs.append(agentID)
        syncAgentStatuses()
        scheduleSave()

        if let agentName = agentStore?.agents.first(where: { $0.id == agentID })?.name {
            let systemMsg = ChatMessage(role: .system, content: "\(agentName)이(가) 방에 참여했습니다.")
            appendMessage(systemMsg, to: roomID)
        }
    }

    // MARK: - 방 워크플로우 (계획 → 실행)

    /// 통합 워크플로우: 토론 → 계획 → 실행
    func startRoomWorkflow(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        rooms[idx].status = .planning
        syncAgentStatuses()

        let agentCount = rooms[idx].assignedAgentIDs.count

        // ── Phase 1: 토론 (2명 이상일 때만) ──
        if agentCount > 1 {
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
        }

        // ── Phase 2: 계획 수립 ──
        let planningMsg = ChatMessage(
            role: .system,
            content: agentCount > 1 ? "토론 결과를 바탕으로 계획을 수립하는 중..." : "계획을 수립하는 중..."
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

        // 계획 성공 → 타이머 시작
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

    /// 에이전트에게 계획 수립 요청
    private func requestPlan(roomID: UUID, task: String) async -> RoomPlan? {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
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

        let planSystemPrompt = """
        \(agent.persona)

        현재 작업방에 배정되었습니다. 팀원들과의 토론이 완료되었습니다.
        토론 내용을 바탕으로 반드시 아래 형식의 JSON으로 실행 계획을 제출하세요:

        {"plan": {"summary": "전체 계획 요약", "estimated_minutes": 5, "steps": ["1단계: ...", {"text": "위험한 단계", "requires_approval": true}, "3단계: ..."]}}

        규칙:
        - 토론에서 합의된 방향을 반영하세요
        - estimated_minutes는 현실적으로 추정하세요 (1~30분)
        - steps는 구체적이고 실행 가능한 단계로 나누세요
        - 배포, 데이터 삭제 등 위험한 단계는 {"text": "...", "requires_approval": true} 형식으로 표기하세요
        - 반드시 유효한 JSON으로만 응답하세요
        """

        let planMessages: [(role: String, content: String)] = [
            ("user", "브리핑:\n\(briefingContext)\(artifactContext)\n\n실행 계획을 JSON으로 작성해주세요. 작업: \(task)")
        ]

        do {
            let response = try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: planSystemPrompt,
                messages: planMessages
            )

            // 계획 메시지를 방에 추가
            let planMsg = ChatMessage(role: .assistant, content: response, agentName: agent.name)
            appendMessage(planMsg, to: roomID)

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

        // steps: plain String과 {"text":"...", "requires_approval": true} 혼합 지원
        var steps: [RoomStep] = []
        for raw in rawSteps {
            if let str = raw as? String {
                steps.append(RoomStep(text: str))
            } else if let dict = raw as? [String: Any], let text = dict["text"] as? String {
                let requiresApproval = dict["requires_approval"] as? Bool ?? false
                steps.append(RoomStep(text: text, requiresApproval: requiresApproval))
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

            let progressMsg = ChatMessage(
                role: .system,
                content: "[\(stepIndex + 1)/\(plan.steps.count)] \(step.text)"
            )
            appendMessage(progressMsg, to: roomID)

            // 병렬로 모든 에이전트 실행
            await withTaskGroup(of: Void.self) { group in
                for agentID in room.assignedAgentIDs {
                    group.addTask { [self] in
                        await self.executeStep(
                            step: step.text,
                            fullTask: task,
                            agentID: agentID,
                            roomID: roomID,
                            stepIndex: stepIndex,
                            totalSteps: plan.steps.count,
                            fileWriteTracker: tracker
                        )
                    }
                }
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

            // 빌드/QA 루프는 에이전트 주도로 실행 (계획 단계에서 에이전트가 직접 shell_exec으로 처리)
        }

        // 완료
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status == .inProgress {
            rooms[i].transitionTo(.completed)
            rooms[i].completedAt = Date()

            let doneMsg = ChatMessage(role: .system, content: "모든 작업이 완료되었습니다.")
            appendMessage(doneMsg, to: roomID)

            // 작업일지 자동 생성
            await generateWorkLog(roomID: roomID, task: task)
        }
        syncAgentStatuses()
        scheduleSave()
    }

    /// 개별 에이전트의 단계 실행
    private func executeStep(
        step: String,
        fullTask: String,
        agentID: UUID,
        roomID: UUID,
        stepIndex: Int,
        totalSteps: Int,
        fileWriteTracker: FileWriteTracker? = nil
    ) async {
        guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        let room = rooms.first(where: { $0.id == roomID })

        // 브리핑 기반 컨텍스트 (압축) + 최근 메시지만
        var history: [ConversationMessage] = []
        if let briefing = room?.briefing {
            history.append(ConversationMessage.user("작업 브리핑:\n\(briefing.asContextString())"))
        }
        history.append(contentsOf: buildRoomHistory(roomID: roomID, limit: 5))

        // 산출물 컨텍스트 구성
        let artifactContext: String
        if let room = room, !room.artifacts.isEmpty {
            artifactContext = "\n\n[참고 산출물]\n" + room.artifacts.map {
                "[\($0.type.displayName)] \($0.title) (v\($0.version)):\n\($0.content)"
            }.joined(separator: "\n---\n")
        } else {
            artifactContext = ""
        }

        let stepPrompt = """
        [작업 \(stepIndex + 1)/\(totalSteps)] \(step)
        \(artifactContext)

        이 단계의 결과만 간결하게 보고하세요. 과정 설명 불필요. 핵심 결과 + 다음 단계에 필요한 사항만.
        """

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)
            speakingAgentIDByRoom[roomID] = agentID

            let context = makeToolContext(roomID: roomID, currentAgentID: agentID, fileWriteTracker: fileWriteTracker)
            let messagesWithStep = history + [ConversationMessage.user(stepPrompt)]
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: agent.persona,
                conversationMessages: messagesWithStep,
                context: context
            )

            if speakingAgentIDByRoom[roomID] == agentID {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
            }

            let reply = ChatMessage(role: .assistant, content: response, agentName: agent.name)
            appendMessage(reply, to: roomID)
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

    /// QA 에이전트 우선 선택 (roleTemplateID == "qa_engineer" 에이전트 우선)
    private func qaAgentID(in room: Room) -> UUID? {
        for agentID in room.assignedAgentIDs {
            if let agent = agentStore?.agents.first(where: { $0.id == agentID }),
               agent.roleTemplateID == "qa_engineer" {
                return agentID
            }
        }
        return nil
    }

    // MARK: - 토론 실행

    /// 합의 기반 토론 실행 (합의 도달 시 자동 종료, 최대 10라운드)
    private func executeDiscussion(roomID: UUID, topic: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let maxSafetyRounds = 10

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

        let history = buildDiscussionHistory(roomID: roomID, currentAgentName: agent.name)

        let otherNames = rooms.first(where: { $0.id == roomID })?
            .assignedAgentIDs
            .compactMap { id in agentStore?.agents.first(where: { $0.id == id })?.name }
            .filter { $0 != agent.name }
            .joined(separator: ", ") ?? ""

        let discussionPrompt = """
        \(agent.persona)

        [회의실] \(topic)
        라운드 \(round + 1) | 동료: \(otherNames)

        당신은 팀 회의에 참석한 실무자입니다. 팀원으로서 자연스럽게 대화하세요.

        말투 규칙:
        - 실제 회의처럼 짧고 직접적으로 말할 것 (2-4문장)
        - "~라고 생각합니다", "~하면 어떨까요" 같은 자연스러운 구어체
        - AI 특유의 나열식/분석식 표현 절대 금지 (번호 매기기, "첫째/둘째", "다음과 같습니다" 등)
        - 동료 이름을 자연스럽게 언급하며 대화
        - 핵심만 말하고, 반복하지 말 것

        중요: 발언 마지막 줄에 반드시 다음 중 하나를 태그로 붙이세요:
        [합의] — 현재 방향에 동의하고, 실행으로 넘어가도 된다고 판단할 때
        [계속] — 추가 논의가 필요하다고 판단할 때

        태그는 반드시 발언 마지막 줄에 단독으로 적어주세요.

        산출물 작성: 구체적 합의 내용(API 스펙, 테스트 계획 등)이 있으면 발언에 포함하세요:
        ```artifact:<type> title="제목"
        내용
        ```
        type: api_spec, test_plan, task_breakdown, architecture_decision, generic
        산출물은 자동 보관되어 실행 단계에서 참조됩니다.
        """

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)
            speakingAgentIDByRoom[roomID] = agentID

            let response = try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: discussionPrompt,
                messages: history
            )

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

            let reply = ChatMessage(role: .assistant, content: displayResponse.isEmpty ? cleanResponse : displayResponse, agentName: agent.name)
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
            .filter { $0.messageType == .text || $0.messageType == .discussionRound }
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
        // 대기 중인 승인 continuation 해제
        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        guard rooms[idx].transitionTo(.completed) else { return }
        rooms[idx].completedAt = Date()
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
            case 1: newStatus = .working
            default: newStatus = .busy
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
