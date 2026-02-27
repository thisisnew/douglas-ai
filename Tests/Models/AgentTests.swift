import Testing
import Foundation
@testable import DOUGLAS

@Suite("Agent Model Tests")
struct AgentTests {

    @Test("기본 초기화")
    func initDefaults() {
        let agent = makeTestAgent()
        #expect(agent.name == "TestAgent")
        #expect(agent.status == .idle)
        #expect(agent.isMaster == false)
        #expect(agent.errorMessage == nil)
        #expect(agent.hasImage == false)
    }

    @Test("모든 파라미터 초기화")
    func initAllParameters() {
        let agent = Agent(
            name: "Custom",
            persona: "persona",
            providerName: "OpenAI",
            modelName: "gpt-4o",
            status: .working,
            isMaster: true,
            errorMessage: "err"
        )
        #expect(agent.name == "Custom")
        #expect(agent.status == .working)
        #expect(agent.isMaster == true)
        #expect(agent.errorMessage == "err")
    }

    @Test("createMaster 팩토리 - 기본값")
    func createMasterDefaults() {
        let master = Agent.createMaster()
        #expect(master.isMaster == true)
        #expect(master.name == "마스터")
        #expect(master.providerName == "Claude Code")
        #expect(master.modelName == "claude-sonnet-4-6")
    }

    @Test("createMaster 팩토리 - 커스텀 모델")
    func createMasterCustom() {
        let master = Agent.createMaster(providerName: "OpenAI", modelName: "gpt-4o")
        #expect(master.providerName == "OpenAI")
        #expect(master.modelName == "gpt-4o")
        #expect(master.isMaster == true)
    }

    @Test("Equatable - 같은 값")
    func equalSameValues() {
        let id = UUID()
        let a = Agent(id: id, name: "A", persona: "p", providerName: "P", modelName: "M")
        let b = Agent(id: id, name: "A", persona: "p", providerName: "P", modelName: "M")
        #expect(a == b)
    }

    @Test("Equatable - 같은 ID면 같은 에이전트 (이름 달라도)")
    func equalSameIDDifferentName() {
        let id = UUID()
        let a = Agent(id: id, name: "A", persona: "p", providerName: "P", modelName: "M")
        let b = Agent(id: id, name: "B", persona: "p", providerName: "P", modelName: "M")
        #expect(a == b) // ID 기반 동등성
    }

    @Test("Equatable - 다른 ID면 다른 에이전트")
    func equalDifferentID() {
        let a = Agent(name: "A", persona: "p", providerName: "P", modelName: "M")
        let b = Agent(name: "A", persona: "p", providerName: "P", modelName: "M")
        #expect(a != b)
    }

    @Test("Hashable - 동일 에이전트는 같은 해시")
    func hashableSameAgent() {
        let id = UUID()
        let a = Agent(id: id, name: "A", persona: "p", providerName: "P", modelName: "M")
        let b = Agent(id: id, name: "A", persona: "p", providerName: "P", modelName: "M")
        #expect(a.hashValue == b.hashValue)
        var set = Set<Agent>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    @Test("Codable 라운드트립")
    func codableRoundTrip() throws {
        let original = makeTestAgent(name: "RoundTrip", persona: "test persona")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Agent.self, from: data)
        #expect(decoded.name == original.name)
        #expect(decoded.persona == original.persona)
        #expect(decoded.providerName == original.providerName)
        #expect(decoded.modelName == original.modelName)
        #expect(decoded.status == original.status)
        #expect(decoded.isMaster == original.isMaster)
    }

    @Test("Codable - imageData는 JSON에 포함되지 않음")
    func codableExcludesImageData() throws {
        let agent = makeTestAgent()
        let data = try JSONEncoder().encode(agent)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["imageData"] == nil)
    }

    @Test("Decodable - status 없는 레거시 JSON")
    func decodeLegacyWithoutStatus() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Legacy",
            "persona": "p",
            "providerName": "P",
            "modelName": "M",
            "isMaster": false,
            "hasImage": false
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let agent = try JSONDecoder().decode(Agent.self, from: data)
        #expect(agent.status == .idle)
    }

    @Test("AgentStatus 열거형 rawValue")
    func agentStatusRawValues() {
        #expect(AgentStatus.idle.rawValue == "idle")
        #expect(AgentStatus.working.rawValue == "working")
        #expect(AgentStatus.busy.rawValue == "busy")
        #expect(AgentStatus.error.rawValue == "error")
    }
}
