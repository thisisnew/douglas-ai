import Testing
import Foundation
@testable import DOUGLAS

@Suite("Intake URL 자동 교정 Tests")
struct IntakeURLCorrectionTests {

    // MARK: - URL 교정

    @Test("ttps:// → https:// 자동 교정")
    func correctTtps() {
        let input = "ttps://kurly0521.atlassian.net/browse/IBS-3279"
        let corrected = IntakeURLCorrector.correct(input)
        #expect(corrected.contains("https://kurly0521.atlassian.net/browse/IBS-3279"))
    }

    @Test("htps:// → https:// 자동 교정")
    func correctHtps() {
        let input = "htps://example.com/page"
        let corrected = IntakeURLCorrector.correct(input)
        #expect(corrected.contains("https://example.com/page"))
    }

    @Test("htp:// → http:// 자동 교정")
    func correctHtp() {
        let input = "htp://example.com/page"
        let corrected = IntakeURLCorrector.correct(input)
        #expect(corrected.contains("http://example.com/page"))
    }

    @Test("정상 URL은 변경 없음")
    func normalURLUnchanged() {
        let input = "https://example.com/page"
        let corrected = IntakeURLCorrector.correct(input)
        #expect(corrected == input)
    }

    @Test("http:// 정상 URL은 변경 없음")
    func normalHttpUnchanged() {
        let input = "http://example.com/page"
        let corrected = IntakeURLCorrector.correct(input)
        #expect(corrected == input)
    }

    @Test("URL 없는 텍스트는 변경 없음")
    func noURLUnchanged() {
        let input = "IBS-3279 개발해줘"
        let corrected = IntakeURLCorrector.correct(input)
        #expect(corrected == input)
    }

    @Test("혼합 텍스트에서 URL만 교정")
    func mixedTextCorrection() {
        let input = "이거 봐줘 ttps://jira.example.com/browse/PROJ-100 개발해줘"
        let corrected = IntakeURLCorrector.correct(input)
        #expect(corrected.contains("https://jira.example.com/browse/PROJ-100"))
        #expect(corrected.contains("이거 봐줘"))
        #expect(corrected.contains("개발해줘"))
    }

    @Test("여러 오타 URL 동시 교정")
    func multipleTypoURLs() {
        let input = "ttps://a.com ttps://b.com"
        let corrected = IntakeURLCorrector.correct(input)
        #expect(corrected.contains("https://a.com"))
        #expect(corrected.contains("https://b.com"))
    }

    // MARK: - URL 끝 한글 조사 제거

    @Test("URL 뒤 한글 조사 '를' 제거")
    func urlTrailingKoreanParticle() {
        // "https://...IBS-3110를" → "를" 제거
        let urls = IntakeURLExtractor.extractURLs(from: "https://kurly0521.atlassian.net/browse/IBS-3110를 개발해줘")
        #expect(urls.count == 1)
        #expect(urls.first == "https://kurly0521.atlassian.net/browse/IBS-3110")
    }

    @Test("URL 뒤 한글 조사 '에서' 제거")
    func urlTrailingKoreanParticle2() {
        let urls = IntakeURLExtractor.extractURLs(from: "https://example.com/page에서 확인")
        #expect(urls.count == 1)
        #expect(urls.first == "https://example.com/page")
    }

    @Test("URL 뒤 한글 없으면 그대로")
    func urlNoTrailingKorean() {
        let urls = IntakeURLExtractor.extractURLs(from: "https://example.com/page 확인")
        #expect(urls.count == 1)
        #expect(urls.first == "https://example.com/page")
    }
}

@Suite("parsePlan 재시도 Tests")
@MainActor
struct PlanParseRetryTests {

    private static let testRoomDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("douglas-parseplan-tests-\(ProcessInfo.processInfo.processIdentifier)")

    private func makeManager() -> RoomManager {
        RoomManager.roomDirectoryOverride = Self.testRoomDir
        return RoomManager()
    }

    // MARK: - parsePlan 파싱

    @Test("유효한 JSON → 파싱 성공")
    func validJSON() {
        let json = """
        {"plan": {"summary": "테스트 계획", "estimated_minutes": 5, "steps": [{"text": "단계1"}]}}
        """
        let rm = makeManager()
        let plan = rm.parsePlan(from: json)
        #expect(plan != nil)
        #expect(plan?.summary == "테스트 계획")
        #expect(plan?.steps.count == 1)
    }

    @Test("코드블록 감싼 JSON → 파싱 성공")
    func codeBlockJSON() {
        let response = """
        여기 계획입니다:
        ```json
        {"plan": {"summary": "코드블록 계획", "estimated_minutes": 3, "steps": ["단계1", "단계2"]}}
        ```
        """
        let rm = makeManager()
        let plan = rm.parsePlan(from: response)
        #expect(plan != nil)
        #expect(plan?.summary == "코드블록 계획")
    }

    @Test("JSON 없는 텍스트 → nil 반환")
    func noJSON() {
        let response = "백엔드 팀과 논의가 필요합니다. 다음 단계를 진행하겠습니다."
        let rm = makeManager()
        let plan = rm.parsePlan(from: response)
        #expect(plan == nil)
    }
}
