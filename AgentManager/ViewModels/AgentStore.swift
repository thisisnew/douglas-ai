import Foundation

@MainActor
class AgentStore: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var selectedAgentID: UUID?
    @Published var minimizedAgentIDs: Set<UUID> = []  // 최소화된 채팅 창

    private let saveKey = "savedAgents"
    private let defaults: UserDefaults

    var masterAgent: Agent? {
        agents.first { $0.isMaster }
    }

    var devAgent: Agent? {
        agents.first { $0.isDevAgent }
    }

    var subAgents: [Agent] {
        agents.filter { !$0.isMaster && !$0.isDevAgent }
    }

    var selectedAgent: Agent? {
        guard let id = selectedAgentID else { return masterAgent }
        return agents.first { $0.id == id }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadAgents()
        if agents.isEmpty || !agents.contains(where: { $0.isMaster }) {
            let master = Agent.createMaster()
            agents.insert(master, at: 0)
            selectedAgentID = master.id
        }
        if !agents.contains(where: { $0.isDevAgent }) {
            let dev = Agent.createDevAgent()
            // 마스터 바로 뒤에 삽입
            let insertIndex = agents.firstIndex(where: { $0.isMaster }).map { $0 + 1 } ?? agents.count
            agents.insert(dev, at: insertIndex)
        }
        // 앱 시작 시 모든 에이전트 상태 초기화 (이전 실행의 잔여 상태 제거)
        for i in agents.indices {
            agents[i].status = .idle
            agents[i].errorMessage = nil
        }
        saveAgents()
        if selectedAgentID == nil {
            selectedAgentID = masterAgent?.id
        }
    }

    func addAgent(_ agent: Agent) {
        agents.append(agent)
        saveAgents()
    }

    func removeAgent(_ agent: Agent) {
        guard !agent.isMaster && !agent.isDevAgent else { return } // 마스터/DevAgent는 삭제 불가
        agents.removeAll { $0.id == agent.id }
        if selectedAgentID == agent.id {
            selectedAgentID = masterAgent?.id
        }
        saveAgents()
    }

    func updateStatus(agentID: UUID, status: AgentStatus, errorMessage: String? = nil) {
        if let idx = agents.firstIndex(where: { $0.id == agentID }) {
            agents[idx].status = status
            agents[idx].errorMessage = errorMessage
            // 상태 변경은 런타임 전용 — 빈번한 디스크 쓰기 방지
        }
    }

    func selectAgent(_ agent: Agent) {
        selectedAgentID = agent.id
    }

    func updateAgent(_ updated: Agent) {
        if let idx = agents.firstIndex(where: { $0.id == updated.id }) {
            agents[idx] = updated
            saveAgents()
        }
    }

    /// 온보딩에서 선택한 프로바이더로 마스터/DevAgent 업데이트
    func updateMasterProvider(providerName: String, modelName: String) {
        if let idx = agents.firstIndex(where: { $0.isMaster }) {
            agents[idx].providerName = providerName
            agents[idx].modelName = modelName
        }
        if let idx = agents.firstIndex(where: { $0.isDevAgent }) {
            agents[idx].providerName = providerName
            agents[idx].modelName = modelName
        }
        saveAgents()
    }

    /// 마스터의 시스템 프롬프트에 현재 에이전트 목록 + 응답 형식을 주입
    func masterSystemPrompt() -> String {
        guard let master = masterAgent else { return "" }
        var allAgentLines: [String] = []
        if let dev = devAgent {
            allAgentLines.append("- \(dev.name) [유지보수 담당자]: 앱 개선, 코드 수정, 버그 수정 요청을 처리합니다. 개발 관련 요청은 이 에이전트에게 위임하세요.")
        }
        allAgentLines += subAgents.map { agent in
            "- \(agent.name) [\(agent.providerName)/\(agent.modelName)]: \(agent.persona.prefix(200))"
        }
        let agentList = allAgentLines.joined(separator: "\n")

        return """
        \(master.persona)

        현재 등록된 에이전트:
        \(agentList.isEmpty ? "(없음)" : agentList)

        응답 형식 (반드시 JSON으로만 응답):

        1. 위임 (단일 또는 병렬):
        {"action": "delegate", "agents": ["에이전트이름1", "에이전트이름2"], "task": "구체적 지시"}

        2. 컨텍스트 공유 위임 (다른 에이전트의 대화 내역을 참조):
        {"action": "delegate", "agents": ["에이전트B"], "task": "작업 내용", "context_from": ["에이전트A"]}

        3. 순차 체인 (A의 결과를 B에게 전달):
        {"action": "chain", "steps": [{"agent": "에이전트A", "task": "첫 번째 작업"}, {"agent": "에이전트B", "task": "A의 결과를 바탕으로 수행할 작업"}]}

        4. 직접 답변:
        {"action": "respond", "message": "답변 내용"}

        5. 에이전트 생성 제안 (적합한 에이전트가 없을 때):
        {"action": "suggest_agent", "name": "제안 이름", "persona": "제안 페르소나", "recommended_provider": "제공자", "recommended_model": "모델"}

        규칙:
        - 적합한 에이전트가 있으면 delegate 또는 chain 사용
        - 여러 에이전트에게 동시에 작업을 맡길 수 있으면 agents 배열에 여러 이름을 넣어 delegate 사용
        - 순차적 처리가 필요하면 chain 사용
        - 적합한 에이전트가 없고 생성이 유익하다면 suggest_agent 사용
        - 단순한 질문이거나 에이전트가 필요 없으면 respond 사용
        - 반드시 유효한 JSON으로만 응답할 것
        """
    }

    // MARK: - 저장/불러오기

    private func saveAgents() {
        if let data = try? JSONEncoder().encode(agents) {
            defaults.set(data, forKey: saveKey)
        }
    }

    private func loadAgents() {
        guard let data = defaults.data(forKey: saveKey),
              let loaded = try? JSONDecoder().decode([Agent].self, from: data) else {
            return
        }
        agents = loaded
    }
}
