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

    /// 서브 에이전트 순서 변경 (드래그 앤 드롭)
    func moveSubAgent(fromID: UUID, toID: UUID) {
        // 마스터 제외한 서브 에이전트만 재배치
        guard fromID != toID else { return }
        guard let fromIdx = agents.firstIndex(where: { $0.id == fromID }),
              let toIdx = agents.firstIndex(where: { $0.id == toID }) else { return }
        guard !agents[fromIdx].isMaster, !agents[toIdx].isMaster else { return }

        let agent = agents.remove(at: fromIdx)
        let insertIdx = agents.firstIndex(where: { $0.id == toID }) ?? agents.endIndex
        agents.insert(agent, at: insertIdx)
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

    /// 마스터의 PM/오케스트레이터 시스템 프롬프트
    func masterSystemPrompt() -> String {
        """
        당신은 PM/오케스트레이터입니다.

        역할:
        - 사용자의 요구사항을 분석하고 분류합니다
        - 적합한 전문가를 식별하고 팀을 구성합니다
        - 토론을 조율하고 합의를 이끌어냅니다
        - 작업 방향이 맞는지 확인하고, 전문가의 업무를 대신 수행하지 않습니다

        핵심 원칙: 정보가 부족하면 반드시 사용자에게 먼저 질문하라. 추측하지 마라.
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
              var loaded = try? JSONDecoder().decode([Agent].self, from: data) else {
            return
        }
        // 마이그레이션: 마스터 에이전트 이름/페르소나 최신화
        for i in loaded.indices where loaded[i].isMaster {
            let master = Agent.createMaster(
                providerName: loaded[i].providerName,
                modelName: loaded[i].modelName
            )
            if loaded[i].name == "마스터" || !loaded[i].persona.contains("## 정체성") {
                loaded[i].name = master.name
                loaded[i].persona = master.persona
            }
        }
        agents = loaded
    }
}
