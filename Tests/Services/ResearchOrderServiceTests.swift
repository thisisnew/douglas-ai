import Testing
import Foundation
@testable import DOUGLAS

@Suite("ResearchOrderService Tests")
struct ResearchOrderServiceTests {

    // MARK: - heuristicOrder

    @Test("heuristicOrder — 프론트엔드 에이전트가 먼저 배치")
    func heuristicOrder_frontendFirst() {
        let be = makeTestAgent(name: "백엔드 개발자")
        let fe = makeTestAgent(name: "프론트엔드 개발자")
        let result = ResearchOrderService.heuristicOrder(agents: [be, fe])
        #expect(result[0].name == "프론트엔드 개발자")
        #expect(result[1].name == "백엔드 개발자")
    }

    @Test("heuristicOrder — 프론트엔드 없으면 원래 순서 유지")
    func heuristicOrder_noFrontend_keepOrder() {
        let be1 = makeTestAgent(name: "백엔드 개발자")
        let be2 = makeTestAgent(name: "DBA")
        let result = ResearchOrderService.heuristicOrder(agents: [be1, be2])
        #expect(result[0].name == "백엔드 개발자")
        #expect(result[1].name == "DBA")
    }

    @Test("heuristicOrder — 에이전트 1명이면 그대로 반환")
    func heuristicOrder_singleAgent() {
        let agent = makeTestAgent(name: "백엔드 개발자")
        let result = ResearchOrderService.heuristicOrder(agents: [agent])
        #expect(result.count == 1)
        #expect(result[0].name == "백엔드 개발자")
    }

    @Test("heuristicOrder — 에이전트 3명 안정 정렬 (FE → 나머지 원래 순서)")
    func heuristicOrder_threeAgents_stableSort() {
        let be = makeTestAgent(name: "백엔드 개발자")
        let fe = makeTestAgent(name: "프론트엔드 개발자")
        let qa = makeTestAgent(name: "QA 엔지니어")
        let result = ResearchOrderService.heuristicOrder(agents: [be, fe, qa])
        #expect(result[0].name == "프론트엔드 개발자")
        // 나머지는 원래 순서 유지: 백엔드 → QA
        #expect(result[1].name == "백엔드 개발자")
        #expect(result[2].name == "QA 엔지니어")
    }

    // MARK: - isFrontendAgent

    @Test("isFrontendAgent — '프론트엔드 개발자' → true")
    func isFrontendAgent_korean() {
        #expect(ResearchOrderService.isFrontendAgent("프론트엔드 개발자") == true)
    }

    @Test("isFrontendAgent — 'Frontend Developer' → true")
    func isFrontendAgent_english() {
        #expect(ResearchOrderService.isFrontendAgent("Frontend Developer") == true)
    }

    @Test("isFrontendAgent — '백엔드 개발자' → false")
    func isFrontendAgent_backend() {
        #expect(ResearchOrderService.isFrontendAgent("백엔드 개발자") == false)
    }

    @Test("isFrontendAgent — 'UI 디자이너' → true")
    func isFrontendAgent_ui() {
        #expect(ResearchOrderService.isFrontendAgent("UI 디자이너") == true)
    }

    // MARK: - determineOrder (LLM)

    @Test("determineOrder — MockProvider JSON 응답 → 올바른 순서 반환")
    func determineOrder_llmSuccess() async throws {
        let fe = makeTestAgent(name: "프론트엔드 개발자", providerName: "Mock")
        let be = makeTestAgent(name: "백엔드 개발자", providerName: "Mock")

        let mockProvider = MockAIProvider()
        mockProvider.sendMessageResult = .success("""
        {"order": ["백엔드 개발자", "프론트엔드 개발자"], "reason": "DB 스키마를 먼저 확인해야 합니다"}
        """)

        let result = await ResearchOrderService.determineOrder(
            task: "DB 스키마 확인하고 화면 설계해줘",
            agents: [fe, be],
            provider: mockProvider,
            model: "test-model"
        )
        #expect(result[0].name == "백엔드 개발자")
        #expect(result[1].name == "프론트엔드 개발자")
    }

    @Test("determineOrder — LLM 실패 시 heuristicOrder 폴백")
    func determineOrder_llmFailure_fallback() async throws {
        let be = makeTestAgent(name: "백엔드 개발자", providerName: "Mock")
        let fe = makeTestAgent(name: "프론트엔드 개발자", providerName: "Mock")

        let mockProvider = MockAIProvider()
        mockProvider.sendMessageResult = .failure(AIProviderError.networkError("timeout"))

        let result = await ResearchOrderService.determineOrder(
            task: "API 찾고 쿼리 알려줘",
            agents: [be, fe],
            provider: mockProvider,
            model: "test-model"
        )
        // 휴리스틱 폴백: 프론트엔드 먼저
        #expect(result[0].name == "프론트엔드 개발자")
        #expect(result[1].name == "백엔드 개발자")
    }
}
