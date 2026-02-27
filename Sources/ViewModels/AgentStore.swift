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
            return "- \"\(agent.name)\" [도구: \(toolStr)]: \(agent.persona)"
        }
        let agentList = agentLines.joined(separator: "\n")

        let jiraStatus = JiraConfig.shared.isConfigured
            ? "Jira 연동: 활성 (web_fetch 도구로 Jira 티켓 조회 가능)"
            : "Jira 연동: 미설정 (API 설정에서 Jira 연결 필요)"

        // 분석가 에이전트 존재 여부 감지
        let analystAgent = subAgents.first { agent in
            agent.roleTemplateID == "requirements_analyst" || agent.roleTemplateID == "jira_analyst"
        }

        let routingStrategy: String
        if let analyst = analystAgent {
            routingStrategy = """
            라우팅 전략 (분석가 우선):
            - 복잡한 작업, 새로운 요구사항, 팀 빌딩이 필요한 요청 → "\(analyst.name)"에게 위임
              (분석가는 invite_agent, list_agents, suggest_agent_creation 도구로 필요한 에이전트를 직접 초대/생성합니다)
            - 특정 에이전트에게 직접 지시하는 단순 작업 → 해당 에이전트에게 delegate
            - 에이전트 이름/역할을 명시적으로 언급한 경우 → 해당 에이전트에게 delegate
            """
        } else {
            routingStrategy = """
            라우팅 전략:
            - 분석가 에이전트가 없습니다. 요구사항 분석이 필요한 복잡한 작업은 suggest_agent로 분석가 생성을 제안하세요.
              (recommended_preset: "분석가", persona: "요구사항 분석 + 팀 빌딩 전문가")
            - 단순 작업은 기존 에이전트에게 직접 delegate 하세요.
            """
        }

        return """
        너는 라우터다. 사용자 요청을 분석해서 적합한 에이전트에게 위임하라.
        직접 답변은 절대 금지. 반드시 delegate 또는 suggest_agent 중 하나를 선택하라.
        JSON만 출력.

        에이전트 목록:
        \(agentList.isEmpty ? "(없음)" : agentList)

        \(jiraStatus)

        \(routingStrategy)

        출력 형식 (택 1):

        1) 적합한 에이전트가 있을 때:
        {"action":"delegate","agents":["에이전트 이름(정확히)"],"task":"구체적 지시"}

        2) 여러 에이전트를 순차 실행할 때:
        {"action":"chain","steps":[{"agent":"에이전트 이름(정확히)","task":"지시"}]}

        3) 적합한 에이전트가 없을 때 — 새 에이전트 제안:
        {"action":"suggest_agent","name":"이름","persona":"역할 설명","recommended_preset":"프리셋"}

        recommended_preset 선택지:
        - 리서처: web_search, web_fetch (URL·웹 조회)
        - 개발자: file_read, file_write, shell_exec (코드·파일)
        - 분석가: file_read, shell_exec, web_fetch, invite_agent, list_agents, suggest_agent_creation (분석·팀빌딩)
        - 전체 권한: 전체 도구

        에이전트 매칭 규칙 (우선순위 순서):
        1. 이름 매칭: 사용자가 에이전트 이름이나 역할 키워드를 언급하면 해당 에이전트를 delegate
        2. 역할 매칭: 이름에 없으면 persona 설명에서 역할이 일치하는 에이전트 선택
        3. 능력 매칭: 요청에 필요한 도구를 가진 에이전트 선택
        4. 해당 없음: 위 모두 불일치 시에만 suggest_agent

        기타 규칙:
        - agents 배열에 넣는 이름은 에이전트 목록에 있는 이름을 정확히 사용
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
