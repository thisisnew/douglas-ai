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

    /// 마스터의 시스템 프롬프트에 현재 에이전트 목록 + 도구 정보 + 응답 형식을 주입
    func masterSystemPrompt() -> String {
        let agentLines = subAgents.map { agent in
            let tools = agent.resolvedToolIDs
            let toolStr = tools.isEmpty ? "도구 없음" : tools.joined(separator: ", ")
            return "- \(agent.name) [도구: \(toolStr)]: \(agent.persona.prefix(80))"
        }
        let agentList = agentLines.joined(separator: "\n")

        let jiraStatus = JiraConfig.shared.isConfigured
            ? "Jira 연동: 활성 (web_fetch 도구로 Jira 티켓 조회 가능)"
            : "Jira 연동: 미설정 (API 설정에서 Jira 연결 필요)"

        return """
        너는 라우터다. 사용자 요청을 분석해서 적합한 에이전트에게 위임하라.
        직접 답변은 절대 금지. 반드시 delegate 또는 suggest_agent 중 하나를 선택하라.
        JSON만 출력.

        에이전트 목록:
        \(agentList.isEmpty ? "(없음)" : agentList)

        \(jiraStatus)

        출력 형식 (택 1):

        1) 적합한 에이전트가 있을 때:
        {"action":"delegate","agents":["이름1","이름2"],"task":"구체적 지시"}

        2) 여러 에이전트를 순차 실행할 때:
        {"action":"chain","steps":[{"agent":"이름","task":"지시"}]}

        3) 적합한 에이전트가 없을 때 — 새 에이전트 제안:
        {"action":"suggest_agent","name":"이름","persona":"역할 설명","recommended_preset":"프리셋"}

        recommended_preset 선택지:
        - researcher: web_search, web_fetch (URL·웹 조회)
        - developer: file_read, file_write, shell_exec (코드·파일)
        - analyst: file_read, shell_exec, web_fetch (분석·URL)
        - fullAccess: 전체 도구

        규칙:
        - 적합한 에이전트가 있으면 무조건 delegate
        - 에이전트가 있어도 요청에 적합하지 않으면 suggest_agent
        - URL이 포함된 요청은 web_fetch 도구가 있는 에이전트에게 위임
        - Jira URL인데 Jira 연동이 미설정이면 task에 "Jira 연동이 필요합니다. API 설정에서 Jira를 연결해주세요." 안내 포함
        - 여러 명 필요하면 agents에 복수 지정
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
