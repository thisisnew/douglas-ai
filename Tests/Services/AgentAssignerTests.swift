import Testing
import Foundation
@testable import DOUGLAS

@Suite("AgentAssigner Tests")
struct AgentAssignerTests {

    let backendID = UUID()
    let frontendID = UUID()
    let qaID = UUID()

    var agents: [(id: UUID, name: String)] {
        [(backendID, "백엔드 개발자"), (frontendID, "프론트엔드 개발자"), (qaID, "QA 전문가")]
    }

    @Test("완전 일치 매칭")
    func exactMatch() {
        let result = AgentAssigner.resolve(name: "백엔드 개발자", stepText: "", agents: agents)
        #expect(result == backendID)
    }

    @Test("대소문자 무시 매칭")
    func caseInsensitive() {
        let agents: [(id: UUID, name: String)] = [(backendID, "Backend Dev")]
        let result = AgentAssigner.resolve(name: "backend dev", stepText: "", agents: agents)
        #expect(result == backendID)
    }

    @Test("부분 매칭 폴백")
    func partialMatch() {
        let result = AgentAssigner.resolve(name: "백엔드", stepText: "", agents: agents)
        #expect(result == backendID)
    }

    @Test("agentResponsibilities 역할 매칭")
    func responsibilitiesMatch() {
        let responsibilities = ["백엔드 개발자": "API 설계 및 서버 로직"]
        let result = AgentAssigner.resolve(
            name: "API",
            stepText: "",
            agents: agents,
            responsibilities: responsibilities
        )
        #expect(result == backendID)
    }

    @Test("이름 없음 + stepText로 매칭")
    func stepTextMatch() {
        let responsibilities = ["QA 전문가": "테스트 작성 및 품질 검증"]
        let result = AgentAssigner.resolve(
            name: nil,
            stepText: "통합 테스트 작성",
            agents: agents,
            responsibilities: responsibilities
        )
        #expect(result == qaID)
    }

    @Test("매칭 실패 → nil")
    func noMatch() {
        let result = AgentAssigner.resolve(name: "데이터 엔지니어", stepText: "ML 파이프라인", agents: agents)
        #expect(result == nil)
    }

    @Test("빈 에이전트 목록 → nil")
    func emptyAgents() {
        let result = AgentAssigner.resolve(name: "백엔드", stepText: "", agents: [])
        #expect(result == nil)
    }
}
