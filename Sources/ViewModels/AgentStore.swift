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
            "- \"\(agent.name)\": \(agent.persona)"
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
            라우팅 전략 (분석가 부재):
            - 분석가 에이전트가 없습니다.
            - 기존 에이전트의 역할과 맞지 않는 요청은 suggest_agent로 새 에이전트를 제안하세요.
            - suggest_agent의 name과 persona는 요청의 맥락에 맞게 구체적으로 작성하세요:
              • Jira 티켓 → "Jira 요구사항 분석가" (Jira 티켓 분석, 수용 조건 정리, 서브태스크 분해 전문)
              • 코드 리뷰 요청 → "코드 리뷰어" (코드 품질 점검, 개선안 제시)
              • 일반 요구사항 분석 → "요구사항 분석가" (요구사항 분석 + 작업 분해)
              • 기타 → 요청 내용에 맞는 전문가
            - persona에는 해당 에이전트가 담당할 구체적 범위와 제한을 명시하세요.
            - 특정 에이전트 이름/역할을 명시적으로 언급한 단순 작업만 기존 에이전트에 delegate
            """
        }

        return """
        너는 라우터다. 사용자 요청을 분석해서 적합한 에이전트에게 위임하라.
        직접 답변은 절대 금지. 반드시 delegate 또는 suggest_agent 중 하나를 선택하라.
        JSON만 출력. URL이 포함되어 있어도 절대 직접 접근하지 마라. URL은 그대로 task에 포함하여 위임하라.

        모든 에이전트는 전체 도구(파일, 셸, 웹, Jira, 팀빌딩)에 접근 가능합니다.

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
        {"action":"suggest_agent","name":"이름","persona":"역할 설명"}

        에이전트 매칭 규칙 (우선순위 순서):
        1. 라우팅 전략을 최우선 적용 (분석가 우선 위임, 또는 분석가 생성 제안)
        2. 이름 매칭: 사용자가 에이전트 이름이나 역할 키워드를 명시적으로 언급하면 해당 에이전트를 delegate
        3. 역할 매칭: persona 설명에서 역할이 일치하는 에이전트 선택
        4. 해당 없음: suggest_agent

        기타 규칙:
        - agents 배열에 넣는 이름은 에이전트 목록에 있는 이름을 정확히 사용
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
