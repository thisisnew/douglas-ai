import Testing
import Foundation
@testable import DOUGLAS

@Suite("PromptCompositionService Tests")
struct PromptCompositionServiceTests {

    // MARK: - 규칙 없음

    @Test("규칙 없으면 persona만 반환")
    func noRules() {
        let result = PromptCompositionService.compose(
            persona: "개발자입니다.",
            workRules: [],
            legacyRules: nil
        )
        #expect(result == "개발자입니다.")
    }

    // MARK: - workRules 기반

    @Test("workRules 있으면 persona + 규칙 결합")
    func withWorkRules() {
        let rules = [WorkRule(name: "R1", summary: "s", content: .inline("코드 리뷰 필수"), isAlwaysActive: true)]
        let result = PromptCompositionService.compose(
            persona: "개발자",
            workRules: rules,
            legacyRules: nil
        )
        #expect(result.contains("개발자"))
        #expect(result.contains("코드 리뷰 필수"))
        #expect(result.contains("작업 규칙"))
    }

    @Test("activeRuleIDs로 필터링")
    func filteredRules() {
        let rules = [
            WorkRule(name: "R1", summary: "s1", content: .inline("규칙1"), isAlwaysActive: true),
            WorkRule(name: "R2", summary: "s2", content: .inline("규칙2"), isAlwaysActive: true),
        ]
        let result = PromptCompositionService.compose(
            persona: "p",
            workRules: rules,
            legacyRules: nil,
            activeRuleIDs: Set([rules[0].id])
        )
        #expect(result.contains("규칙1"))
        #expect(!result.contains("규칙2"))
    }

    @Test("빈 activeRuleIDs → persona만")
    func emptyActiveRuleIDs() {
        let rules = [WorkRule(name: "R1", summary: "s", content: .inline("규칙"), isAlwaysActive: true)]
        let result = PromptCompositionService.compose(
            persona: "p",
            workRules: rules,
            legacyRules: nil,
            activeRuleIDs: Set()
        )
        #expect(result == "p")
    }

    @Test("한국어 규칙 → 언어 강제 접미사")
    func koreanSuffix() {
        let rules = [WorkRule(name: "R", summary: "s", content: .inline("한국어로 작성"), isAlwaysActive: true)]
        let result = PromptCompositionService.compose(
            persona: "p",
            workRules: rules,
            legacyRules: nil
        )
        #expect(result.contains("반드시 한국어로 응답"))
    }

    @Test("한국어 없으면 접미사 없음")
    func noKoreanSuffix() {
        let rules = [WorkRule(name: "R", summary: "s", content: .inline("Write in English"), isAlwaysActive: true)]
        let result = PromptCompositionService.compose(
            persona: "p",
            workRules: rules,
            legacyRules: nil
        )
        #expect(!result.contains("반드시 한국어로 응답"))
    }

    // MARK: - Agent 위임 호환

    @Test("Agent.resolvedSystemPrompt는 PromptCompositionService 결과와 동일")
    func agentDelegation() {
        let rules = [WorkRule(name: "R", summary: "s", content: .inline("규칙 내용"), isAlwaysActive: true)]
        let agent = Agent(name: "T", persona: "페르소나", providerName: "P", modelName: "M", workRules: rules)
        let direct = PromptCompositionService.compose(
            persona: agent.persona,
            workRules: agent.workRules,
            legacyRules: agent.workingRules
        )
        #expect(agent.resolvedSystemPrompt == direct)
    }

    @Test("Agent.resolvedSystemPrompt(activeRuleIDs:)도 동일 위임")
    func agentDelegationFiltered() {
        let rules = [
            WorkRule(name: "R1", summary: "s1", content: .inline("A"), isAlwaysActive: true),
            WorkRule(name: "R2", summary: "s2", content: .inline("B"), isAlwaysActive: true),
        ]
        let agent = Agent(name: "T", persona: "p", providerName: "P", modelName: "M", workRules: rules)
        let ids = Set([rules[0].id])
        let direct = PromptCompositionService.compose(
            persona: agent.persona,
            workRules: agent.workRules,
            legacyRules: agent.workingRules,
            activeRuleIDs: ids
        )
        #expect(agent.resolvedSystemPrompt(activeRuleIDs: ids) == direct)
    }
}
