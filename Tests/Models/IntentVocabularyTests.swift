import Testing
import Foundation
@testable import DOUGLAS

@Suite("IntentVocabulary Tests")
struct IntentVocabularyTests {

    // MARK: - 시나리오 1: quickAnswer

    @Test("'BFF 패턴이 뭐야'에서 quickAnswer 매칭")
    func quickAnswerBFF() {
        let text = "bff 패턴이 뭐야?"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let qaScore = IntentVocabulary.quickAnswer.score(tokens: tokens, fullText: text, bigrams: bigrams)
        #expect(qaScore >= IntentVocabulary.quickAnswer.threshold)
    }

    @Test("'shared nothing architecture 설명해줘'에서 quickAnswer 매칭")
    func quickAnswerExplain() {
        let text = "shared nothing architecture 설명해줘"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let qaScore = IntentVocabulary.quickAnswer.score(tokens: tokens, fullText: text, bigrams: bigrams)
        #expect(qaScore >= IntentVocabulary.quickAnswer.threshold)
    }

    // MARK: - 시나리오 5: research

    @Test("'비교해서 정리해줘'에서 research 어휘 점수가 task보다 높음")
    func researchComparison() {
        let text = "claude code, codex, opencode를 비교해서 정리해줘"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let researchScore = IntentVocabulary.research.score(tokens: tokens, fullText: text, bigrams: bigrams)
        #expect(researchScore >= IntentVocabulary.research.threshold)
    }

    @Test("'사례 조사해줘'에서 research 매칭")
    func researchCaseStudy() {
        let text = "ai 작업 시스템 사례 조사해줘"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let score = IntentVocabulary.research.score(tokens: tokens, fullText: text, bigrams: bigrams)
        #expect(score >= IntentVocabulary.research.threshold)
    }

    // MARK: - 시나리오 6, 10: documentation

    @Test("'워크플로우 명세서 작성해줘'에서 documentation 매칭")
    func documentationSpec() {
        let text = "douglas 공식 워크플로우 명세서 작성해줘"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let score = IntentVocabulary.documentation.score(tokens: tokens, fullText: text, bigrams: bigrams)
        #expect(score >= IntentVocabulary.documentation.threshold)
    }

    @Test("'DDD 발표자료 목차 짜줘'에서 documentation 매칭")
    func documentationPresentation() {
        let text = "ddd 발표자료 목차 짜줘"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let docScore = IntentVocabulary.documentation.score(tokens: tokens, fullText: text, bigrams: bigrams)
        let taskScore = IntentVocabulary.task.score(tokens: tokens, fullText: text, bigrams: bigrams)
        #expect(docScore > taskScore, "documentation(\(docScore)) > task(\(taskScore))")
    }

    @Test("'사내 세미나 소개글 초안 작성해줘'에서 documentation 매칭")
    func documentationDraft() {
        let text = "사내 세미나 소개글 초안 작성해줘"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let score = IntentVocabulary.documentation.score(tokens: tokens, fullText: text, bigrams: bigrams)
        #expect(score >= IntentVocabulary.documentation.threshold)
    }

    // MARK: - SQL 키워드 (이전 분석 B)

    @Test("'DDL 보고 쿼리 짜줘'에서 task 매칭 (sql)")
    func taskSQL() {
        let text = "ddl 보고 쿼리 짜줘"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let score = IntentVocabulary.task.score(tokens: tokens, fullText: text, bigrams: bigrams)
        #expect(score >= IntentVocabulary.task.threshold)
    }

    // MARK: - 시나리오 10: 같은 주제 다른 intent

    @Test("'DDD가 뭐야'에서 quickAnswer가 최고점")
    func dddQuickAnswer() {
        let text = "ddd가 뭐야?"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let qaScore = IntentVocabulary.quickAnswer.score(tokens: tokens, fullText: text, bigrams: bigrams)
        let discScore = IntentVocabulary.discussion.score(tokens: tokens, fullText: text, bigrams: bigrams)
        let taskScore = IntentVocabulary.task.score(tokens: tokens, fullText: text, bigrams: bigrams)

        #expect(qaScore > discScore)
        #expect(qaScore > taskScore)
    }

    @Test("'DDD 적용 방향 같이 토론해줘'에서 discussion 매칭")
    func dddDiscussion() {
        let text = "ddd 적용 방향 같이 토론해줘"
        let tokens = text.split(separator: " ").map { String($0) }
        let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0)\($1)" }

        let score = IntentVocabulary.discussion.score(tokens: tokens, fullText: text, bigrams: bigrams)
        #expect(score >= IntentVocabulary.discussion.threshold)
    }

    // MARK: - 구조 검증

    @Test("모든 intent에 대한 어휘가 존재")
    func allIntentsCovered() {
        let coveredIntents = Set(IntentVocabulary.all.map(\.intent))
        #expect(coveredIntents.contains(.quickAnswer))
        #expect(coveredIntents.contains(.discussion))
        #expect(coveredIntents.contains(.research))
        #expect(coveredIntents.contains(.documentation))
        #expect(coveredIntents.contains(.task))
    }

    @Test("IntentVocabulary는 Equatable")
    func equatable() {
        let a = IntentVocabulary.quickAnswer
        let b = IntentVocabulary.quickAnswer
        #expect(a == b)
    }
}
