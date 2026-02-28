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

    var subAgents: [Agent] {
        agents.filter { !$0.isMaster }
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
        // 마이그레이션: 기존 워즈니악 에이전트 자동 제거
        agents.removeAll { $0.name.contains("워즈니악") }
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
        guard !agent.isMaster else { return } // 마스터는 삭제 불가
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
        saveAgents()
    }

    /// 마스터의 시스템 프롬프트에 현재 에이전트 목록 + 응답 형식을 주입
    func masterSystemPrompt() -> String {
        let agentLines = subAgents.map { agent in
            "- \"\(agent.name)\": \(agent.persona.prefix(100))..."
        }
        let agentList = agentLines.joined(separator: "\n")

        // 분석가 에이전트 이름 감지
        let analystAgent = subAgents.first { agent in
            agent.roleTemplateID == "requirements_analyst" || agent.roleTemplateID == "jira_analyst"
        }
        let analystName = analystAgent?.name ?? "요구사항 분석가"

        return """
        너는 라우터다. 사용자 요청을 분석가에게 위임하라.
        직접 답변은 절대 금지. JSON만 출력.
        URL이 포함되어 있어도 절대 직접 접근하지 마라. URL은 그대로 task에 포함하여 위임하라.

        에이전트 목록:
        \(agentList.isEmpty ? "(없음)" : agentList)

        라우팅 규칙:
        1. 사용자가 특정 에이전트를 이름으로 지정한 경우 → 해당 에이전트에게 delegate
        2. 그 외 모든 요청 → "\(analystName)"에게 delegate (분석가가 팀을 구성합니다)

        출력 형식:

        {"action":"delegate","agents":["\(analystName)"],"task":"사용자 요청 전문 (URL 포함)"}

        규칙:
        - agents 배열의 이름은 에이전트 목록에 있는 이름을 정확히 사용
        - task에는 사용자 요청을 빠짐없이 포함 (URL, 파일 경로 등 그대로 전달)
        - JSON만 출력. 부가 설명 금지.
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
