import Testing
import Foundation
@testable import DOUGLAS

@Suite("PositionInferenceService Tests")
struct PositionInferenceServiceTests {

    // MARK: - workModes 기반

    @Test("plan → planner, architect")
    func planModes() {
        let positions = PositionInferenceService.inferPositions(workModes: [.plan], persona: "일반")
        #expect(positions.contains(.planner))
        #expect(positions.contains(.architect))
    }

    @Test("create → implementer, writer")
    func createModes() {
        let positions = PositionInferenceService.inferPositions(workModes: [.create], persona: "일반")
        #expect(positions.contains(.implementer))
        #expect(positions.contains(.writer))
    }

    @Test("execute → implementer")
    func executeModes() {
        let positions = PositionInferenceService.inferPositions(workModes: [.execute], persona: "일반")
        #expect(positions.contains(.implementer))
    }

    @Test("review → reviewer, auditor")
    func reviewModes() {
        let positions = PositionInferenceService.inferPositions(workModes: [.review], persona: "일반")
        #expect(positions.contains(.reviewer))
        #expect(positions.contains(.auditor))
    }

    @Test("research → researcher, analyst")
    func researchModes() {
        let positions = PositionInferenceService.inferPositions(workModes: [.research], persona: "일반")
        #expect(positions.contains(.researcher))
        #expect(positions.contains(.analyst))
    }

    @Test("빈 workModes + 일반 persona → 빈 결과")
    func emptyModes() {
        let positions = PositionInferenceService.inferPositions(workModes: [], persona: "일반")
        #expect(positions.isEmpty)
    }

    // MARK: - persona 키워드 보정

    @Test("persona '번역' → translator")
    func personaTranslator() {
        let positions = PositionInferenceService.inferPositions(workModes: [.create], persona: "다국어 번역 전문가")
        #expect(positions.contains(.translator))
    }

    @Test("persona 'QA' → tester")
    func personaQA() {
        let positions = PositionInferenceService.inferPositions(workModes: [.review], persona: "QA 및 테스트 자동화")
        #expect(positions.contains(.tester))
    }

    @Test("persona '법률' → auditor")
    func personaLegal() {
        let positions = PositionInferenceService.inferPositions(workModes: [.review], persona: "법률 자문 및 컴플라이언스")
        #expect(positions.contains(.auditor))
    }

    @Test("persona '기획' → coordinator")
    func personaPM() {
        let positions = PositionInferenceService.inferPositions(workModes: [.plan], persona: "프로젝트 기획 및 관리")
        #expect(positions.contains(.coordinator))
    }

    @Test("persona '아키텍처' → architect")
    func personaArchitect() {
        let positions = PositionInferenceService.inferPositions(workModes: [.plan], persona: "시스템 아키텍처 설계")
        #expect(positions.contains(.architect))
    }

    @Test("persona '데이터 분석' → analyst")
    func personaAnalyst() {
        let positions = PositionInferenceService.inferPositions(workModes: [.research], persona: "데이터 분석 및 시각화")
        #expect(positions.contains(.analyst))
    }

    // MARK: - Agent.goodPositions 위임 확인

    @Test("Agent.goodPositions는 PositionInferenceService 결과와 동일")
    func agentDelegation() {
        var agent = Agent(name: "테스트", persona: "QA 테스트", providerName: "P", modelName: "M")
        agent.workModes = [.review]
        let direct = PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona)
        #expect(agent.goodPositions == direct)
    }
}
