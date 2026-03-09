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
        #expect(master.name == "DOUGLAS")
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

    @Test("Equatable - 같은 ID라도 이름 다르면 다른 에이전트")
    func equalSameIDDifferentName() {
        let id = UUID()
        let a = Agent(id: id, name: "A", persona: "p", providerName: "P", modelName: "M")
        let b = Agent(id: id, name: "B", persona: "p", providerName: "P", modelName: "M")
        #expect(a != b) // id + name + hasImage + status 기반 동등성
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

    // MARK: - resolvedToolIDs (모든 에이전트 전체 도구)

    @Test("resolvedToolIDs - 항상 전체 도구")
    func resolvedToolIDsAlwaysAll() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M")
        #expect(agent.resolvedToolIDs == ToolRegistry.allToolIDs)
    }

    @Test("hasToolsEnabled - 항상 true")
    func hasToolsEnabledAlwaysTrue() {
        let agent = Agent(name: "A", persona: "p", providerName: "P", modelName: "M")
        #expect(agent.hasToolsEnabled == true)
    }

    // MARK: - imageData (파일 시스템 I/O)

    @Test("imageData 변경 시 Equatable이 변경을 감지해야 함")
    func imageChangeDetectedByEquatable() {
        let id = UUID()
        var agent = Agent(id: id, name: "A", persona: "p", providerName: "P", modelName: "M")

        // 첫 번째 이미지 설정
        agent.imageData = Data("image-v1".utf8)
        let snapshot1 = agent

        // 다른 이미지로 변경
        agent.imageData = Data("image-v2".utf8)
        let snapshot2 = agent

        // SwiftUI가 변경을 감지하려면 두 스냅샷이 다르게 비교되어야 함
        #expect(snapshot1 != snapshot2, "이미지를 교체하면 Agent 비교에서 차이가 감지되어야 합니다")

        // cleanup
        agent.imageData = nil
    }

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

    @Test("Decodable - 레거시 capabilityPreset JSON 무시")
    func decodeLegacyPresetJSON() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Dev",
            "persona": "p",
            "providerName": "P",
            "modelName": "M",
            "isMaster": false,
            "hasImage": false,
            "capabilityPreset": "개발자"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let agent = try JSONDecoder().decode(Agent.self, from: data)
        #expect(agent.name == "Dev")
        #expect(agent.resolvedToolIDs == ToolRegistry.allToolIDs)
    }

    @Test("createMaster - 기본 속성 확인")
    func createMasterDefaults2() {
        let master = Agent.createMaster()
        #expect(master.persona.contains("AI 집사"))
        #expect(master.status == .idle)
        #expect(master.errorMessage == nil)
        #expect(master.hasImage == false)
    }

    @Test("Codable - 전체 도구 라운드트립")
    func codableToolsRoundTrip() throws {
        let original = Agent(name: "A", persona: "p", providerName: "P", modelName: "M")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Agent.self, from: data)
        #expect(decoded.name == "A")
        #expect(decoded.resolvedToolIDs == ToolRegistry.allToolIDs)
    }

    // MARK: - workingRules

    @Test("workingRules — inline 초기화")
    func workingRulesInline() {
        let agent = Agent(
            name: "Dev",
            persona: "개발자",
            providerName: "P",
            modelName: "M",
            workingRules: WorkingRulesSource(inlineText: "브랜치 전략: feature/ 사용")
        )
        #expect(agent.workingRules == WorkingRulesSource(inlineText: "브랜치 전략: feature/ 사용"))
    }

    @Test("workingRules — filePath 초기화")
    func workingRulesFilePath() {
        let agent = Agent(
            name: "Dev",
            persona: "개발자",
            providerName: "P",
            modelName: "M",
            workingRules: WorkingRulesSource(filePaths: ["/path/to/.cursorrules"])
        )
        #expect(agent.workingRules == WorkingRulesSource(filePaths: ["/path/to/.cursorrules"]))
    }

    @Test("workingRules — 기본값 nil")
    func workingRulesDefault() {
        let agent = Agent(name: "Dev", persona: "p", providerName: "P", modelName: "M")
        #expect(agent.workingRules == nil)
    }

    @Test("resolvedSystemPrompt — 규칙 없으면 persona만")
    func resolvedSystemPromptNoRules() {
        let agent = Agent(name: "Dev", persona: "개발자입니다.", providerName: "P", modelName: "M")
        #expect(agent.resolvedSystemPrompt == "개발자입니다.")
    }

    @Test("resolvedSystemPrompt — 규칙 있으면 결합")
    func resolvedSystemPromptWithRules() {
        let agent = Agent(
            name: "Dev",
            persona: "개발자입니다.",
            providerName: "P",
            modelName: "M",
            workingRules: WorkingRulesSource(inlineText: "탭 대신 스페이스 사용")
        )
        let prompt = agent.resolvedSystemPrompt
        #expect(prompt.contains("개발자입니다."))
        #expect(prompt.contains("작업 규칙"))
        #expect(prompt.contains("탭 대신 스페이스 사용"))
    }

    @Test("resolvedSystemPrompt — 빈 규칙이면 persona만")
    func resolvedSystemPromptEmptyRules() {
        let agent = Agent(
            name: "Dev",
            persona: "개발자입니다.",
            providerName: "P",
            modelName: "M",
            workingRules: WorkingRulesSource(inlineText: "  ")
        )
        #expect(agent.resolvedSystemPrompt == "개발자입니다.")
    }

    @Test("Codable — workingRules 라운드트립")
    func codableWorkingRulesRoundTrip() throws {
        let original = Agent(
            name: "Dev",
            persona: "p",
            providerName: "P",
            modelName: "M",
            workingRules: WorkingRulesSource(inlineText: "규칙 텍스트")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Agent.self, from: data)
        #expect(decoded.workingRules == WorkingRulesSource(inlineText: "규칙 텍스트"))
    }

    @Test("Decodable — workingRules 없는 레거시 JSON 호환")
    func decodeLegacyWithoutWorkingRules() throws {
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
        #expect(agent.workingRules == nil)
        #expect(agent.resolvedSystemPrompt == "p")
    }

    // MARK: - workRules (레코드 기반)

    @Test("workRules — 초기화 + resolvedSystemPrompt")
    func workRulesInit() {
        let rules = [
            WorkRule(name: "코딩", summary: "코드 작성", content: .inline("탭 사용")),
            WorkRule(name: "PR", summary: "코드 리뷰", content: .inline("리뷰 필수"))
        ]
        let agent = Agent(name: "Dev", persona: "개발자", providerName: "P", modelName: "M", workRules: rules)
        #expect(agent.workRules.count == 2)
        let prompt = agent.resolvedSystemPrompt
        #expect(prompt.contains("탭 사용"))
        #expect(prompt.contains("리뷰 필수"))
    }

    @Test("resolvedSystemPrompt(activeRuleIDs:) — nil이면 전체")
    func resolvedSystemPromptAllRules() {
        let rules = [
            WorkRule(name: "A", summary: "", content: .inline("규칙A")),
            WorkRule(name: "B", summary: "", content: .inline("규칙B"))
        ]
        let agent = Agent(name: "Dev", persona: "p", providerName: "P", modelName: "M", workRules: rules)
        let prompt = agent.resolvedSystemPrompt(activeRuleIDs: nil)
        #expect(prompt.contains("규칙A"))
        #expect(prompt.contains("규칙B"))
    }

    @Test("resolvedSystemPrompt(activeRuleIDs:) — Set으로 필터링")
    func resolvedSystemPromptFilteredRules() {
        let rules = [
            WorkRule(name: "A", summary: "", content: .inline("규칙A")),
            WorkRule(name: "B", summary: "", content: .inline("규칙B"))
        ]
        let agent = Agent(name: "Dev", persona: "p", providerName: "P", modelName: "M", workRules: rules)
        let prompt = agent.resolvedSystemPrompt(activeRuleIDs: Set([rules[0].id]))
        #expect(prompt.contains("규칙A"))
        #expect(!prompt.contains("규칙B"))
    }

    @Test("resolvedSystemPrompt(activeRuleIDs:) — 빈 Set이면 persona만")
    func resolvedSystemPromptEmptySet() {
        let rules = [WorkRule(name: "A", summary: "", content: .inline("규칙A"))]
        let agent = Agent(name: "Dev", persona: "p", providerName: "P", modelName: "M", workRules: rules)
        let prompt = agent.resolvedSystemPrompt(activeRuleIDs: Set())
        #expect(prompt == "p")
    }

    @Test("레거시 마이그레이션 — workingRules → workRules 자동 변환")
    func legacyMigration() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Legacy",
            "persona": "p",
            "providerName": "P",
            "modelName": "M",
            "isMaster": false,
            "hasImage": false,
            "workingRules": ["inlineText": "레거시 규칙", "filePaths": []]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let agent = try JSONDecoder().decode(Agent.self, from: data)
        #expect(agent.workRules.count == 1)
        #expect(agent.workRules[0].name == "업무 규칙")
        #expect(agent.workRules[0].isAlwaysActive == true)
        #expect(agent.resolvedSystemPrompt.contains("레거시 규칙"))
    }

    @Test("workRules + workingRules 동시 → workRules 우선")
    func workRulesPriority() {
        let rules = [WorkRule(name: "New", summary: "", content: .inline("신규 규칙"))]
        let agent = Agent(
            name: "Dev", persona: "p", providerName: "P", modelName: "M",
            workingRules: WorkingRulesSource(inlineText: "레거시"),
            workRules: rules
        )
        let prompt = agent.resolvedSystemPrompt
        #expect(prompt.contains("신규 규칙"))
        #expect(!prompt.contains("레거시"))
    }
}
