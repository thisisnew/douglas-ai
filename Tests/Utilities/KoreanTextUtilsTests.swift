import Testing
import Foundation
@testable import DOUGLAS

@Suite("KoreanTextUtils Tests")
struct KoreanTextUtilsTests {

    // MARK: - extractSemanticKeywords

    @Test("extractSemanticKeywords — 한국어+영문 혼합 텍스트에서 키워드 추출")
    func extractMixed() {
        let keywords = KoreanTextUtils.extractSemanticKeywords(from: "백엔드 개발자 spring boot")
        #expect(keywords.contains("백엔드"))
        #expect(keywords.contains("spring"))
        #expect(keywords.contains("boot"))
    }

    @Test("extractSemanticKeywords — 한국어 조사 제거")
    func extractStripsSuffix() {
        let keywords = KoreanTextUtils.extractSemanticKeywords(from: "서버에서 데이터를 분석하는")
        #expect(keywords.contains("서버"))
        #expect(keywords.contains("데이터"))
        #expect(keywords.contains("분석"))
    }

    @Test("extractSemanticKeywords — 빈 텍스트 → 빈 배열")
    func extractEmpty() {
        let keywords = KoreanTextUtils.extractSemanticKeywords(from: "")
        #expect(keywords.isEmpty)
    }

    @Test("extractSemanticKeywords — 1글자 토큰 필터링")
    func extractFiltersSingleChar() {
        let keywords = KoreanTextUtils.extractSemanticKeywords(from: "a b 테")
        #expect(keywords.isEmpty)
    }

    // MARK: - splitByScript

    @Test("splitByScript — 한글↔라틴 경계 분리")
    func splitMixedScript() {
        let parts = KoreanTextUtils.splitByScript("react와")
        #expect(parts == ["react", "와"])
    }

    @Test("splitByScript — 순수 한글 → 분리 없음")
    func splitPureKorean() {
        let parts = KoreanTextUtils.splitByScript("백엔드")
        #expect(parts == ["백엔드"])
    }

    @Test("splitByScript — 순수 영문 → 분리 없음")
    func splitPureLatin() {
        let parts = KoreanTextUtils.splitByScript("spring")
        #expect(parts == ["spring"])
    }

    @Test("splitByScript — 빈 문자열 → 빈 배열")
    func splitEmpty() {
        let parts = KoreanTextUtils.splitByScript("")
        #expect(parts.isEmpty)
    }

    // MARK: - stripKoreanSuffix

    @Test("stripKoreanSuffix — 조사 '에서' 제거")
    func stripEseo() {
        let result = KoreanTextUtils.stripKoreanSuffix("서버에서")
        #expect(result == "서버")
    }

    @Test("stripKoreanSuffix — 조사 '를' 제거")
    func stripReul() {
        let result = KoreanTextUtils.stripKoreanSuffix("데이터를")
        #expect(result == "데이터")
    }

    @Test("stripKoreanSuffix — 어간 2글자 미만이면 원본 유지")
    func stripKeepsShort() {
        let result = KoreanTextUtils.stripKoreanSuffix("가를")
        #expect(result == "가를")  // 어간 "가"는 1글자 → 제거 안 함
    }

    @Test("stripKoreanSuffix — 조사 없는 단어 → 그대로")
    func stripNoSuffix() {
        let result = KoreanTextUtils.stripKoreanSuffix("백엔드")
        #expect(result == "백엔드")
    }

    // MARK: - koreanStripSuffixes

    @Test("koreanStripSuffixes — 긴 접미사가 앞에 위치 (greedy)")
    func suffixOrdering() {
        let suffixes = KoreanTextUtils.koreanStripSuffixes
        // "에서"(2글자)가 "에"(1글자)보다 앞
        if let idxEseo = suffixes.firstIndex(of: "에서"),
           let idxE = suffixes.firstIndex(of: "에") {
            #expect(idxEseo < idxE)
        }
    }
}
