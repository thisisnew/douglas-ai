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
    func createRoom(title: String, agentIDs: [UUID], createdBy: RoomCreator, mode: RoomMode = .task, maxDiscussionRounds: Int = 3) -> Room {
        let room = Room(
            title: title,
            assignedAgentIDs: agentIDs,
            createdBy: createdBy,
            mode: mode,
            maxDiscussionRounds: maxDiscussionRounds
        )
        rooms.append(room)
        selectedRoomID = room.id
        syncAgentStatuses()
        scheduleSave()
        return room
    }

    /// 사용자 수동 방 생성 + 바로 작업 시작
    func createManualRoom(title: String, agentIDs: [UUID], task: String) {
        let room = createRoom(title: title, agentIDs: agentIDs, createdBy: .user)

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

    /// 사용자가 방에 메시지 보내기
    func sendUserMessage(_ text: String, to roomID: UUID) async {
        let userMsg = ChatMessage(role: .user, content: text)
        appendMessage(userMsg, to: roomID)

        guard let room = rooms.first(where: { $0.id == roomID }) else { return }

        // 방의 에이전트들에게 추가 지시
        for agentID in room.assignedAgentIDs {
            guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
                  let provider = providerManager?.provider(named: agent.providerName) else { continue }

            let history = buildRoomHistory(roomID: roomID)
            do {
                let response = try await ToolExecutor.smartSend(
                    provider: provider,
                    agent: agent,
                    systemPrompt: agent.persona,
                    messages: history
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

        // ── Phase 1: 토론 ──
        rooms[idx].status = .planning
        syncAgentStatuses()

        let agentCount = max(1, rooms[idx].assignedAgentIDs.count)

        let startMsg = ChatMessage(
            role: .system,
            content: "토론을 시작합니다. 참여자: \(agentCount)명 | 합의 시 자동 종료"
        )
        appendMessage(startMsg, to: roomID)

        await executeDiscussion(roomID: roomID, topic: task)
        guard !Task.isCancelled,
              rooms.first(where: { $0.id == roomID })?.status == .planning else { return }

        // 토론 요약 생성
        await generateDiscussionSummary(roomID: roomID, topic: task)
        guard !Task.isCancelled else { return }

        // ── Phase 2: 계획 수립 ──
        let planningMsg = ChatMessage(role: .system, content: "토론 결과를 바탕으로 계획을 수립하는 중...")
        appendMessage(planningMsg, to: roomID)

        let planResult = await requestPlan(roomID: roomID, task: task)
        guard !Task.isCancelled else { return }

        guard let plan = planResult else {
            // 계획 실패 → 직접 실행 (기본 5분)
            let fallbackMsg = ChatMessage(role: .system, content: "계획 수립을 건너뛰고 바로 실행합니다.")
            appendMessage(fallbackMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = RoomPlan(summary: task, estimatedSeconds: 300, steps: [task])
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

        let planSystemPrompt = """
        \(agent.persona)

        현재 작업방에 배정되었습니다. 팀원들과의 토론이 완료되었습니다.
        토론 내용을 바탕으로 반드시 아래 형식의 JSON으로 실행 계획을 제출하세요:

        {"plan": {"summary": "전체 계획 요약", "estimated_minutes": 5, "steps": ["1단계: ...", "2단계: ..."]}}

        규칙:
        - 토론에서 합의된 방향을 반영하세요
        - estimated_minutes는 현실적으로 추정하세요 (1~30분)
        - steps는 구체적이고 실행 가능한 단계로 나누세요
        - 반드시 유효한 JSON으로만 응답하세요
        """

        // 토론 히스토리를 포함하여 계획 수립
        let history = buildDiscussionHistory(roomID: roomID, currentAgentName: agent.name)
        let planMessages = history + [("user", "위 토론을 바탕으로 실행 계획을 JSON으로 작성해주세요. 작업: \(task)")]

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
              let steps = planDict["steps"] as? [String] else {
            return nil
        }
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

        for (stepIndex, step) in plan.steps.enumerated() {
            // 취소 또는 방 삭제 감지
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { break }

            // 현재 단계 업데이트
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].setCurrentStep(stepIndex)
            }

            let progressMsg = ChatMessage(
                role: .system,
                content: "[\(stepIndex + 1)/\(plan.steps.count)] \(step)"
            )
            appendMessage(progressMsg, to: roomID)

            // 병렬로 모든 에이전트 실행
            await withTaskGroup(of: Void.self) { group in
                for agentID in room.assignedAgentIDs {
                    group.addTask { [self] in
                        await self.executeStep(
                            step: step,
                            fullTask: task,
                            agentID: agentID,
                            roomID: roomID,
                            stepIndex: stepIndex,
                            totalSteps: plan.steps.count
                        )
                    }
                }
            }
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
        totalSteps: Int
    ) async {
        guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        let history = buildRoomHistory(roomID: roomID)

        let stepPrompt = """
        [작업 \(stepIndex + 1)/\(totalSteps)] \(step)

        이 단계의 결과만 간결하게 보고하세요. 과정 설명 불필요. 핵심 결과 + 다음 단계에 필요한 사항만.
        """

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)
            speakingAgentIDByRoom[roomID] = agentID

            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: agent.persona,
                messages: history + [("user", stepPrompt)]
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

            let reply = ChatMessage(role: .assistant, content: cleanResponse, agentName: agent.name)
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

    /// 토론 요약 생성
    private func generateDiscussionSummary(roomID: UUID, topic: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        let summaryMsg = ChatMessage(role: .system, content: "토론 내용을 정리하는 중...")
        appendMessage(summaryMsg, to: roomID)

        let history = buildDiscussionHistory(roomID: roomID, currentAgentName: nil)

        let summaryPrompt = """
        회의록을 작성하세요. 형식:

        **결론**: 팀이 합의한 방향 (1-2문장)
        **핵심 의견**: 주요 발언 요약 (각 1줄)
        **미결 사항**: 추가 논의 필요한 부분 (있으면)

        3-5줄 이내로 간결하게.
        """

        do {
            let response = try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: summaryPrompt,
                messages: history
            )

            let reply = ChatMessage(role: .assistant, content: response, agentName: "토론 정리", messageType: .summary)
            appendMessage(reply, to: roomID)
        } catch {
            let errorMsg = ChatMessage(
                role: .system,
                content: "요약 생성 실패: \(error.localizedDescription)",
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }
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
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        rooms[idx].transitionTo(.completed)
        rooms[idx].completedAt = Date()
        syncAgentStatuses()
        scheduleSave()
    }

    func deleteRoom(_ roomID: UUID) {
        // 진행 중인 워크플로우 취소
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        speakingAgentIDByRoom.removeValue(forKey: roomID)

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

    private func buildRoomHistory(roomID: UUID) -> [(role: String, content: String)] {
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

    // MARK: - 영속화

    private static var roomDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgentManager/rooms", isDirectory: true)
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
