import Testing
import Foundation
@testable import DOUGLAS

@Suite("ToolExecutionContext Tests")
struct ToolExecutionContextTests {

    @Test("기본 초기화")
    func initBasic() {
        let roomID = UUID()
        let agentID = UUID()
        let context = ToolExecutionContext(
            roomID: roomID,
            agentsByName: ["Agent1": agentID],
            agentListString: "- Agent1: 테스트 에이전트",
            inviteAgent: { _ in true }
        )
        #expect(context.roomID == roomID)
        #expect(context.agentsByName["Agent1"] == agentID)
        #expect(context.agentListString == "- Agent1: 테스트 에이전트")
    }

    @Test("empty 팩토리 - 모든 필드 비어있음")
    func emptyFactory() {
        let context = ToolExecutionContext.empty
        #expect(context.roomID == nil)
        #expect(context.agentsByName.isEmpty)
        #expect(context.agentListString == "")
    }

    @Test("empty - inviteAgent는 항상 false 반환")
    func emptyInviteAlwaysFalse() async {
        let context = ToolExecutionContext.empty
        let result = await context.inviteAgent(UUID())
        #expect(result == false)
    }

    @Test("여러 에이전트 매핑")
    func multipleAgents() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: ["코더": id1, "리서처": id2, "리뷰어": id3],
            agentListString: "- 코더\n- 리서처\n- 리뷰어",
            inviteAgent: { _ in true }
        )
        #expect(context.agentsByName.count == 3)
        #expect(context.agentsByName["코더"] == id1)
        #expect(context.agentsByName["리서처"] == id2)
        #expect(context.agentsByName["리뷰어"] == id3)
    }

    @Test("inviteAgent 콜백 동작")
    func inviteAgentCallback() async {
        let targetID = UUID()
        var invitedID: UUID?
        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: [:],
            agentListString: "",
            inviteAgent: { id in
                invitedID = id
                return true
            }
        )
        let result = await context.inviteAgent(targetID)
        #expect(result == true)
        #expect(invitedID == targetID)
    }

    @Test("roomID nil 허용")
    func roomIDNil() {
        let context = ToolExecutionContext(
            roomID: nil,
            agentsByName: ["A": UUID()],
            agentListString: "A",
            inviteAgent: { _ in false }
        )
        #expect(context.roomID == nil)
        #expect(context.agentsByName.count == 1)
    }
}
