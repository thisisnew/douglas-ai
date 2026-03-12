import Testing
import Foundation
@testable import DOUGLAS

@Suite("AmbiguityDetector Tests")
struct AmbiguityDetectorTests {

    // MARK: - 모호한 요청 (시나리오 3)

    @Test("'이거 좀 좋게 바꿔줘'는 모호함 — pronounOnly")
    func pronounOnly() {
        let result = AmbiguityDetector.detect(text: "이거 좀 더 좋게 바꿔줘", hasAttachments: false)
        #expect(result.isAmbiguous)
        #expect(result.reason == .pronounOnly)
    }

    @Test("'그거 고쳐줘'는 모호함 — pronounOnly")
    func pronounOnlyFix() {
        let result = AmbiguityDetector.detect(text: "그거 고쳐줘", hasAttachments: false)
        #expect(result.isAmbiguous)
        #expect(result.reason == .pronounOnly)
    }

    // MARK: - 명확한 요청

    @Test("'Spring Boot Redis 캐시 코드 짜줘'는 비모호")
    func clearTaskRequest() {
        let result = AmbiguityDetector.detect(text: "Spring Boot에서 Redis 캐시 예제 코드 짜줘", hasAttachments: false)
        #expect(!result.isAmbiguous)
    }

    @Test("'이거 분석해줘' + 첨부파일은 비모호")
    func pronounWithAttachment() {
        let result = AmbiguityDetector.detect(text: "이거 분석해줘", hasAttachments: true)
        #expect(!result.isAmbiguous)
    }

    @Test("'더글라스 RoomManager 리팩토링해줘'는 비모호 (구체적 대상)")
    func specificTarget() {
        let result = AmbiguityDetector.detect(text: "더글라스 RoomManager 리팩토링해줘", hasAttachments: false)
        #expect(!result.isAmbiguous)
    }

    // MARK: - URL만 입력

    @Test("빈 텍스트(URL 제거 후)는 모호함 — noActionableContext")
    func emptyAfterClean() {
        let result = AmbiguityDetector.detect(text: "  ", hasAttachments: false)
        #expect(result.isAmbiguous)
        #expect(result.reason == .noActionableContext)
    }

    // MARK: - 경계 케이스

    @Test("'이거 리팩토링해줘'는 비모호 — 구체적 동작 있음")
    func pronounWithSpecificAction() {
        let result = AmbiguityDetector.detect(text: "이거 리팩토링해줘", hasAttachments: false)
        // "리팩토링"은 genericActions에 없으므로 구체적 동작
        #expect(!result.isAmbiguous)
    }

    @Test("AmbiguityDetector.Result는 Equatable")
    func equatable() {
        let a = AmbiguityDetector.Result(isAmbiguous: true, reason: .pronounOnly)
        let b = AmbiguityDetector.Result(isAmbiguous: true, reason: .pronounOnly)
        #expect(a == b)
    }
}
