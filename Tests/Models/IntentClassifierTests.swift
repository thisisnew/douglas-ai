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

    @Test("설명 요청 → quickAnswer")
    func explanation() {
        #expect(IntentClassifier.quickClassify("알려줘") == .quickAnswer)
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

    @Test("요약+pdf 복합 → task")
    func summarizeWithPdf() {
        #expect(IntentClassifier.quickClassify("요약해서 pdf로 바꿔줘") == WorkflowIntent.task)
    }

    @Test("요약+pdf 만들어줘 → task")
    func summarizePdfMake() {
        let result = IntentClassifier.quickClassify("요약해서 pdf로 만들어줘")
        #expect(result == WorkflowIntent.task)
    }

    @Test("분석 요청 → task")
    func analysis() {
        #expect(IntentClassifier.quickClassify("이거 분석해봐") == WorkflowIntent.task)
    }

    @Test("브레인스토밍 → discussion")
    func brainstorm() {
        #expect(IntentClassifier.quickClassify("브레인스토밍 해보자") == WorkflowIntent.discussion)
    }

    @Test("변환 → task")
    func convert() {
        #expect(IntentClassifier.quickClassify("워드로 변환해줘") == WorkflowIntent.task)
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

    @Test("pdf로 만들어줘 → task")
    func pdfContextOverridesAction() {
        let result = IntentClassifier.quickClassify("이걸 pdf로 만들어줘")
        #expect(result == WorkflowIntent.task)
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

    @Test("번역 + 문서화 복합 → documentation (문서화가 최종 동사)")
    func longTranslation() {
        #expect(IntentClassifier.quickClassify("이 프로젝트의 README를 한국어로 번역하고 기술 용어집도 포함해서 문서화해줘") == .documentation)
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

    @Test("바꿔봐 → task")
    func koreanStemConvert() {
        #expect(IntentClassifier.quickClassify("pdf로 바꿔봐") == WorkflowIntent.task)
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
}
