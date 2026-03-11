import Testing
import Foundation
@testable import DOUGLAS

@Suite("TokenEstimator Tests")
struct TokenEstimatorTests {

    @Test("영문 텍스트 — ~4자/토큰 추정")
    func asciiText() {
        let text = String(repeating: "a", count: 100)
        let tokens = TokenEstimator.estimate(text)
        // 100 ASCII chars ≈ 25 tokens (4자/토큰)
        #expect(tokens >= 20 && tokens <= 35)
    }

    @Test("한글 텍스트 — ~2자/토큰 추정")
    func koreanText() {
        let text = String(repeating: "가", count: 100)
        let tokens = TokenEstimator.estimate(text)
        // 100 Korean chars ≈ 50 tokens (2자/토큰)
        #expect(tokens >= 40 && tokens <= 65)
    }

    @Test("혼합 텍스트 — 가중 평균")
    func mixedText() {
        // 50 ASCII + 50 Korean
        let text = String(repeating: "a", count: 50) + String(repeating: "가", count: 50)
        let tokens = TokenEstimator.estimate(text)
        // 50/4 + 50/2 = 12.5 + 25 = ~37.5
        #expect(tokens >= 30 && tokens <= 50)
    }

    @Test("빈 문자열 — 0 토큰")
    func emptyString() {
        #expect(TokenEstimator.estimate("") == 0)
    }

    @Test("여러 텍스트 합산")
    func multipleTexts() {
        let texts = ["Hello World", "안녕하세요"]
        let combined = TokenEstimator.estimate(texts)
        let individual = texts.map { TokenEstimator.estimate($0) }.reduce(0, +)
        #expect(combined == individual)
    }
}
