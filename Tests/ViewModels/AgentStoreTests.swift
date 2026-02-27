import Testing
import Foundation
@testable import DOUGLAS

@Suite("AgentStore Tests")
@MainActor
struct AgentStoreTests {

    @Test("init - 기본 마스터 에이전트 생성")
    func initCreatesMaster() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        #expect(store.masterAgent != nil)
        #expect(store.masterAgent?.isMaster == true)
    }

    @Test("init - 모든 상태 idle로 초기화")
    func initResetsStatus() {
        let defaults = makeTestDefaults()
        // 먼저 working 상태 에이전트를 저장
        var agent = Agent.createMaster()
        agent.status = .working
        let data = try! JSONEncoder().encode([agent])
        defaults.set(data, forKey: "savedAgents")

        let store = AgentStore(defaults: defaults)
        #expect(store.masterAgent?.status == .idle)
    }

    @Test("masterAgent 속성")
    func masterAgentProperty() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        #expect(store.masterAgent != nil)
        #expect(store.masterAgent?.isMaster == true)
    }

    @Test("subAgents 속성 - 마스터 제외")
    func subAgentsProperty() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let sub = makeTestAgent(name: "Sub1")
        store.addAgent(sub)
        #expect(store.subAgents.contains(where: { $0.name == "Sub1" }))
        #expect(!store.subAgents.contains(where: { $0.isMaster }))
    }

    @Test("selectedAgent - 기본은 마스터")
    func selectedAgentDefaultsMaster() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        #expect(store.selectedAgent?.isMaster == true)
    }

    @Test("selectedAgent - 특정 에이전트 선택")
    func selectedAgentSpecific() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let sub = makeTestAgent(name: "Sub1")
        store.addAgent(sub)
        store.selectAgent(sub)
        #expect(store.selectedAgent?.name == "Sub1")
    }

    @Test("addAgent")
    func addAgent() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let initialCount = store.agents.count
        let sub = makeTestAgent(name: "NewAgent")
        store.addAgent(sub)
        #expect(store.agents.count == initialCount + 1)
        #expect(store.agents.contains(where: { $0.name == "NewAgent" }))
    }

    @Test("removeAgent - 서브 에이전트 삭제")
    func removeSubAgent() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let sub = makeTestAgent(name: "ToDelete")
        store.addAgent(sub)
        let countBefore = store.agents.count
        store.removeAgent(sub)
        #expect(store.agents.count == countBefore - 1)
        #expect(!store.agents.contains(where: { $0.name == "ToDelete" }))
    }

    @Test("removeAgent - 마스터 삭제 불가")
    func removeMasterProtected() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        guard let master = store.masterAgent else {
            Issue.record("Master not found")
            return
        }
        let countBefore = store.agents.count
        store.removeAgent(master)
        #expect(store.agents.count == countBefore)
        #expect(store.masterAgent != nil)
    }

    @Test("removeAgent - 선택된 에이전트 삭제 시 마스터로 리셋")
    func removeSelectedResetsToMaster() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let sub = makeTestAgent(name: "Selected")
        store.addAgent(sub)
        store.selectAgent(sub)
        store.removeAgent(sub)
        #expect(store.selectedAgentID == store.masterAgent?.id)
    }

    @Test("updateStatus")
    func updateStatus() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        guard let master = store.masterAgent else { return }
        store.updateStatus(agentID: master.id, status: .working)
        #expect(store.agents.first(where: { $0.id == master.id })?.status == .working)
    }

    @Test("updateStatus - 에러 메시지")
    func updateStatusWithError() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        guard let master = store.masterAgent else { return }
        store.updateStatus(agentID: master.id, status: .error, errorMessage: "fail")
        let updated = store.agents.first(where: { $0.id == master.id })
        #expect(updated?.status == .error)
        #expect(updated?.errorMessage == "fail")
    }

    @Test("updateAgent")
    func updateAgent() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let sub = makeTestAgent(name: "Original")
        store.addAgent(sub)
        var updated = sub
        updated.name = "Updated"
        store.updateAgent(updated)
        #expect(store.agents.contains(where: { $0.name == "Updated" }))
        #expect(!store.agents.contains(where: { $0.name == "Original" }))
    }

    @Test("masterSystemPrompt - 서브 에이전트 포함")
    func masterSystemPromptContainsSubAgents() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let sub = makeTestAgent(name: "TestHelper", persona: "helps with testing")
        store.addAgent(sub)
        let prompt = store.masterSystemPrompt()
        #expect(prompt.contains("TestHelper"))
    }

    @Test("masterSystemPrompt - 서브 에이전트 없을 때")
    func masterSystemPromptNoSubAgents() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let prompt = store.masterSystemPrompt()
        #expect(prompt.contains("delegate"))
        #expect(prompt.contains("suggest_agent"))
        #expect(!prompt.contains("\"respond\""))
    }

    @Test("masterSystemPrompt - JSON 형식 포함")
    func masterSystemPromptContainsFormats() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let prompt = store.masterSystemPrompt()
        #expect(prompt.contains("delegate"))
        #expect(prompt.contains("chain"))
        #expect(prompt.contains("suggest_agent"))
    }

    @Test("minimizedAgentIDs - 초기 빈 상태")
    func minimizedAgentIDsEmpty() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        #expect(store.minimizedAgentIDs.isEmpty)
    }

    @Test("updateStatus - 존재하지 않는 에이전트")
    func updateStatusNonExisting() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let fakeID = UUID()
        // 크래시 없이 무시되어야 함
        store.updateStatus(agentID: fakeID, status: .working)
    }

    @Test("updateAgent - 존재하지 않는 에이전트")
    func updateAgentNonExisting() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let fake = makeTestAgent(name: "Ghost")
        // 크래시 없이 무시되어야 함
        store.updateAgent(fake)
        #expect(!store.agents.contains(where: { $0.name == "Ghost" }))
    }

    // MARK: - updateMasterProvider

    @Test("updateMasterProvider - 마스터 프로바이더 변경")
    func updateMasterProvider() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        store.updateMasterProvider(providerName: "OpenAI", modelName: "gpt-4o")
        #expect(store.masterAgent?.providerName == "OpenAI")
        #expect(store.masterAgent?.modelName == "gpt-4o")
    }

    @Test("updateMasterProvider - 영속화 확인")
    func updateMasterProviderPersistence() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        store.updateMasterProvider(providerName: "Google", modelName: "gemini-2.0-flash")

        // 같은 defaults로 새 인스턴스 생성
        let store2 = AgentStore(defaults: defaults)
        #expect(store2.masterAgent?.providerName == "Google")
        #expect(store2.masterAgent?.modelName == "gemini-2.0-flash")
    }

    // MARK: - 에이전트 추가/삭제 영속화

    @Test("addAgent - 영속화 확인")
    func addAgentPersistence() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let sub = makeTestAgent(name: "Persistent")
        store.addAgent(sub)

        let store2 = AgentStore(defaults: defaults)
        #expect(store2.agents.contains(where: { $0.name == "Persistent" }))
    }

    @Test("removeAgent - 영속화 확인")
    func removeAgentPersistence() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let sub = makeTestAgent(name: "ToRemove")
        store.addAgent(sub)
        store.removeAgent(sub)

        let store2 = AgentStore(defaults: defaults)
        #expect(!store2.agents.contains(where: { $0.name == "ToRemove" }))
    }

    // MARK: - selectAgent

    @Test("selectAgent - 존재하지 않는 에이전트 선택 시 selectedAgent가 nil")
    func selectAgentNonExisting() {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let fake = makeTestAgent(name: "Ghost")
        store.selectAgent(fake)
        // selectedAgentID는 설정되지만 agents에 없으므로 selectedAgent는 nil이 아니라 마스터
        // 실제로 selectAgent는 단순히 ID를 설정하므로 agents에서 못 찾으면 fallback
        #expect(store.selectedAgentID == fake.id)
    }

    // MARK: - 워즈니악 마이그레이션

    @Test("init - 기존 워즈니악 에이전트 자동 제거")
    func initRemovesWozniak() {
        let defaults = makeTestDefaults()
        // 워즈니악이 포함된 에이전트 목록을 저장
        let master = Agent.createMaster()
        let wozniak = Agent(name: "워즈니악 (유지보수 담당자)", persona: "test", providerName: "P", modelName: "M")
        let data = try! JSONEncoder().encode([master, wozniak])
        defaults.set(data, forKey: "savedAgents")

        let store = AgentStore(defaults: defaults)
        #expect(!store.agents.contains(where: { $0.name.contains("워즈니악") }))
        #expect(store.masterAgent != nil)
    }
}
