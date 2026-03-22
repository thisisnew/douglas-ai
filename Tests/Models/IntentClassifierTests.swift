import Testing
import Foundation
@testable import DOUGLAS

@Suite("IntentClassifier Tests")
struct IntentClassifierTests {

    // MARK: - quickClassify: quickAnswer

    @Test("짧은 질문 → quickAnswer")
    func shortQuestion() {
        #expect(IntentClassifier.quickClassify("이게 뭐야") == .quickAnswer)
    }

    @Test("짧은 번역 → quickAnswer (단순 변환)")
    func shortTranslation() {
        #expect(IntentClassifier.quickClassify("이거 영어로 번역해줘") == .quickAnswer)
    }

    @Test("설명 요청 — '알려줘' 단독은 LLM 폴백 (threshold 4 미달)")
    func explanation_allyeojwo_needsLLM() {
        // "알려"=3 < threshold 4 → nil (LLM 폴백으로 처리)
        #expect(IntentClassifier.quickClassify("알려줘") == nil)
    }

    @Test("설명 요청 — '설명해줘'는 quickAnswer")
    func explanation_seolmyeong() {
        // "설명"=4 ≥ threshold 4
        #expect(IntentClassifier.quickClassify("설명해줘") == .quickAnswer)
    }

    @Test("의미 질문 → quickAnswer")
    func meaningQuestion() {
        #expect(IntentClassifier.quickClassify("뜻이 뭐야") == .quickAnswer)
    }

    // MARK: - quickClassify: research (Phase 3 신규)

    @Test("조사 → research")
    func researchDirect() {
        #expect(IntentClassifier.quickClassify("이 주제 조사해줘") == .research)
    }

    @Test("리서치 → research")
    func researchKeyword() {
        #expect(IntentClassifier.quickClassify("리서치해줘") == .research)
    }

    @Test("서베이 → research")
    func surveyKeyword() {
        #expect(IntentClassifier.quickClassify("경쟁사 서베이 해줘") == .research)
    }

    // MARK: - quickClassify: documentation (Phase 3 신규)

    @Test("기획서 작성 → documentation")
    func documentWriting() {
        #expect(IntentClassifier.quickClassify("기획서 작성해줘") == .documentation)
    }

    @Test("보고서 정리 → documentation")
    func reportOrganize() {
        #expect(IntentClassifier.quickClassify("보고서로 정리해줘") == .documentation)
    }

    @Test("PRD → documentation")
    func prd() {
        #expect(IntentClassifier.quickClassify("PRD 작성해줘") == .documentation)
    }

    @Test("문서화 → documentation")
    func documentationKeyword() {
        #expect(IntentClassifier.quickClassify("이걸 문서화해줘") == .documentation)
    }

    @Test("제안서 → documentation")
    func proposalKeyword() {
        #expect(IntentClassifier.quickClassify("제안서 만들어줘") == .documentation)
    }

    // MARK: - quickClassify: task (구현)

    @Test("짧은 요약 → quickAnswer (단순 변환)")
    func summarize() {
        #expect(IntentClassifier.quickClassify("요약해줘") == WorkflowIntent.quickAnswer)
    }

    @Test("요약+pdf 복합 → documentation (문서 포맷 명시)")
    func summarizeWithPdf() {
        let result = IntentClassifier.quickClassify("요약해서 pdf로 바꿔줘")
        #expect(result == WorkflowIntent.documentation || result == WorkflowIntent.complex)
    }

    @Test("요약+pdf 만들어줘 → documentation (문서 포맷 명시)")
    func summarizePdfMake() {
        let result = IntentClassifier.quickClassify("요약해서 pdf로 만들어줘")
        #expect(result == WorkflowIntent.documentation || result == WorkflowIntent.complex)
    }

    @Test("분석 요청 → LLM 폴백 (task에서 '분석' 제거됨, research/discussion 영역)")
    func analysis() {
        // "분석"은 task에서 제거 → "이거 분석해봐"는 nil(LLM이 context 기반 판단)
        #expect(IntentClassifier.quickClassify("이거 분석해봐") == nil)
    }

    @Test("브레인스토밍 → discussion")
    func brainstorm() {
        #expect(IntentClassifier.quickClassify("브레인스토밍 해보자") == WorkflowIntent.discussion)
    }

    @Test("변환 → documentation (문서 포맷 명시)")
    func convert() {
        let result = IntentClassifier.quickClassify("워드로 변환해줘")
        #expect(result == WorkflowIntent.documentation || result == WorkflowIntent.complex)
    }

    @Test("코딩 → task")
    func coding() {
        #expect(IntentClassifier.quickClassify("코딩해줘") == WorkflowIntent.task)
    }

    @Test("구현 → task")
    func implement() {
        #expect(IntentClassifier.quickClassify("로그인 기능 구현해줘") == WorkflowIntent.task)
    }

    @Test("버그 → task")
    func bugFix() {
        #expect(IntentClassifier.quickClassify("이 버그 수정해줘") == WorkflowIntent.task)
    }

    @Test("리팩토링 → task")
    func refactor() {
        #expect(IntentClassifier.quickClassify("이 코드 리팩토링해줘") == WorkflowIntent.task)
    }

    @Test("pdf로 만들어줘 → documentation (문서 포맷 명시)")
    func pdfContextOverridesAction() {
        let result = IntentClassifier.quickClassify("이걸 pdf로 만들어줘")
        #expect(result == WorkflowIntent.documentation || result == WorkflowIntent.complex)
    }

    @Test("문서 만들어줘 → task (문서 단독으로는 documentation 임계값 미달)")
    func documentMake() {
        let result = IntentClassifier.quickClassify("문서 만들어줘")
        #expect(result == WorkflowIntent.task)
    }

    @Test("앱 만들어줘 → task")
    func appMake() {
        let result = IntentClassifier.quickClassify("앱 만들어줘")
        #expect(result == WorkflowIntent.task)
    }

    @Test("번역 + 문서화 복합 → complex (번역=task + 문서화=documentation)")
    func longTranslation() {
        #expect(IntentClassifier.quickClassify("이 프로젝트의 README를 한국어로 번역하고 기술 용어집도 포함해서 문서화해줘") == .complex)
    }

    // MARK: - nil 반환 케이스

    @Test("Jira URL만 → nil")
    func jiraUrlOnly() {
        #expect(IntentClassifier.quickClassify("https://team.atlassian.net/browse/PROJ-123") == nil)
    }

    @Test("빈 문자열 → nil")
    func emptyString() {
        #expect(IntentClassifier.quickClassify("") == nil)
    }

    // MARK: - 한국어 어미 변형 커버

    @Test("요약해서 → task (어간 '요약' 매칭)")
    func koreanStemSummarize() {
        #expect(IntentClassifier.quickClassify("이 파일 요약해서 보내줘") == WorkflowIntent.task)
    }

    @Test("pdf로 바꿔봐 → documentation (문서 포맷 명시)")
    func koreanStemConvert() {
        let result = IntentClassifier.quickClassify("pdf로 바꿔봐")
        #expect(result == WorkflowIntent.documentation || result == WorkflowIntent.complex)
    }

    @Test("classified task 파일 포함")
    func preRouteTaskWithFile() {
        let route = IntentClassifier.preRoute("이거 분석해줘", hasAttachments: true)
        #expect(route == .classified(WorkflowIntent.task))
    }

    // MARK: - PreIntentRoute

    @Test("빈 텍스트 + 파일 없음 → empty")
    func preRouteEmpty() {
        #expect(IntentClassifier.preRoute("", hasAttachments: false) == .empty)
    }

    @Test("빈 텍스트 + 파일 있음 → fileOnly")
    func preRouteFileOnly() {
        #expect(IntentClassifier.preRoute("", hasAttachments: true) == .fileOnly)
        #expect(IntentClassifier.preRoute("  ", hasAttachments: true) == .fileOnly)
    }

    @Test("에이전트 불러와 → command")
    func preRouteCommand() {
        let route = IntentClassifier.preRoute("에이전트 불러와", hasAttachments: false)
        #expect(route == .command(.summonAgent(name: nil)))
    }

    @Test("QA에이전트 불러와 → command with name")
    func preRouteCommandWithName() {
        let route = IntentClassifier.preRoute("QA에이전트 불러와", hasAttachments: false)
        #expect(route == .command(.summonAgent(name: "qa")))
    }

    @Test("일반 질문 → classified quickAnswer")
    func preRouteQuickAnswer() {
        let route = IntentClassifier.preRoute("JWT가 뭐야?", hasAttachments: false)
        #expect(route == .classified(.quickAnswer))
    }

    @Test("작업 요청 → classified task")
    func preRouteTask() {
        let route = IntentClassifier.preRoute("이 코드 리팩토링해줘", hasAttachments: false)
        #expect(route == .classified(.task))
    }

    @Test("키워드 미매칭 → task 기본값 (ambiguous 없음)")
    func preRouteDefaultTask() {
        // "취합해줘" 같은 키워드 사전에 없는 입력도 task로 분류
        let route = IntentClassifier.preRoute("pr 링크좀 레포지토리별로 취합해줘", hasAttachments: false)
        #expect(route == .classified(.task))
    }

    @Test("Jira URL + 작업 텍스트 → classified task")
    func preRouteJiraURLsWithTask() {
        let input = """
        https://company.atlassian.net/browse/IBS-100
        https://company.atlassian.net/browse/IBS-200
        pr 링크좀 취합해줘
        """
        let route = IntentClassifier.preRoute(input, hasAttachments: false)
        #expect(route == .classified(.task))
    }

    // MARK: - LLM parseIntent (Phase 3 신규)

    @Test("preRoute — 조사 요청 → classified research")
    func preRouteResearch() {
        let route = IntentClassifier.preRoute("이거 조사해줘", hasAttachments: false)
        #expect(route == .classified(.research))
    }

    @Test("preRoute — 문서화 요청 → classified documentation")
    func preRouteDocumentation() {
        let route = IntentClassifier.preRoute("기획서 작성해줘", hasAttachments: false)
        #expect(route == .classified(.documentation))
    }

    // MARK: - Phase 2: 부정 키워드 (개선안 A)

    @Test("토론 키워드가 task 키워드보다 우세할 때 discussion")
    func discussionWinsOverTask() {
        // "이 아키텍처에 대해 토론해줘" — 토론(4) + 아키텍처(task 4) 경쟁
        // discussion negative에 의해 task 감점 → discussion 승
        let result = IntentClassifier.quickClassify("이 아키텍처에 대해 토론해줘")
        #expect(result == .discussion)
    }

    // MARK: - URL 없이 도출/파악 키워드 → discussion

    @Test("'확인해서 작업할거 도출해줘' → discussion (Clarify 응답)")
    func derivationKeyword_noURL() {
        let result = IntentClassifier.quickClassify("확인해서 작업할거 도출해줘")
        #expect(result == .discussion)
    }

    @Test("'뭘해야 하는지 알려줘' → discussion")
    func whatToDo_discussion() {
        let result = IntentClassifier.quickClassify("이 티켓에서 뭘해야 하는지 알려줘")
        #expect(result == .discussion)
    }

    @Test("'할일 정리해줘' → discussion")
    func todoList_discussion() {
        let result = IntentClassifier.quickClassify("할일 정리해줘")
        #expect(result == .discussion)
    }

    @Test("'로그인 기능 구현해줘' → task (도출 키워드 없음)")
    func implementTask_staysTask() {
        let result = IntentClassifier.quickClassify("로그인 기능 구현해줘")
        #expect(result == .task)
    }

    @Test("'현재 상태 파악해줘' → research (파악은 research, 도출과 구분)")
    func investigate_staysResearch() {
        let result = IntentClassifier.quickClassify("현재 상태 파악해줘")
        #expect(result == .research)
    }

    @Test("'무슨 작업해야되는지 알려줘' → discussion (무슨 작업 패턴)")
    func whatWorkToDo_discussion() {
        let result = IntentClassifier.quickClassify("이거보고 무슨 작업해야되는지 알려줘")
        #expect(result == .discussion)
    }

    @Test("URL + '무슨 작업해야되는지 알려줘' → discussion")
    func urlPlusWhatWork_discussion() {
        let result = IntentClassifier.quickClassify("https://jira.company.net/browse/PROJ-1 이거보고 무슨 작업해야되는지 알려줘")
        #expect(result == .discussion)
    }

    @Test("URL만 입력 → preRoute pendingIntent")
    func urlOnly_pendingIntent() {
        let route = IntentClassifier.preRoute("https://jira.company.net/browse/PROJ-1", hasAttachments: false)
        #expect(route == .pendingIntent)
    }

    // MARK: - Phase 2: Bigram 매칭 (개선안 B)

    @Test("'작업 도출' 띄어쓰기 → discussion (bigram)")
    func bigramTaskDerivation() {
        // "작업" + "도출" 개별 토큰이 bigram "작업도출"로 결합 → discussion 매칭
        let result = IntentClassifier.quickClassify("이 티켓에서 작업 도출해줘")
        #expect(result == .discussion)
    }

    // MARK: - Phase 2: Modifier 추출 (개선안 C)

    @Test("adversarial modifier 추출")
    func extractAdversarial() {
        let mods = IntentClassifier.extractModifiers(from: "날카롭게 토론해줘")
        #expect(mods.contains(.adversarial))
    }

    @Test("outputOnly modifier 추출")
    func extractOutputOnly() {
        let mods = IntentClassifier.extractModifiers(from: "작업분해만 해줘")
        #expect(mods.contains(.outputOnly))
    }

    @Test("withExecution modifier 추출")
    func extractWithExecution() {
        let mods = IntentClassifier.extractModifiers(from: "작업분해하고 구현해줘")
        #expect(mods.contains(.withExecution))
    }

    @Test("breakdown modifier 추출")
    func extractBreakdown() {
        let mods = IntentClassifier.extractModifiers(from: "이 티켓 작업 도출해줘")
        #expect(mods.contains(.breakdown))
    }

    @Test("modifier 없는 일반 요청")
    func noModifiers() {
        let mods = IntentClassifier.extractModifiers(from: "이거 구현해줘")
        #expect(mods.isEmpty || !mods.contains(.adversarial))
    }

    @Test("classifyWithModifiers 통합")
    func classifyWithModifiersIntegration() {
        let result = IntentClassifier.classifyWithModifiers("날카롭게 토론해줘")
        #expect(result.intent == .discussion)
        #expect(result.has(.adversarial))
    }

    // MARK: - Phase 2: Jira URL + 도출 → discussion

    @Test("Jira URL + 도출 → discussion")
    func jiraUrlWithDerivation() {
        let result = IntentClassifier.quickClassify("https://team.atlassian.net/browse/PROJ-123 작업 도출해줘")
        #expect(result == .discussion)
    }

    @Test("Jira URL + 분석 → discussion")
    func jiraUrlWithAnalysis() {
        let result = IntentClassifier.quickClassify("https://team.atlassian.net/browse/IBS-3328 분석하라그래")
        #expect(result == .discussion)
    }

    @Test("Jira URL + 검토 → discussion")
    func jiraUrlWithReview() {
        let result = IntentClassifier.quickClassify("https://team.atlassian.net/browse/PROJ-123 검토해줘")
        #expect(result == .discussion)
    }

    @Test("Jira URL + 리뷰 → discussion")
    func jiraUrlWithCodeReview() {
        let result = IntentClassifier.quickClassify("https://team.atlassian.net/browse/PROJ-456 리뷰해줘")
        #expect(result == .discussion)
    }

    // MARK: - Phase 1 개선: complex 결정론적 분류

    @Test("조사+문서화 복합 → complex")
    func complexResearchAndDoc() {
        let result = IntentClassifier.quickClassify("React 현황 조사해서 기획서 만들어줘")
        #expect(result == .complex)
    }

    @Test("비교 조사+문서 정리 → complex")
    func complexCompareAndDoc() {
        let result = IntentClassifier.quickClassify("경쟁사 비교 조사하고 보고서로 정리해줘")
        #expect(result == .complex)
    }

    @Test("조사+구현 복합 → complex")
    func complexResearchAndTask() {
        let result = IntentClassifier.quickClassify("이 주제를 조사하고 코드로 구현해줘")
        #expect(result == .complex)
    }

    @Test("단일 인텐트는 complex 아님")
    func singleIntentNotComplex() {
        // 단일 intent만 threshold를 넘으면 complex가 아님
        #expect(IntentClassifier.quickClassify("이 주제 조사해줘") == .research)
        #expect(IntentClassifier.quickClassify("기획서 작성해줘") == .documentation)
        #expect(IntentClassifier.quickClassify("코딩해줘") == .task)
    }

    // MARK: - Phase 1 개선: discussion 키워드 보강

    @Test("'뭐가 나을까' → discussion")
    func discussionBetterChoice() {
        let result = IntentClassifier.quickClassify("React hooks vs Redux 뭐가 나을까")
        #expect(result == .discussion)
    }

    @Test("'고민' → discussion")
    func discussionWorry() {
        let result = IntentClassifier.quickClassify("이 방식에 대해 고민이 돼")
        #expect(result == .discussion)
    }

    @Test("'낫지' → discussion")
    func discussionWhichBetter() {
        let result = IntentClassifier.quickClassify("어떤 게 낫지?")
        #expect(result == .discussion)
    }

    @Test("'괜찮을까' → discussion")
    func discussionIsItOk() {
        let result = IntentClassifier.quickClassify("이렇게 하면 괜찮을까 의견 좀 줘")
        #expect(result == .discussion)
    }

    // MARK: - Phase 1 개선: research 우선순위

    @Test("비교+정리 → research (task에 밀리지 않음)")
    func researchCompareOrganize() {
        let result = IntentClassifier.quickClassify("React 라이브러리들 비교해서 정리해줘")
        #expect(result == .research)
    }

    @Test("비교 분석 → research")
    func researchCompareAnalysis() {
        let result = IntentClassifier.quickClassify("프레임워크 비교 분석해줘")
        #expect(result == .research)
    }

    // MARK: - Phase 1 개선: withExecution modifier가 requiredPhases에 반영

    @Test("withExecution modifier → discussion에 build/review 추가")
    func withExecutionAddsPhases() {
        let basePhases = WorkflowIntent.discussion.requiredPhases
        #expect(!basePhases.contains(.build))
        #expect(!basePhases.contains(.review))

        let extendedPhases = WorkflowIntent.discussion.requiredPhases(with: [.withExecution])
        #expect(extendedPhases.contains(.build))
        #expect(extendedPhases.contains(.review))
    }

    @Test("withExecution modifier → research에 build/review 추가")
    func withExecutionResearch() {
        let extendedPhases = WorkflowIntent.research.requiredPhases(with: [.withExecution])
        #expect(extendedPhases.contains(.build))
        #expect(extendedPhases.contains(.review))
    }

    @Test("outputOnly modifier → task에서 build 제거")
    func outputOnlyRemovesBuild() {
        let phases = WorkflowIntent.task.requiredPhases(with: [.outputOnly])
        #expect(!phases.contains(.build))
        #expect(!phases.contains(.review))
    }

    @Test("modifier 없으면 기본 phases 유지")
    func noModifierKeepsDefault() {
        let phases = WorkflowIntent.discussion.requiredPhases(with: [])
        #expect(phases == WorkflowIntent.discussion.requiredPhases)
    }

    // MARK: - IntentVocabulary 회귀 테스트

    @Test("'검토해줘' → discussion (검토 키워드 추가됨)")
    func reviewRequest_discussion() {
        #expect(IntentClassifier.quickClassify("이거 검토해줘") == .discussion)
    }

    @Test("'찾고...알려줘' → quickAnswer가 아님 (멀티스텝 억제)")
    func multiStep_notQuickAnswer() {
        let result = IntentClassifier.quickClassify("화면에서 찾고 그 API의 쿼리를 알려줘")
        #expect(result != .quickAnswer)
    }

    @Test("'자문해줘' → nil (task에서 제거됨, LLM 폴백)")
    func consultRequest_llmFallback() {
        // "자문"이 task에서 제거됨 → nil (LLM이 판단)
        #expect(IntentClassifier.quickClassify("자문해줘") == nil)
    }

    @Test("'이메일 작성해줘' → documentation (이메일 키워드 추가됨)")
    func emailRequest_documentation() {
        #expect(IntentClassifier.quickClassify("이메일 작성해줘") == .documentation)
    }

    @Test("'파악해줘' → research (파악 키워드 추가됨)")
    func investigateRequest_research() {
        #expect(IntentClassifier.quickClassify("현재 상태 파악해줘") == .research)
    }
}
