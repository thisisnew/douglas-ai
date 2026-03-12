import Testing
import Foundation
@testable import DOUGLAS

@Suite("ActionItemGenerator Tests")
struct ActionItemGeneratorTests {

    @Test("유효한 JSON에서 ActionItems 파싱")
    func parseValid() {
        let json = """
        {
            "summary": "토론 결과 요약",
            "action_items": [
                {"description": "API 설계", "suggested_agent": "백엔드", "priority": 1, "rationale": "핵심", "dependencies": null},
                {"description": "UI 구현", "suggested_agent": "프론트", "priority": 2, "dependencies": [0]}
            ]
        }
        """
        let items = ActionItemGenerator.parse(from: json)
        #expect(items != nil)
        #expect(items?.count == 2)
        #expect(items?[0].description == "API 설계")
        #expect(items?[0].suggestedAgentName == "백엔드")
        #expect(items?[0].priority == 1)
        #expect(items?[1].dependencies == [0])
    }

    @Test("action_items 없는 JSON → nil")
    func parseNoItems() {
        let json = """
        {"summary": "결과 요약", "conclusion": "합의 도달"}
        """
        let items = ActionItemGenerator.parse(from: json)
        #expect(items == nil)
    }

    @Test("빈 action_items 배열 → nil")
    func parseEmptyItems() {
        let json = """
        {"action_items": []}
        """
        let items = ActionItemGenerator.parse(from: json)
        #expect(items == nil)
    }

    @Test("잘못된 JSON → nil")
    func parseInvalid() {
        let items = ActionItemGenerator.parse(from: "이것은 JSON이 아닙니다")
        #expect(items == nil)
    }

    @Test("priority 기본값 2")
    func defaultPriority() {
        let json = """
        {"action_items": [{"description": "테스트"}]}
        """
        let items = ActionItemGenerator.parse(from: json)
        #expect(items?.first?.priority == 2)
    }
}
