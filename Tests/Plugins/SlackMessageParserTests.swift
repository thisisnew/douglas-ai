import Testing
import Foundation
@testable import DOUGLAS

@Suite("SlackMessageParser Tests")
struct SlackMessageParserTests {

    // MARK: - extractCleanText

    @Test("유저 멘션 제거")
    func stripUserMentions() {
        let input = "<@U12345> 서버 확인해줘"
        let result = SlackMessageParser.extractCleanText(input)
        #expect(result == "서버 확인해줘")
    }

    @Test("복수 멘션 제거")
    func stripMultipleMentions() {
        let input = "<@U111> <@U222> 같이 확인해줘"
        let result = SlackMessageParser.extractCleanText(input)
        #expect(result == "같이 확인해줘")
    }

    @Test("URL label 변환")
    func convertURLLabels() {
        let input = "<https://example.com|Example Site> 참고"
        let result = SlackMessageParser.extractCleanText(input)
        #expect(result == "Example Site 참고")
    }

    @Test("URL 태그 제거 (label 없음)")
    func stripURLTags() {
        let input = "<https://example.com> 확인"
        let result = SlackMessageParser.extractCleanText(input)
        #expect(result == "https://example.com 확인")
    }

    @Test("빈 입력")
    func emptyInput() {
        let result = SlackMessageParser.extractCleanText("")
        #expect(result == "")
    }

    @Test("변환 불필요 텍스트")
    func plainText() {
        let input = "일반 텍스트 메시지"
        let result = SlackMessageParser.extractCleanText(input)
        #expect(result == "일반 텍스트 메시지")
    }

    @Test("공백만 남는 경우 트리밍")
    func trimWhitespace() {
        let input = "  <@U123>  "
        let result = SlackMessageParser.extractCleanText(input)
        #expect(result == "")
    }

    // MARK: - formatForSlack

    @Test("에이전트 이름 prefix 추가")
    func formatWithAgentName() {
        let result = SlackMessageParser.formatForSlack(content: "안녕하세요", agentName: "백엔드")
        #expect(result == "*[백엔드]* 안녕하세요")
    }

    @Test("에이전트 이름 없이")
    func formatWithoutAgentName() {
        let result = SlackMessageParser.formatForSlack(content: "안녕하세요", agentName: nil)
        #expect(result == "안녕하세요")
    }

    @Test("4000자 초과 시 truncation")
    func formatTruncation() {
        let longText = String(repeating: "가", count: 4000)
        let result = SlackMessageParser.formatForSlack(content: longText, agentName: nil)
        #expect(result.count < 4000)
        #expect(result.hasSuffix("...(truncated)"))
    }
}
