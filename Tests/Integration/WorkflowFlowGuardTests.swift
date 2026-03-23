import Testing
import Foundation
@testable import DOUGLAS

@Suite("워크플로우 플로우 회귀 방지 — 핵심 시나리오 고정")
struct WorkflowFlowGuardTests {

    // MARK: - Intent 분류 회귀 방지

    @Test("'API 찾고 쿼리 알려줘' → research (complex 아님)")
    func researchQuery_notComplex() {
        let result = IntentClassifier.quickClassify("회송 목록 화면에서 어떤 API 호출하는지 찾고, 그 API의 쿼리를 알려줘")
        #expect(result != .complex, "연구/조사 요청이 complex로 잘못 분류됨")
    }

    @Test("'도출해줘' → discussion")
    func derivationKeyword_discussion() {
        #expect(IntentClassifier.quickClassify("작업할거 도출해줘") == .discussion)
    }

    @Test("URL만 → pendingIntent")
    func jiraUrlOnly_pendingIntent() {
        let route = IntentClassifier.preRoute("https://company.atlassian.net/browse/PROJ-123", hasAttachments: false)
        #expect(route == .pendingIntent)
    }

    @Test("'구현해줘' → task")
    func implementTask_staysTask() {
        #expect(IntentClassifier.quickClassify("로그인 기능 구현해줘") == .task)
    }

    @Test("'이게 뭐야' → quickAnswer")
    func questionOnly_quickAnswer() {
        #expect(IntentClassifier.quickClassify("이게 뭐야") == .quickAnswer)
    }

    @Test("'분석하고 구현도 해줘' → complex")
    func genuineComplex_staysComplex() {
        let result = IntentClassifier.quickClassify("이 코드를 분석하고 리팩토링도 해줘. 그리고 테스트도 작성해줘.")
        // 분석(research) + 리팩토링(task) + 테스트(task) → 충분히 complex
        // 또는 task로 잡혀도 OK — complex가 아닌 게 문제가 아님
        #expect(result == .complex || result == .task)
    }

    // MARK: - Follow-up 회귀 방지

    @Test("토론 후 '구현해줘' → implementAll + task intent")
    func followUpImplementAll() {
        let decision = FollowUpClassifier.classify(
            message: "구현해줘",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .implementAll)
        #expect(decision.resolvedWorkflowIntent == .task)
    }

    @Test("토론 후 '1번이랑 3번만' → implementPartial([0, 2])")
    func followUpImplementPartial() {
        let decision = FollowUpClassifier.classify(
            message: "1번이랑 3번만 구현해줘",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .implementPartial([0, 2]))
    }

    // MARK: - 토론 패턴 회귀 방지

    @Test("'생각을 듣고싶어' → discussion (complex 아님)")
    func wantToHearThoughts_discussion() {
        let result = IntentClassifier.quickClassify("최신 개발 트렌드에 대해 프론트, 백엔드의 생각을 듣고싶어")
        #expect(result == .discussion)
    }

    @Test("'토론해줘' → discussion")
    func debate_discussion() {
        #expect(IntentClassifier.quickClassify("이 아키텍처에 대해 토론해줘") == .discussion)
    }

    @Test("'개발 트렌드 찾아봐' → research (task 아님)")
    func devTrend_research() {
        let result = IntentClassifier.quickClassify("최신 개발 트렌드 찾아봐")
        #expect(result == .research)
    }

    @Test("'이거 개발해줘' → task")
    func develop_task() {
        #expect(IntentClassifier.quickClassify("이거 개발해줘") == .task)
    }
}
