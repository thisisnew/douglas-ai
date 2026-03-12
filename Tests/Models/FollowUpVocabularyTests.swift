import Testing
import Foundation
@testable import DOUGLAS

@Suite("FollowUpVocabulary Tests")
struct FollowUpVocabularyTests {

    // MARK: - 문서화 어휘 (이전 분석 A — "요약" 키워드)

    @Test("'요약해줘'는 document 어휘 매칭")
    func summarizeMatchesDocument() {
        #expect(FollowUpVocabulary.document.matches("요약해줘"))
    }

    @Test("'정리해줘'는 document 어휘 매칭")
    func organizeMatchesDocument() {
        #expect(FollowUpVocabulary.document.matches("정리해줘"))
    }

    @Test("'문서화해줘'는 document 어휘 매칭")
    func documentizeMatchesDocument() {
        #expect(FollowUpVocabulary.document.matches("문서화해줘"))
    }

    // MARK: - 재시도 어휘

    @Test("'다시해줘'는 retry 어휘 매칭")
    func retryMatch() {
        #expect(FollowUpVocabulary.retry.matches("다시해줘"))
    }

    @Test("'재시도 해줘'는 retry 어휘 매칭")
    func retryRetry() {
        #expect(FollowUpVocabulary.retry.matches("재시도 해줘"))
    }

    // MARK: - 구현 어휘

    @Test("'구현해줘'는 implement 어휘 매칭")
    func implementMatch() {
        #expect(FollowUpVocabulary.implement.matches("구현해줘"))
    }

    // MARK: - 토론 계속 어휘

    @Test("'더 논의하자'는 continueDiscussion 어휘 매칭")
    func continueDiscussionMatch() {
        #expect(FollowUpVocabulary.continueDiscussion.matches("더 논의하자"))
    }

    // MARK: - 검토 어휘

    @Test("'검토해줘'는 review 어휘 매칭")
    func reviewMatch() {
        #expect(FollowUpVocabulary.review.matches("검토해줘"))
    }

    // MARK: - 비매칭

    @Test("'새로운 기능 만들어줘'는 document 어휘 미매칭")
    func noDocumentMatch() {
        #expect(!FollowUpVocabulary.document.matches("새로운 기능 만들어줘"))
    }

    // MARK: - 구조 검증

    @Test("모든 어휘의 키워드가 비어있지 않음")
    func allVocabulariesNonEmpty() {
        for vocab in FollowUpVocabulary.all {
            #expect(!vocab.keywords.isEmpty, "\(vocab.intent) 어휘가 비어있음")
        }
    }
}
