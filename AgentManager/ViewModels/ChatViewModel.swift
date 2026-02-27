import Foundation
import UserNotifications

// MARK: - Master Action 타입

enum MasterAction {
    case delegate(agents: [String], task: String, contextFrom: [String]?)
    case suggestAgent(name: String, persona: String, provider: String, model: String)
    case chain(steps: [ChainStep])
    case unknown(rawResponse: String)

    struct ChainStep {
        let agent: String
        let task: String
    }
}

// MARK: - Agent Suggestion

struct AgentSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let persona: String
    let recommendedProvider: String
    let recommendedModel: String
    let masterAgentID: UUID
}

// MARK: - ChatViewModel

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messagesByAgent: [UUID: [ChatMessage]] = [:]
    @Published var loadingAgentIDs: Set<UUID> = []
    @Published var toastMessage: String?
    @Published var showToast = false
    @Published var pendingSuggestion: AgentSuggestion?

    /// 하위 호환: 특정 에이전트가 로딩 중인지 확인
    func isLoading(for agentID: UUID?) -> Bool {
        guard let id = agentID else { return false }
        return loadingAgentIDs.contains(id)
    }

    private(set) var agentStore: AgentStore?
    private(set) var providerManager: ProviderManager?
    private(set) var roomManager: RoomManager?

    private let maxRetryAttempts = 2

    init() {}

    /// AppDelegate에서 한 번만 호출 — 의존성 설정 + 알림 권한 요청
    func configure(agentStore: AgentStore, providerManager: ProviderManager, roomManager: RoomManager? = nil) {
        self.agentStore = agentStore
        self.providerManager = providerManager
        self.roomManager = roomManager
        requestNotificationPermissionIfNeeded()
    }

    func messages(for agentID: UUID?) -> [ChatMessage] {
        guard let id = agentID else { return [] }
        return messagesByAgent[id] ?? []
    }

    /// 외부에서 메시지 추가 (SuggestionCard 등)
    func appendMessagePublic(_ message: ChatMessage, for agentID: UUID) {
        appendMessage(message, for: agentID)
    }

    // MARK: - 진행 중인 작업 취소

    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    /// 에이전트별 동시 실행 중인 작업 수 (로딩 상태 관리용)
    private var activeTaskCounts: [UUID: Int] = [:]

    /// 특정 에이전트의 진행 중인 작업을 취소
    func cancelTask(for agentID: UUID) {
        activeTasks[agentID]?.cancel()
        activeTasks.removeValue(forKey: agentID)
        activeTaskCounts[agentID] = 0
        loadingAgentIDs.remove(agentID)
        agentStore?.updateStatus(agentID: agentID, status: .idle)
    }

    /// .app 번들에서만 알림 권한 요청 (테스트 환경 크래시 방지)
    private func requestNotificationPermissionIfNeeded() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - 메시지 전송 (진입점)

    func sendMessage(_ text: String, agentID: UUID? = nil, attachments: [ImageAttachment]? = nil) {
        guard let agentStore = agentStore,
              let providerManager = providerManager else { return }

        // agentID가 명시되면 해당 에이전트, 아니면 selectedAgent 사용
        let targetID = agentID ?? agentStore.selectedAgentID
        guard let agent = agentStore.agents.first(where: { $0.id == targetID }) else { return }

        // 마스터는 각 질문이 독립적 → 이전 작업 취소하지 않음
        // 서브에이전트는 기존 작업 취소
        if !agent.isMaster {
            activeTasks[agent.id]?.cancel()
        }

        let userMessage = ChatMessage(role: .user, content: text, attachments: attachments)
        appendMessage(userMessage, for: agent.id)

        loadingAgentIDs.insert(agent.id)
        activeTaskCounts[agent.id, default: 0] += 1

        let task = Task {
            if agent.isMaster {
                await handleMasterMessage(text, agent: agent, agentStore: agentStore, providerManager: providerManager)
            } else {
                await handleAgentMessage(text, agent: agent, providerManager: providerManager)
            }

            activeTaskCounts[agent.id, default: 1] -= 1
            // 모든 작업이 끝났을 때만 로딩 해제
            if activeTaskCounts[agent.id, default: 0] <= 0 {
                loadingAgentIDs.remove(agent.id)
                activeTaskCounts.removeValue(forKey: agent.id)
            }
            activeTasks.removeValue(forKey: agent.id)
        }
        activeTasks[agent.id] = task
    }

    // MARK: - 마스터 메시지 처리

    private func handleMasterMessage(
        _ text: String,
        agent: Agent,
        agentStore: AgentStore,
        providerManager: ProviderManager
    ) async {
        agentStore.updateStatus(agentID: agent.id, status: .working)

        do {
            guard let provider = providerManager.provider(named: agent.providerName) else {
                throw AIProviderError.apiError("프로바이더 '\(agent.providerName)'을(를) 찾을 수 없습니다.")
            }

            let systemPrompt = agentStore.masterSystemPrompt()
            // 마스터는 히스토리 없이 현재 메시지만 전송 (매 질문이 독립적)
            let messages: [(role: String, content: String)] = [("user", text)]

            let response = try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: systemPrompt,
                messages: messages
            )

            let action = parseMasterResponse(response)

            switch action {
            case .delegate(let agents, let task, let contextFrom):
                await handleDelegation(
                    agentNames: agents, task: task, contextFrom: contextFrom,
                    masterAgent: agent, agentStore: agentStore, providerManager: providerManager
                )

            case .suggestAgent(let name, let persona, let prov, let model):
                await handleAgentSuggestion(
                    name: name, persona: persona, provider: prov, model: model,
                    masterAgent: agent
                )

            case .chain(let steps):
                await handleChain(
                    steps: steps, masterAgent: agent,
                    agentStore: agentStore, providerManager: providerManager
                )

            case .unknown(let rawResponse):
                let reply = ChatMessage(
                    role: .assistant,
                    content: "위임 처리 중 오류가 발생했습니다. 다시 시도해주세요.\n\n원본: \(String(rawResponse.prefix(200)))",
                    agentName: "마스터",
                    messageType: .error
                )
                appendMessage(reply, for: agent.id)
            }

            agentStore.updateStatus(agentID: agent.id, status: .idle)
            sendNotification(agentName: "마스터", message: "작업 완료")

        } catch {
            agentStore.updateStatus(agentID: agent.id, status: .error, errorMessage: error.localizedDescription)
            showToastMessage("마스터 오류: \(error.localizedDescription)")
            sendErrorNotification(agentName: "마스터", error: error.localizedDescription)

            let errorReply = ChatMessage(
                role: .assistant,
                content: "오류가 발생했습니다: \(error.localizedDescription)",
                agentName: "마스터",
                messageType: .error
            )
            appendMessage(errorReply, for: agent.id)

        }
    }

    // MARK: - 서브 에이전트 직접 대화

    private func handleAgentMessage(
        _ text: String,
        agent: Agent,
        providerManager: ProviderManager
    ) async {
        agentStore?.updateStatus(agentID: agent.id, status: .working)

        do {
            guard let provider = providerManager.provider(named: agent.providerName) else {
                throw AIProviderError.apiError("프로바이더 '\(agent.providerName)'을(를) 찾을 수 없습니다.")
            }

            let history = buildConversationHistory(for: agent.id)
            let agentID = agent.id
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: agent.persona,
                conversationMessages: history,
                onToolActivity: { [weak self] activity in
                    Task { @MainActor in
                        let toolMsg = ChatMessage(role: .assistant, content: activity, agentName: agent.name, messageType: .toolActivity)
                        self?.appendMessage(toolMsg, for: agentID)
                    }
                }
            )

            let reply = ChatMessage(role: .assistant, content: response, agentName: agent.name)
            appendMessage(reply, for: agent.id)
            agentStore?.updateStatus(agentID: agent.id, status: .idle)
            sendNotification(agentName: agent.name, message: response)

        } catch {
            agentStore?.updateStatus(agentID: agent.id, status: .error, errorMessage: error.localizedDescription)
            showToastMessage("\(agent.name) 오류: \(error.localizedDescription)")
            sendErrorNotification(agentName: agent.name, error: error.localizedDescription)

            let errorReply = ChatMessage(
                role: .assistant,
                content: "오류가 발생했습니다: \(error.localizedDescription)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorReply, for: agent.id)
        }
    }

    // MARK: - 위임 → 방 생성

    private func handleDelegation(
        agentNames: [String],
        task: String,
        contextFrom: [String]?,
        masterAgent: Agent,
        agentStore: AgentStore,
        providerManager: ProviderManager
    ) async {
        let resolvedAgents = agentNames.compactMap { name in
            agentStore.agents.first(where: { $0.name == name })
        }

        if resolvedAgents.isEmpty {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "위임할 에이전트를 찾을 수 없습니다: \(agentNames.joined(separator: ", "))",
                agentName: "마스터",
                messageType: .error
            )
            appendMessage(errorMsg, for: masterAgent.id)
            return
        }

        let agentIDs = resolvedAgents.map { $0.id }

        // RoomManager가 있으면 방 생성, 없으면 레거시 방식
        if let roomManager = roomManager {
            let agentNamesStr = resolvedAgents.map { $0.name }.joined(separator: ", ")
            let delegationMsg = ChatMessage(
                role: .assistant,
                content: "'\(agentNamesStr)' 에이전트로 방을 생성합니다: \(task)",
                agentName: "마스터",
                messageType: .delegation
            )
            appendMessage(delegationMsg, for: masterAgent.id)

            let room = roomManager.createRoom(
                title: task,
                agentIDs: agentIDs,
                createdBy: .master(agentID: masterAgent.id)
            )
            roomManager.selectedRoomID = room.id
            roomManager.pendingAutoOpenRoomID = room.id

            roomManager.launchWorkflow(roomID: room.id, task: task)
        } else {
            // 레거시 폴백: 기존 방식으로 실행
            await legacyDelegation(
                resolvedAgents: resolvedAgents, task: task, contextFrom: contextFrom,
                masterAgent: masterAgent, agentStore: agentStore, providerManager: providerManager
            )
        }
    }

    /// 레거시 위임 (RoomManager 없을 때 폴백)
    private func legacyDelegation(
        resolvedAgents: [Agent],
        task: String,
        contextFrom: [String]?,
        masterAgent: Agent,
        agentStore: AgentStore,
        providerManager: ProviderManager
    ) async {
        let delegationMsg = ChatMessage(
            role: .assistant,
            content: "'\(resolvedAgents.map { $0.name }.joined(separator: ", "))'에게 작업을 위임합니다...",
            agentName: "마스터",
            messageType: .delegation
        )
        appendMessage(delegationMsg, for: masterAgent.id)

        let contextMessages = buildContextMessages(from: contextFrom, agentStore: agentStore)
        var results: [(agentName: String, response: String)] = []

        await withTaskGroup(of: (String, String?).self) { group in
            for subAgent in resolvedAgents {
                group.addTask { [self] in
                    let response = await self.executeDelegation(
                        to: subAgent, task: task,
                        contextMessages: contextMessages,
                        providerManager: providerManager,
                        agentStore: agentStore,
                        masterID: masterAgent.id
                    )
                    return (subAgent.name, response)
                }
            }
            for await (name, response) in group {
                if let response { results.append((name, response)) }
            }
        }

        if results.count > 1 {
            await generateSummary(
                results: results, masterAgent: masterAgent,
                providerManager: providerManager, agentStore: agentStore
            )
        }
    }

    // MARK: - 단일 위임 실행 + 재시도 (Feature 4)

    private func executeDelegation(
        to agent: Agent,
        task: String,
        contextMessages: [(role: String, content: String)]?,
        providerManager: ProviderManager,
        agentStore: AgentStore,
        masterID: UUID
    ) async -> String? {
        var messages: [(role: String, content: String)] = []
        if let ctx = contextMessages {
            messages.append(contentsOf: ctx)
        }
        messages.append(("user", task))

        for attempt in 0...maxRetryAttempts {
            agentStore.updateStatus(agentID: agent.id, status: .working)

            do {
                guard let provider = providerManager.provider(named: agent.providerName) else {
                    throw AIProviderError.apiError("프로바이더를 찾을 수 없습니다.")
                }

                let response = try await ToolExecutor.smartSend(
                    provider: provider,
                    agent: agent,
                    systemPrompt: agent.persona,
                    messages: messages
                )

                let reply = ChatMessage(role: .assistant, content: response, agentName: agent.name)
                appendMessage(reply, for: masterID)
                appendMessage(reply, for: agent.id)
                agentStore.updateStatus(agentID: agent.id, status: .idle)
                sendNotification(agentName: agent.name, message: response)
                return response

            } catch {
                if attempt < maxRetryAttempts {
                    let retryMsg = ChatMessage(
                        role: .assistant,
                        content: "\(agent.name) 오류 발생, 재시도 중... (\(attempt + 1)/\(maxRetryAttempts))",
                        agentName: "마스터",
                        messageType: .error
                    )
                    appendMessage(retryMsg, for: masterID)
                    try? await Task.sleep(for: .seconds(2))
                } else {
                    agentStore.updateStatus(agentID: agent.id, status: .error, errorMessage: error.localizedDescription)
                    let errorMsg = ChatMessage(
                        role: .assistant,
                        content: "\(agent.name) 작업 실패: \(error.localizedDescription)",
                        agentName: "마스터",
                        messageType: .error
                    )
                    appendMessage(errorMsg, for: masterID)
                    sendErrorNotification(agentName: agent.name, error: error.localizedDescription)
                    return nil
                }
            }
        }
        return nil
    }

    // MARK: - 결과 취합/요약 (Feature 2)

    private func generateSummary(
        results: [(agentName: String, response: String)],
        masterAgent: Agent,
        providerManager: ProviderManager,
        agentStore: AgentStore
    ) async {
        let summaryPrompt = results.map { "[\($0.agentName)의 응답]\n\($0.response)" }
            .joined(separator: "\n\n---\n\n")

        do {
            guard let provider = providerManager.provider(named: masterAgent.providerName) else { return }
            let summaryResponse = try await provider.sendMessage(
                model: masterAgent.modelName,
                systemPrompt: "당신은 여러 전문가의 응답을 종합하는 요약자입니다. 각 응답의 핵심을 정리하고, 공통점과 차이점을 분석해서 간결하게 요약하세요.",
                messages: [("user", summaryPrompt)]
            )
            let summaryMsg = ChatMessage(
                role: .assistant,
                content: summaryResponse,
                agentName: "마스터",
                messageType: .summary
            )
            appendMessage(summaryMsg, for: masterAgent.id)
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "요약 생성 실패: \(error.localizedDescription)",
                agentName: "마스터",
                messageType: .error
            )
            appendMessage(errorMsg, for: masterAgent.id)
        }
    }

    // MARK: - 에이전트 생성 제안 (Feature 3)

    private func handleAgentSuggestion(
        name: String,
        persona: String,
        provider: String,
        model: String,
        masterAgent: Agent
    ) async {
        let suggestionMsg = ChatMessage(
            role: .assistant,
            content: "적합한 에이전트가 없습니다. 새 에이전트를 제안합니다:\n\n이름: \(name)\n역할: \(persona)",
            agentName: "마스터",
            messageType: .suggestion
        )
        appendMessage(suggestionMsg, for: masterAgent.id)

        pendingSuggestion = AgentSuggestion(
            name: name,
            persona: persona,
            recommendedProvider: provider,
            recommendedModel: model,
            masterAgentID: masterAgent.id
        )
    }

    // MARK: - 워크플로우 체이닝 → 방 생성

    private func handleChain(
        steps: [MasterAction.ChainStep],
        masterAgent: Agent,
        agentStore: AgentStore,
        providerManager: ProviderManager
    ) async {
        let stepNames = steps.map { $0.agent }.joined(separator: " → ")

        // 체인의 모든 에이전트 해석
        let allAgentNames = Array(Set(steps.map { $0.agent }))
        let resolvedAgents = allAgentNames.compactMap { name in
            agentStore.agents.first(where: { $0.name == name })
        }
        let agentIDs = resolvedAgents.map { $0.id }

        if let roomManager = roomManager {
            let chainMsg = ChatMessage(
                role: .assistant,
                content: "체인 실행을 위한 방을 생성합니다: \(stepNames)",
                agentName: "마스터",
                messageType: .chainProgress
            )
            appendMessage(chainMsg, for: masterAgent.id)

            let taskDescription = steps.map { "\($0.agent): \($0.task)" }.joined(separator: "\n")
            let room = roomManager.createRoom(
                title: "체인: \(stepNames)",
                agentIDs: agentIDs,
                createdBy: .master(agentID: masterAgent.id)
            )
            roomManager.selectedRoomID = room.id

            Task { await roomManager.startRoomWorkflow(roomID: room.id, task: taskDescription) }
        } else {
            // 레거시 폴백
            await legacyChain(steps: steps, masterAgent: masterAgent, agentStore: agentStore, providerManager: providerManager)
        }
    }

    /// 레거시 체인 실행 (RoomManager 없을 때)
    private func legacyChain(
        steps: [MasterAction.ChainStep],
        masterAgent: Agent,
        agentStore: AgentStore,
        providerManager: ProviderManager
    ) async {
        let stepNames = steps.map { $0.agent }.joined(separator: " → ")
        let announceMsg = ChatMessage(
            role: .assistant,
            content: "체인 실행: \(stepNames)",
            agentName: "마스터",
            messageType: .chainProgress
        )
        appendMessage(announceMsg, for: masterAgent.id)

        var previousOutput: String? = nil

        for (index, step) in steps.enumerated() {
            guard let subAgent = agentStore.subAgents.first(where: { $0.name == step.agent }) else {
                let errorMsg = ChatMessage(
                    role: .assistant,
                    content: "체인 중단: '\(step.agent)' 에이전트를 찾을 수 없습니다.",
                    agentName: "마스터",
                    messageType: .error
                )
                appendMessage(errorMsg, for: masterAgent.id)
                return
            }

            var fullTask = step.task
            if let prev = previousOutput {
                fullTask = "이전 단계 결과:\n\(prev)\n\n현재 작업:\n\(step.task)"
            }

            let stepMsg = ChatMessage(
                role: .assistant,
                content: "[\(index + 1)/\(steps.count)] \(subAgent.name)에게 작업 전달 중...",
                agentName: "마스터",
                messageType: .chainProgress
            )
            appendMessage(stepMsg, for: masterAgent.id)

            let result = await executeDelegation(
                to: subAgent, task: fullTask,
                contextMessages: nil,
                providerManager: providerManager,
                agentStore: agentStore,
                masterID: masterAgent.id
            )

            guard let output = result else {
                let fallbackMsg = ChatMessage(
                    role: .assistant,
                    content: "체인이 \(subAgent.name) 단계에서 실패했습니다.",
                    agentName: "마스터",
                    messageType: .error
                )
                appendMessage(fallbackMsg, for: masterAgent.id)
                if let prev = previousOutput {
                    await masterFallbackResponse(
                        context: prev, masterAgent: masterAgent,
                        providerManager: providerManager, agentStore: agentStore
                    )
                }
                return
            }
            previousOutput = output
        }

        if steps.count > 1, previousOutput != nil {
            let completionMsg = ChatMessage(
                role: .assistant,
                content: "체인 완료. 최종 결과가 위에 표시되었습니다.",
                agentName: "마스터",
                messageType: .chainProgress
            )
            appendMessage(completionMsg, for: masterAgent.id)
        }
    }

    // MARK: - 마스터 폴백 응답 (Feature 4)

    private func masterFallbackResponse(
        context: String,
        masterAgent: Agent,
        providerManager: ProviderManager,
        agentStore: AgentStore
    ) async {
        let fallbackNote = ChatMessage(
            role: .assistant,
            content: "에이전트 위임 실패. 마스터가 직접 응답합니다.",
            agentName: "마스터",
            messageType: .delegation
        )
        appendMessage(fallbackNote, for: masterAgent.id)

        do {
            guard let provider = providerManager.provider(named: masterAgent.providerName) else { return }
            let response = try await provider.sendMessage(
                model: masterAgent.modelName,
                systemPrompt: "이전 에이전트 위임이 실패했습니다. 가능한 범위에서 직접 답변해 주세요.",
                messages: [("user", context)]
            )
            let reply = ChatMessage(role: .assistant, content: response, agentName: "마스터")
            appendMessage(reply, for: masterAgent.id)
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "마스터 직접 응답도 실패: \(error.localizedDescription)",
                agentName: "마스터",
                messageType: .error
            )
            appendMessage(errorMsg, for: masterAgent.id)
        }
    }

    // MARK: - 컨텍스트 관리 (Feature 6)

    private func buildContextFromAgent(_ agentID: UUID, maxMessages: Int = 10) -> String {
        let msgs = messagesByAgent[agentID] ?? []
        return msgs.suffix(maxMessages).map { msg in
            let role = msg.role == .user ? "사용자" : (msg.agentName ?? "어시스턴트")
            return "\(role): \(msg.content)"
        }.joined(separator: "\n")
    }

    private func buildContextMessages(
        from agentNames: [String]?,
        agentStore: AgentStore
    ) -> [(role: String, content: String)]? {
        guard let names = agentNames, !names.isEmpty else { return nil }
        var messages: [(String, String)] = []
        for name in names {
            if let agent = agentStore.agents.first(where: { $0.name == name }) {
                let context = buildContextFromAgent(agent.id)
                if !context.isEmpty {
                    messages.append(("user", "[\(name)의 대화 컨텍스트]\n\(context)"))
                    messages.append(("assistant", "이해했습니다. 해당 컨텍스트를 참고하겠습니다."))
                }
            }
        }
        return messages.isEmpty ? nil : messages
    }

    // MARK: - JSON 파싱

    func parseMasterResponse(_ response: String) -> MasterAction {
        let cleaned = extractJSON(from: response)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            return .unknown(rawResponse: response)
        }

        switch action {
        case "delegate":
            guard let agents = json["agents"] as? [String],
                  let task = json["task"] as? String else {
                return .unknown(rawResponse: response)
            }
            let contextFrom = json["context_from"] as? [String]
            return .delegate(agents: agents, task: task, contextFrom: contextFrom)

        case "suggest_agent":
            guard let name = json["name"] as? String,
                  let persona = json["persona"] as? String else {
                return .unknown(rawResponse: response)
            }
            let provider = json["recommended_provider"] as? String ?? ""
            let model = json["recommended_model"] as? String ?? ""
            return .suggestAgent(name: name, persona: persona, provider: provider, model: model)

        case "chain":
            guard let stepsArray = json["steps"] as? [[String: String]] else {
                return .unknown(rawResponse: response)
            }
            let steps = stepsArray.compactMap { dict -> MasterAction.ChainStep? in
                guard let agent = dict["agent"], let task = dict["task"] else { return nil }
                return MasterAction.ChainStep(agent: agent, task: task)
            }
            return steps.isEmpty ? .unknown(rawResponse: response) : .chain(steps: steps)

        default:
            return .unknown(rawResponse: response)
        }
    }

    /// 마크다운 코드블록이나 텍스트에서 JSON 추출
    func extractJSON(from text: String) -> String {
        // ```json ... ``` 블록
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", range: startRange.upperBound..<text.endIndex) {
            let jsonStr = String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return jsonStr
        }
        // ``` ... ``` 블록
        if let startRange = text.range(of: "```\n"),
           let endRange = text.range(of: "\n```", range: startRange.upperBound..<text.endIndex) {
            let jsonStr = String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return jsonStr
        }
        // { ... } 찾기
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    // MARK: - Helpers

    private func appendMessage(_ message: ChatMessage, for agentID: UUID) {
        if messagesByAgent[agentID] == nil {
            messagesByAgent[agentID] = []
        }
        messagesByAgent[agentID]?.append(message)
        scheduleSave()
    }

    // MARK: - 대화 기록 영속화

    private static var chatDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentmanager")
        let dir = appSupport.appendingPathComponent("AgentManager/chats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var saveTask: Task<Void, Never>?

    /// 짧은 디바운스로 저장 (빈번한 쓰기 방지)
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveMessages()
        }
    }

    func clearMessages(for agentID: UUID) {
        messagesByAgent[agentID] = []
        // 저장 파일도 삭제
        let file = Self.chatDirectory.appendingPathComponent("\(agentID.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    private func saveMessages() {
        let dir = Self.chatDirectory
        for (agentID, messages) in messagesByAgent {
            let file = dir.appendingPathComponent("\(agentID.uuidString).json")
            if let data = try? JSONEncoder().encode(messages) {
                try? data.write(to: file)
            }
        }
    }

    func loadMessages() {
        let dir = Self.chatDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            let uuidString = file.deletingPathExtension().lastPathComponent
            guard let uuid = UUID(uuidString: uuidString),
                  let data = try? Data(contentsOf: file),
                  let msgs = try? JSONDecoder().decode([ChatMessage].self, from: data) else { continue }
            messagesByAgent[uuid] = msgs
        }
    }

    func buildHistory(for agentID: UUID) -> [(role: String, content: String)] {
        let msgs = messagesByAgent[agentID] ?? []
        // 내부 메시지(delegation, chainProgress, error, suggestion)를 제외하고
        // 실제 대화 메시지(text, summary)만 API에 전송
        return msgs
            .filter { [.text, .summary].contains($0.messageType) }
            .suffix(20)
            .map { msg in
                let role: String
                switch msg.role {
                case .user:      role = "user"
                case .assistant: role = "assistant"
                case .system:    role = "system"
                }
                return (role: role, content: msg.content)
            }
    }

    /// 이미지 첨부를 포함한 ConversationMessage 히스토리 빌드
    func buildConversationHistory(for agentID: UUID) -> [ConversationMessage] {
        let msgs = messagesByAgent[agentID] ?? []
        return msgs
            .filter { [.text, .summary].contains($0.messageType) }
            .suffix(20)
            .map { msg in
                let role: String
                switch msg.role {
                case .user:      role = "user"
                case .assistant: role = "assistant"
                case .system:    role = "system"
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

    private var toastDismissTask: Task<Void, Never>?

    func showToastMessage(_ message: String) {
        // 이전 dismiss 타이머 취소 → 경합 방지
        toastDismissTask?.cancel()
        toastMessage = message
        showToast = true
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            showToast = false
        }
    }

    // MARK: - 알림

    private nonisolated func sendNotification(agentName: String, message: String) {
        // 번들 ID가 없는 CLI 빌드에서는 UNUserNotificationCenter 접근 시 crash
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(agentName): 작업 완료"
        content.body = String(message.prefix(100))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private nonisolated func sendErrorNotification(agentName: String, error: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(agentName): 오류 발생"
        content.body = String(error.prefix(100))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
