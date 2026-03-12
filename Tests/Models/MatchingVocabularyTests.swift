import Testing
import Foundation
@testable import DOUGLAS

@Suite("MatchingVocabulary Tests")
struct MatchingVocabularyTests {

    let vocab = MatchingVocabulary.default

    // MARK: - expandSynonyms

    @Test("expandSynonyms — 'fe' → 프론트엔드 동의어 확장")
    func expandFE() {
        let expanded = vocab.expandSynonyms(["fe"])
        #expect(expanded.contains("프론트엔드"))
        #expect(expanded.contains("frontend"))
        #expect(expanded.contains("fe"))
    }

    @Test("expandSynonyms — 'ios' → swift, swiftui 포함")
    func expandIOS() {
        let expanded = vocab.expandSynonyms(["ios"])
        #expect(expanded.contains("swift"))
        #expect(expanded.contains("swiftui"))
    }

    @Test("expandSynonyms — 매칭 안 되는 키워드 → 원본만")
    func expandNoMatch() {
        let expanded = vocab.expandSynonyms(["xyz123"])
        #expect(expanded == ["xyz123"])
    }

    @Test("expandSynonyms — 빈 배열 → 빈 배열")
    func expandEmpty() {
        let expanded = vocab.expandSynonyms([])
        #expect(expanded.isEmpty)
    }

    // MARK: - isGenericSuffix

    @Test("isGenericSuffix — '전문가' → true")
    func genericTrue() {
        #expect(vocab.isGenericSuffix("전문가"))
    }

    @Test("isGenericSuffix — 'developer' → true")
    func genericEnglish() {
        #expect(vocab.isGenericSuffix("developer"))
    }

    @Test("isGenericSuffix — '백엔드' → false")
    func genericFalse() {
        #expect(!vocab.isGenericSuffix("백엔드"))
    }

    // MARK: - containsWholeWord

    @Test("containsWholeWord — 'qa'는 'squad'에 매칭 안 됨")
    func wholeWordQA() {
        #expect(!vocab.containsWholeWord("squad", keyword: "qa"))
    }

    @Test("containsWholeWord — 'qa'는 'qa'에 매칭")
    func wholeWordExact() {
        #expect(vocab.containsWholeWord("qa", keyword: "qa"))
    }

    @Test("containsWholeWord — 'qa'는 'qa 엔지니어'에 매칭")
    func wholeWordBoundary() {
        #expect(vocab.containsWholeWord("qa 엔지니어", keyword: "qa"))
    }

    @Test("containsWholeWord — 긴 키워드 '백엔드'는 부분 매칭 허용")
    func wholeWordLong() {
        #expect(vocab.containsWholeWord("백엔드 개발", keyword: "백엔드"))
    }

    // MARK: - domainKeywords

    @Test("domainKeywords — '백엔드' 포함")
    func domainContains() {
        #expect(vocab.domainKeywords.contains("백엔드"))
    }

    // MARK: - synonymGroups 개수

    @Test("synonymGroups — 28+ 그룹 존재")
    func synonymGroupCount() {
        #expect(vocab.synonymGroups.count >= 28)
    }
}
