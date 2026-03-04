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

    @Test("번역 → quickAnswer")
    func translation() {
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

    // MARK: - quickClassify: research

    @Test("요약 요청 → research")
    func summarize() {
        #expect(IntentClassifier.quickClassify("요약해줘") == .research)
    }

    @Test("요약+pdf 복합 → research")
    func summarizeWithPdf() {
        #expect(IntentClassifier.quickClassify("요약해서 pdf로 바꿔줘") == .research)
    }

    @Test("요약+pdf 만들어줘 → research (implementation 아님)")
    func summarizePdfMake() {
        let result = IntentClassifier.quickClassify("요약해서 pdf로 만들어줘")
        #expect(result == .research)
    }

    @Test("문서 작성 → research")
    func documentWriting() {
        #expect(IntentClassifier.quickClassify("기획서 작성해줘") == .research)
    }

    @Test("보고서 정리 → research")
    func reportOrganize() {
        #expect(IntentClassifier.quickClassify("보고서로 정리해줘") == .research)
    }

    @Test("리서치 → research")
    func researchDirect() {
        #expect(IntentClassifier.quickClassify("이 주제 조사해줘") == .research)
    }

    @Test("분석 요청 → research")
    func analysis() {
        #expect(IntentClassifier.quickClassify("이거 분석해봐") == .research)
    }

    @Test("PRD → research")
    func prd() {
        #expect(IntentClassifier.quickClassify("PRD 작성해줘") == .research)
    }

    @Test("브레인스토밍 → research")
    func brainstorm() {
        #expect(IntentClassifier.quickClassify("브레인스토밍 해보자") == .research)
    }

    @Test("변환 → research")
    func convert() {
        #expect(IntentClassifier.quickClassify("워드로 변환해줘") == .research)
    }

    // MARK: - quickClassify: implementation

    @Test("코딩 → implementation")
    func coding() {
        #expect(IntentClassifier.quickClassify("코딩해줘") == .implementation)
    }

    @Test("구현 → implementation")
    func implement() {
        #expect(IntentClassifier.quickClassify("로그인 기능 구현해줘") == .implementation)
    }

    @Test("버그 → implementation")
    func bugFix() {
        #expect(IntentClassifier.quickClassify("이 버그 수정해줘") == .implementation)
    }

    @Test("리팩토링 → implementation")
    func refactor() {
        #expect(IntentClassifier.quickClassify("이 코드 리팩토링해줘") == .implementation)
    }

    // MARK: - 문서 컨텍스트 보정

    @Test("pdf로 만들어줘 → research (문서 컨텍스트가 implementation을 억제)")
    func pdfContextOverridesAction() {
        let result = IntentClassifier.quickClassify("이걸 pdf로 만들어줘")
        #expect(result == .research)
    }

    @Test("문서 만들어줘 → research")
    func documentMake() {
        let result = IntentClassifier.quickClassify("문서 만들어줘")
        #expect(result == .research)
    }

    @Test("앱 만들어줘 → implementation (문서 컨텍스트 없음)")
    func appMake() {
        let result = IntentClassifier.quickClassify("앱 만들어줘")
        #expect(result == .implementation)
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

    @Test("요약해서 → research (어간 '요약' 매칭)")
    func koreanStemSummarize() {
        #expect(IntentClassifier.quickClassify("이 파일 요약해서 보내줘") == .research)
    }

    @Test("바꿔봐 → research")
    func koreanStemConvert() {
        #expect(IntentClassifier.quickClassify("pdf로 바꿔봐") == .research)
    }
}
