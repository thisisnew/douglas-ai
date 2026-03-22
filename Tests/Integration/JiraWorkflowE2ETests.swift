import Testing
import Foundation
@testable import DOUGLAS

@Suite("Jira URL → 에이전트 할당 → 작업 도출 → 구현 E2E")
struct JiraWorkflowE2ETests {

    // MARK: - Step 1: Jira URL + "도출" → discussion intent

    @Test("Jira URL + '작업 도출해줘' → discussion intent")
    func jiraURL_plusDerive_classifiesAsDiscussion() {
        let input = "https://company.atlassian.net/browse/PROJ-123 작업 도출해줘"
        let intent = IntentClassifier.quickClassify(input)
        #expect(intent == .discussion)
    }

    // MARK: - Step 2: 티켓 내용 → 도메인 힌트

    @Test("Jira 티켓 내용 → 백엔드 + 프론트엔드 도메인 힌트 감지")
    func jiraTicketContent_detectsDomainHints() {
        let hints = DomainHintDetector.detect(
            summary: "API 엔드포인트 추가 + 결과 화면 표시",
            description: "백엔드 API를 호출하여 프론트 화면에 렌더링"
        )
        let domains = hints.map { $0.domain }
        #expect(domains.contains("백엔드"))
        #expect(domains.contains("프론트엔드"))

        // IntakeData에 힌트가 포함되는지 확인
        let intakeData = IntakeData(
            sourceType: .jira,
            rawInput: "https://company.atlassian.net/browse/PROJ-123",
            jiraKeys: ["PROJ-123"],
            jiraDataList: [
                JiraTicketSummary(
                    key: "PROJ-123",
                    summary: "API 엔드포인트 추가 + 결과 화면 표시",
                    issueType: "Story",
                    status: "To Do",
                    description: "백엔드 API를 호출하여 프론트 화면에 렌더링"
                )
            ]
        )
        let contextString = intakeData.asClarifyContextString()
        #expect(contextString.contains("감지된 관련 도메인:"))
        #expect(contextString.contains("백엔드"))
    }

    // MARK: - Step 3: 도메인 힌트 → 에이전트 매칭 부스트

    @Test("도메인 힌트로 매칭 에이전트의 confidence 상승")
    func domainHints_boostCorrectAgents() {
        // skillTags가 roleName 동의어 확장과 완전히 겹치지 않도록 설정
        let backendDev = Agent(
            name: "서버 엔지니어", persona: "Spring/JPA 전문가",
            providerName: "test", modelName: "test",
            skillTags: ["spring", "jpa", "api", "rest"], workModes: [.execute, .create]
        )
        let unrelated = Agent(
            name: "마케터", persona: "마케팅 전문가",
            providerName: "test", modelName: "test",
            skillTags: ["마케팅", "광고"], workModes: [.create]
        )

        let hints = DomainHintDetector.detect(
            summary: "API 엔드포인트 추가",
            description: "REST API 구현 + Spring 설정"
        )

        let (matched, conf) = AgentMatcher.matchByTags(
            roleName: "서버 엔지니어",
            agents: [backendDev, unrelated],
            excluding: [],
            domainHints: hints
        )
        let (_, confNoHint) = AgentMatcher.matchByTags(
            roleName: "서버 엔지니어",
            agents: [backendDev, unrelated],
            excluding: []
        )

        // 힌트 있을 때 서버 엔지니어 선택 + confidence 상승
        #expect(matched?.id == backendDev.id)
        #expect(conf > confNoHint)
    }

    // MARK: - Step 4: 후속 "구현해줘" → implementAll

    @Test("토론 완료 후 '구현해줘' → implementAll + 올바른 컨텍스트 유지")
    func followUp_implementAll_correctRoutingAndContext() {
        let decision = FollowUpClassifier.classify(
            message: "구현해줘",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .implementAll)
        #expect(decision.resolvedWorkflowIntent == .task)
        #expect(decision.needsPlan == true)
        // understand 스킵 (이미 파악됨)
        #expect(decision.skipPhases.contains(.understand))
        // assemble은 스킵하지 않음 (토론→구현 에이전트 재평가 필요)
        #expect(!decision.skipPhases.contains(.assemble))
        // 토론 결과 유지
        #expect(decision.contextPolicy.keepBriefing == true)
        #expect(decision.contextPolicy.keepActionItems == true)
    }

    // MARK: - Step 5: 전체 파이프라인 연결 검증

    @Test("전체 플로우: Jira URL → intent → 도메인 → 에이전트 → 후속 구현")
    func fullPipeline_jiraToDiscussionToImplement() {
        // 1) Jira URL + "도출" → discussion intent
        let userInput = "https://company.atlassian.net/browse/IBS-500 이 티켓에서 작업 도출해줘"
        let intent = IntentClassifier.quickClassify(userInput)
        #expect(intent == .discussion)

        // 2) 티켓 내용으로 도메인 힌트 감지
        let ticketSummary = "결제 API 리팩토링 + 결제 화면 UI 개선"
        let ticketDesc = "백엔드 REST API 구조 변경 + 프론트엔드 컴포넌트 수정"
        let hints = DomainHintDetector.detect(summary: ticketSummary, description: ticketDesc)
        #expect(!hints.isEmpty)
        let detectedDomains = hints.map { $0.domain }
        #expect(detectedDomains.contains("백엔드"))
        #expect(detectedDomains.contains("프론트엔드"))

        // 3) 도메인 힌트로 에이전트 매칭 — 백엔드 에이전트 부스트 확인
        let backendDev = Agent(
            name: "백엔드 개발자", persona: "서버/API 전문가",
            providerName: "test", modelName: "test",
            skillTags: ["backend", "api", "서버", "rest"], workModes: [.execute, .create]
        )
        let designAgent = Agent(
            name: "디자이너", persona: "UX 전문가",
            providerName: "test", modelName: "test",
            skillTags: ["design", "ux", "피그마"], workModes: [.create]
        )

        let (agent, _) = AgentMatcher.matchByTags(
            roleName: "API 전문가",
            agents: [backendDev, designAgent],
            excluding: [],
            domainHints: hints
        )
        #expect(agent?.id == backendDev.id)

        // 4) 토론 완료 후 "구현해줘" → task로 전환
        let followUp = FollowUpClassifier.classify(
            message: "이제 구현하자",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(followUp.intent == .implementAll)
        #expect(followUp.resolvedWorkflowIntent == .task)
        #expect(followUp.contextPolicy.keepActionItems == true)
        #expect(followUp.contextPolicy.keepBriefing == true)

        // 5) 부분 구현도 동작 확인
        let partial = FollowUpClassifier.classify(
            message: "1번이랑 3번만 구현해줘",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(partial.intent == .implementPartial([0, 2]))
    }

    // MARK: - 비-Jira 텍스트에서 도메인 힌트 감지

    @Test("'화면'과 'API' 키워드 → 프론트엔드 + 백엔드 도메인 감지")
    func nonJiraText_withScreenKeyword_detectsFrontend() {
        let text = "회송 목록 화면에서 어떤 API 호출하는지 찾고, 그 API의 쿼리를 알려줘"
        let hints = DomainHintDetector.detect(text: text)
        let domains = hints.map { $0.domain }
        #expect(domains.contains("프론트엔드"))  // "화면"
        #expect(domains.contains("백엔드"))      // "api", "쿼리"
    }

    @Test("텍스트 힌트가 백엔드 + 프론트엔드 에이전트 모두 부스트")
    func textHints_boostBothBackendAndFrontend() {
        let backendDev = Agent(
            name: "서버 엔지니어", persona: "API 전문가",
            providerName: "test", modelName: "test",
            skillTags: ["spring", "api", "쿼리"], workModes: [.execute, .create]
        )
        let frontendDev = Agent(
            name: "웹 엔지니어", persona: "화면 전문가",
            providerName: "test", modelName: "test",
            skillTags: ["react", "화면", "css"], workModes: [.create]
        )

        let hints = DomainHintDetector.detect(text: "화면에서 API 호출 확인")

        // 백엔드 에이전트 — 힌트 부스트 확인
        let (_, backConf) = AgentMatcher.matchByTags(
            roleName: "서버 엔지니어", agents: [backendDev], excluding: [],
            domainHints: hints
        )
        let (_, backNoHint) = AgentMatcher.matchByTags(
            roleName: "서버 엔지니어", agents: [backendDev], excluding: []
        )
        #expect(backConf > backNoHint)

        // 프론트엔드 에이전트 — 힌트 부스트 확인
        let (_, frontConf) = AgentMatcher.matchByTags(
            roleName: "웹 엔지니어", agents: [frontendDev], excluding: [],
            domainHints: hints
        )
        let (_, frontNoHint) = AgentMatcher.matchByTags(
            roleName: "웹 엔지니어", agents: [frontendDev], excluding: []
        )
        #expect(frontConf > frontNoHint)
    }

    // MARK: - Clarify 응답에서 intent 재분류

    @Test("Clarify 응답 '확인해서 작업할거 도출해줘' → discussion")
    func clarifyResponse_derivation_classifiesAsDiscussion() {
        // Clarify 응답은 URL 없이 텍스트만 옴
        let clarifyAnswer = "확인해서 작업할거 도출해줘"
        let intent = IntentClassifier.quickClassify(clarifyAnswer)
        #expect(intent == .discussion)
    }
}
