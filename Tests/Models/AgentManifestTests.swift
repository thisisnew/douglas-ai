import Testing
import Foundation
@testable import DOUGLAS

@Suite("AgentManifest Tests")
struct AgentManifestTests {

    // MARK: - 라운드트립

    @Test("빈 매니페스트 인코딩/디코딩")
    func emptyManifestRoundTrip() throws {
        let manifest = AgentManifest(
            formatVersion: 1,
            exportedAt: Date(),
            exportedFrom: "DOUGLAS",
            agents: []
        )
        let data = try encode(manifest)
        let decoded = try decode(data)

        #expect(decoded.formatVersion == 1)
        #expect(decoded.exportedFrom == "DOUGLAS")
        #expect(decoded.agents.isEmpty)
    }

    @Test("단일 에이전트 라운드트립")
    func singleAgentRoundTrip() throws {
        let entry = AgentManifest.AgentEntry(
            name: "백엔드 개발자",
            persona: "Node.js 전문 개발자",
            isMaster: false,
            providerType: "OpenAI",
            preferredModel: "gpt-4o",
            workingRules: "- 코드 작성 시 테스트 포함 필수",
            avatarBase64: nil
        )
        let manifest = AgentManifest(
            formatVersion: 1,
            exportedAt: Date(),
            exportedFrom: "DOUGLAS",
            agents: [entry]
        )
        let data = try encode(manifest)
        let decoded = try decode(data)

        #expect(decoded.agents.count == 1)
        let agent = decoded.agents[0]
        #expect(agent.name == "백엔드 개발자")
        #expect(agent.persona == "Node.js 전문 개발자")
        #expect(agent.isMaster == false)
        #expect(agent.providerType == "OpenAI")
        #expect(agent.preferredModel == "gpt-4o")
        #expect(agent.workingRules == "- 코드 작성 시 테스트 포함 필수")
        #expect(agent.avatarBase64 == nil)
    }

    // MARK: - 아바타

    @Test("아바타 base64 라운드트립")
    func avatarBase64RoundTrip() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG 시그니처 일부
        let base64 = imageData.base64EncodedString()

        let entry = AgentManifest.AgentEntry(
            name: "디자이너",
            persona: "UI 전문가",
            isMaster: false,
            providerType: "Anthropic",
            preferredModel: "claude-sonnet-4-6",
            workingRules: nil,
            avatarBase64: base64
        )
        let manifest = makeManifest(agents: [entry])
        let data = try encode(manifest)
        let decoded = try decode(data)

        let decodedImage = Data(base64Encoded: decoded.agents[0].avatarBase64!)
        #expect(decodedImage == imageData)
    }

    // MARK: - Agent ↔ AgentEntry 변환

    @Test("Agent → AgentEntry 변환")
    func agentToEntry() {
        let agent = makeTestAgent(
            name: "번역가",
            persona: "다국어 번역 전문가",
            providerName: "Anthropic",
            modelName: "claude-sonnet-4-6"
        )
        let entry = AgentManifest.AgentEntry(from: agent)

        #expect(entry.name == "번역가")
        #expect(entry.persona == "다국어 번역 전문가")
        #expect(entry.isMaster == false)
        #expect(entry.providerType == "Anthropic")
        #expect(entry.preferredModel == "claude-sonnet-4-6")
        #expect(entry.workingRules == nil)
        #expect(entry.avatarBase64 == nil)
    }

    @Test("AgentEntry → Agent 변환")
    func entryToAgent() {
        let entry = AgentManifest.AgentEntry(
            name: "QA 전문가",
            persona: "품질 보증 전문가",
            isMaster: false,
            providerType: "OpenAI",
            preferredModel: "gpt-4o",
            workingRules: "- Given/When/Then 형식",
            avatarBase64: nil
        )
        let agent = entry.toAgent()

        #expect(agent.name == "QA 전문가")
        #expect(agent.persona == "품질 보증 전문가")
        #expect(agent.isMaster == false)
        #expect(agent.providerName == "OpenAI")
        #expect(agent.modelName == "gpt-4o")
        #expect(agent.workingRules?.inlineText == "- Given/When/Then 형식")
    }

    @Test("마스터 AgentEntry → Agent 변환 시 isMaster=false 강제")
    func masterEntryBecomesSub() {
        let entry = AgentManifest.AgentEntry(
            name: "DOUGLAS",
            persona: "AI 집사",
            isMaster: true,
            providerType: "Claude Code",
            preferredModel: "claude-sonnet-4-6",
            workingRules: nil,
            avatarBase64: nil
        )
        let agent = entry.toAgent()
        #expect(agent.isMaster == false)
    }

    // MARK: - workingRules 처리

    @Test("workingRules nil이면 Agent에도 nil")
    func nilWorkingRules() {
        let entry = AgentManifest.AgentEntry(
            name: "테스터",
            persona: "테스트 전문가",
            isMaster: false,
            providerType: "OpenAI",
            preferredModel: "gpt-4o",
            workingRules: nil,
            avatarBase64: nil
        )
        let agent = entry.toAgent()
        #expect(agent.workingRules == nil)
    }

    @Test("빈 workingRules도 nil로 처리")
    func emptyWorkingRules() {
        let entry = AgentManifest.AgentEntry(
            name: "테스터",
            persona: "테스트 전문가",
            isMaster: false,
            providerType: "OpenAI",
            preferredModel: "gpt-4o",
            workingRules: "",
            avatarBase64: nil
        )
        let agent = entry.toAgent()
        #expect(agent.workingRules == nil)
    }

    // MARK: - 이름 중복 해결

    @Test("이름 중복 없으면 그대로")
    func noDuplicate() {
        let agents = [makeTestAgent(name: "번역가")]
        let result = AgentManifest.deduplicateName("QA 전문가", existing: agents)
        #expect(result == "QA 전문가")
    }

    @Test("이름 중복 시 (2) 접미어")
    func duplicateGets2() {
        let agents = [makeTestAgent(name: "번역가")]
        let result = AgentManifest.deduplicateName("번역가", existing: agents)
        #expect(result == "번역가 (2)")
    }

    @Test("이름 연속 중복 시 (3) 접미어")
    func duplicateGets3() {
        let agents = [
            makeTestAgent(name: "번역가"),
            makeTestAgent(name: "번역가 (2)")
        ]
        let result = AgentManifest.deduplicateName("번역가", existing: agents)
        #expect(result == "번역가 (3)")
    }

    // MARK: - 전방 호환

    @Test("알 수 없는 필드가 있어도 디코딩 성공")
    func forwardCompatibility() throws {
        let json = """
        {
          "formatVersion": 2,
          "exportedAt": "2026-03-03T14:30:00Z",
          "exportedFrom": "DOUGLAS-FUTURE",
          "unknownField": "some value",
          "agents": [
            {
              "name": "미래 에이전트",
              "persona": "미래형 전문가",
              "isMaster": false,
              "providerType": "FutureAI",
              "preferredModel": "future-v1",
              "workingRules": null,
              "avatarBase64": null,
              "futureField": 42
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try decode(data)

        #expect(decoded.formatVersion == 2)
        #expect(decoded.agents.count == 1)
        #expect(decoded.agents[0].name == "미래 에이전트")
        #expect(decoded.agents[0].providerType == "FutureAI")
    }

    @Test("ISO8601 날짜 포맷 확인")
    func dateFormat() throws {
        let manifest = makeManifest(agents: [])
        let data = try encode(manifest)
        let json = String(data: data, encoding: .utf8)!
        // ISO8601 형식 확인 (YYYY-MM-DDTHH:MM:SS)
        #expect(json.contains("T"))
        #expect(json.contains("Z") || json.contains("+"))
    }

    // MARK: - 복수 에이전트

    @Test("복수 에이전트 라운드트립")
    func multipleAgents() throws {
        let entries = [
            AgentManifest.AgentEntry(
                name: "백엔드", persona: "백엔드 전문가", isMaster: false,
                providerType: "OpenAI", preferredModel: "gpt-4o",
                workingRules: nil, avatarBase64: nil
            ),
            AgentManifest.AgentEntry(
                name: "프론트엔드", persona: "프론트엔드 전문가", isMaster: false,
                providerType: "Anthropic", preferredModel: "claude-sonnet-4-6",
                workingRules: "- React 사용", avatarBase64: nil
            ),
            AgentManifest.AgentEntry(
                name: "DOUGLAS", persona: "AI 집사", isMaster: true,
                providerType: "Claude Code", preferredModel: "claude-sonnet-4-6",
                workingRules: nil, avatarBase64: nil
            ),
        ]
        let manifest = makeManifest(agents: entries)
        let data = try encode(manifest)
        let decoded = try decode(data)

        #expect(decoded.agents.count == 3)
        #expect(decoded.agents[0].name == "백엔드")
        #expect(decoded.agents[2].isMaster == true)
    }

    // MARK: - Helpers

    private func makeManifest(agents: [AgentManifest.AgentEntry]) -> AgentManifest {
        AgentManifest(
            formatVersion: AgentManifest.currentFormatVersion,
            exportedAt: Date(),
            exportedFrom: "DOUGLAS",
            agents: agents
        )
    }

    private func encode(_ manifest: AgentManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    private func decode(_ data: Data) throws -> AgentManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentManifest.self, from: data)
    }
}
