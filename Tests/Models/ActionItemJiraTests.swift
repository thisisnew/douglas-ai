import Testing
import Foundation
@testable import DOUGLAS

@Suite("ActionItem Jira 연동")
struct ActionItemJiraTests {

    @Test("toJiraSubtaskPayload — 기본 필드 변환")
    func toJiraSubtaskPayload_basic() {
        let item = ActionItem(
            description: "API 엔드포인트 구현",
            suggestedAgentName: "백엔드 개발자",
            priority: 1
        )

        let payload = item.toJiraSubtaskPayload(parentKey: "PROJ-123", projectKey: "PROJ")

        #expect(payload["parentKey"] == "PROJ-123")
        #expect(payload["projectKey"] == "PROJ")
        #expect(payload["summary"] == "API 엔드포인트 구현")
    }

    @Test("toJiraSubtaskPayload — 긴 description은 summary 잘림")
    func toJiraSubtaskPayload_longDescription() {
        let longDesc = String(repeating: "가", count: 300)
        let item = ActionItem(description: longDesc)

        let payload = item.toJiraSubtaskPayload(parentKey: "PROJ-1", projectKey: "PROJ")

        #expect((payload["summary"] ?? "").count <= 255)
    }

    @Test("toJiraSubtaskPayload — rationale이 description에 포함")
    func toJiraSubtaskPayload_withRationale() {
        let item = ActionItem(
            description: "리팩토링",
            rationale: "기술 부채 해소"
        )

        let payload = item.toJiraSubtaskPayload(parentKey: "PROJ-1", projectKey: "PROJ")
        let desc = payload["description"] ?? ""
        #expect(desc.contains("기술 부채 해소"))
    }
}
