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

    // MARK: - Research Synthesis Prompt

    @Test("researchSynthesisPrompt — 직접 답변 지시 포함")
    func researchSynthesisPrompt_directAnswer() {
        let prompt = PromptCompositionService.researchSynthesisPrompt()
        #expect(prompt.contains("사용자의 질문에 직접 답변"))
    }

    @Test("researchSynthesisPrompt — 재정리 방지 지시 포함")
    func researchSynthesisPrompt_antiReorganize() {
        let prompt = PromptCompositionService.researchSynthesisPrompt()
        #expect(prompt.contains("재정리"))
    }

    @Test("researchSynthesisPrompt — 교차 참조 지시 포함")
    func researchSynthesisPrompt_crossReference() {
        let prompt = PromptCompositionService.researchSynthesisPrompt()
        #expect(prompt.contains("교차") || prompt.contains("연결점"))
    }

    @Test("researchSynthesisPrompt — 코드 원문 유지 규칙 포함")
    func researchSynthesisPrompt_codePreservation() {
        let prompt = PromptCompositionService.researchSynthesisPrompt()
        #expect(prompt.contains("원문 그대로 유지"))
    }

    // MARK: - Research Follow-Up Prompt

    @Test("researchFollowUpPrompt — 한국어 요구 포함")
    func followUpPrompt_korean() {
        let prompt = PromptCompositionService.researchFollowUpPrompt()
        #expect(prompt.contains("한국어"))
    }

    @Test("researchFollowUpPrompt — '추가 발견 없음' 안내 포함")
    func followUpPrompt_noAdditional() {
        let prompt = PromptCompositionService.researchFollowUpPrompt()
        #expect(prompt.contains("추가 발견 없음"))
    }

    @Test("researchFollowUpPrompt — 도구 사용 허용 지시 포함")
    func followUpPrompt_toolUsage() {
        let prompt = PromptCompositionService.researchFollowUpPrompt()
        #expect(prompt.contains("도구"))
    }

    @Test("researchFollowUpPrompt — 중복 생략 지시 포함")
    func followUpPrompt_noRepeat() {
        let prompt = PromptCompositionService.researchFollowUpPrompt()
        #expect(prompt.contains("중복") || prompt.contains("생략"))
    }
}
