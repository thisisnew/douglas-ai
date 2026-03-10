import Testing
import Foundation
@testable import DOUGLAS

@Suite("토론 Turn 2 발언 순서 결정 Tests")
struct DiscussionOrderTests {

    // MARK: - JSON 파싱

    @Test("유효한 JSON → 순서 파싱 성공")
    func validJSON() {
        let response = """
        {"order": ["백엔드 개발자", "프론트엔드 개발자"], "reason": "API 설계가 프론트 구조를 결정"}
        """
        let agents = ["프론트엔드 개발자", "백엔드 개발자"]
        let result = DiscussionOrderParser.parse(from: response, agentNames: agents)
        #expect(result == ["백엔드 개발자", "프론트엔드 개발자"])
    }

    @Test("코드블록 감싼 JSON → 파싱 성공")
    func codeBlockJSON() {
        let response = """
        ```json
        {"order": ["QA 엔지니어", "백엔드 개발자", "프론트엔드 개발자"], "reason": "테스트 먼저"}
        ```
        """
        let agents = ["백엔드 개발자", "프론트엔드 개발자", "QA 엔지니어"]
        let result = DiscussionOrderParser.parse(from: response, agentNames: agents)
        #expect(result == ["QA 엔지니어", "백엔드 개발자", "프론트엔드 개발자"])
    }

    @Test("JSON 없는 텍스트 → nil 반환")
    func invalidResponse() {
        let response = "백엔드 개발자가 먼저 발언하는 게 좋겠습니다."
        let agents = ["프론트엔드 개발자", "백엔드 개발자"]
        let result = DiscussionOrderParser.parse(from: response, agentNames: agents)
        #expect(result == nil)
    }

    @Test("에이전트 이름이 불일치하면 nil 반환")
    func mismatchedNames() {
        let response = """
        {"order": ["디자이너", "기획자"], "reason": "디자인 먼저"}
        """
        let agents = ["프론트엔드 개발자", "백엔드 개발자"]
        let result = DiscussionOrderParser.parse(from: response, agentNames: agents)
        #expect(result == nil)
    }

    @Test("일부 에이전트만 포함 → nil 반환 (전원 포함 필수)")
    func partialNames() {
        let response = """
        {"order": ["백엔드 개발자"], "reason": "백엔드만"}
        """
        let agents = ["프론트엔드 개발자", "백엔드 개발자"]
        let result = DiscussionOrderParser.parse(from: response, agentNames: agents)
        #expect(result == nil)
    }

    @Test("3명 에이전트 순서 결정")
    func threeAgents() {
        let response = """
        {"order": ["QA 엔지니어", "프론트엔드 개발자", "백엔드 개발자"], "reason": "검증 관점 선행"}
        """
        let agents = ["백엔드 개발자", "프론트엔드 개발자", "QA 엔지니어"]
        let result = DiscussionOrderParser.parse(from: response, agentNames: agents)
        #expect(result == ["QA 엔지니어", "프론트엔드 개발자", "백엔드 개발자"])
    }

    @Test("order 배열이 없으면 nil")
    func missingOrderKey() {
        let response = """
        {"agents": ["백엔드 개발자"], "reason": "잘못된 키"}
        """
        let agents = ["백엔드 개발자"]
        let result = DiscussionOrderParser.parse(from: response, agentNames: agents)
        #expect(result == nil)
    }
}
