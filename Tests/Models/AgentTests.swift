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

    // MARK: - resolvedToolIDs

    @Test("resolvedToolIDs - preset nil이면 빈 배열")
    func resolvedToolIDsNilPreset() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M", capabilityPreset: nil)
        #expect(agent.resolvedToolIDs.isEmpty)
    }

    @Test("resolvedToolIDs - .none이면 빈 배열")
    func resolvedToolIDsNonePreset() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M", capabilityPreset: CapabilityPreset.none)
        #expect(agent.resolvedToolIDs.isEmpty)
    }

    @Test("resolvedToolIDs - .developer 프리셋")
    func resolvedToolIDsDeveloper() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M", capabilityPreset: .developer)
        let ids = agent.resolvedToolIDs
        #expect(!ids.isEmpty)
        #expect(ids.contains("shell_exec"))
        #expect(ids.contains("file_read"))
        #expect(ids.contains("file_write"))
    }

    @Test("resolvedToolIDs - .researcher 프리셋")
    func resolvedToolIDsResearcher() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M", capabilityPreset: .researcher)
        let ids = agent.resolvedToolIDs
        #expect(!ids.isEmpty)
        #expect(ids.contains("web_fetch"))
    }

    @Test("resolvedToolIDs - .custom은 enabledToolIDs 사용")
    func resolvedToolIDsCustom() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M",
                          capabilityPreset: .custom, enabledToolIDs: ["shell_exec", "file_read"])
        #expect(agent.resolvedToolIDs == ["shell_exec", "file_read"])
    }

    @Test("resolvedToolIDs - .custom + enabledToolIDs nil이면 빈 배열")
    func resolvedToolIDsCustomNilTools() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M",
                          capabilityPreset: .custom, enabledToolIDs: nil)
        #expect(agent.resolvedToolIDs.isEmpty)
    }

    @Test("hasToolsEnabled - 도구 있으면 true")
    func hasToolsEnabledTrue() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M", capabilityPreset: .developer)
        #expect(agent.hasToolsEnabled == true)
    }

    @Test("hasToolsEnabled - 도구 없으면 false")
    func hasToolsEnabledFalse() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M")
        #expect(agent.hasToolsEnabled == false)
    }

    // MARK: - imageData (파일 시스템 I/O)

    @Test("imageData - 설정 후 hasImage true")
    func imageDataSet() {
        let id = UUID()
        var agent = Agent(id: id, name: "A", persona: "p", providerName: "P", modelName: "M")
        #expect(agent.hasImage == false)

        let testData = Data("test-image-data".utf8)
        agent.imageData = testData
        #expect(agent.hasImage == true)
        #expect(agent.imageData == testData)

        // cleanup
        agent.imageData = nil
        #expect(agent.hasImage == false)
        #expect(agent.imageData == nil)
    }

    @Test("imageData - nil로 설정하면 파일 삭제")
    func imageDataClear() {
        let id = UUID()
        var agent = Agent(id: id, name: "A", persona: "p", providerName: "P", modelName: "M")
        agent.imageData = Data("temp".utf8)
        #expect(agent.hasImage == true)

        agent.imageData = nil
        #expect(agent.hasImage == false)
        #expect(agent.imageData == nil)
    }

    @Test("init - imageData 파라미터로 초기화하면 파일 저장됨")
    func initWithImageData() {
        let testData = Data("init-test-image".utf8)
        var agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M", imageData: testData)
        #expect(agent.hasImage == true)
        #expect(agent.imageData == testData)

        // cleanup
        agent.imageData = nil
    }

    // MARK: - Decodable 레거시 마이그레이션

    @Test("Decodable - hasImage true지만 파일 없으면 hasImage false로 수정")
    func decodeWithMissingImageFile() throws {
        let id = UUID()
        let json: [String: Any] = [
            "id": id.uuidString,
            "name": "Agent",
            "persona": "p",
            "providerName": "P",
            "modelName": "M",
            "isMaster": false,
            "hasImage": true  // true지만 실제 파일 없음
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let agent = try JSONDecoder().decode(Agent.self, from: data)
        // 파일이 없으므로 hasImage가 false로 수정됨
        #expect(agent.hasImage == false)
    }

    @Test("Decodable - capabilityPreset 포함 JSON")
    func decodeWithCapabilityPreset() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Dev",
            "persona": "p",
            "providerName": "P",
            "modelName": "M",
            "isMaster": false,
            "hasImage": false,
            "capabilityPreset": "개발자"  // Korean rawValue
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let agent = try JSONDecoder().decode(Agent.self, from: data)
        #expect(agent.capabilityPreset == .developer)
    }

    @Test("Decodable - enabledToolIDs 포함 JSON")
    func decodeWithEnabledToolIDs() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Custom",
            "persona": "p",
            "providerName": "P",
            "modelName": "M",
            "isMaster": false,
            "hasImage": false,
            "capabilityPreset": "사용자 정의",  // Korean rawValue
            "enabledToolIDs": ["shell_exec", "web_fetch"]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let agent = try JSONDecoder().decode(Agent.self, from: data)
        #expect(agent.capabilityPreset == .custom)
        #expect(agent.enabledToolIDs == ["shell_exec", "web_fetch"])
    }

    @Test("createMaster - 기본 속성 확인")
    func createMasterDefaults2() {
        let master = Agent.createMaster()
        #expect(master.persona.contains("라우터"))
        #expect(master.status == .idle)
        #expect(master.errorMessage == nil)
        #expect(master.hasImage == false)
    }

    // MARK: - Codable with capabilityPreset

    @Test("Codable - capabilityPreset 라운드트립")
    func codableWithPreset() throws {
        let original = Agent(name: "A", persona: "p", providerName: "P", modelName: "M",
                             capabilityPreset: .fullAccess, enabledToolIDs: ["shell_exec"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Agent.self, from: data)
        #expect(decoded.capabilityPreset == .fullAccess)
        #expect(decoded.enabledToolIDs == ["shell_exec"])
    }
}
