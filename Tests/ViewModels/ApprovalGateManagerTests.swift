import Testing
import Foundation
@testable import DOUGLAS

@Suite("ApprovalGateManager")
struct ApprovalGateManagerTests {

    @Test("approve — 대기 중인 continuation 해제")
    @MainActor
    func approve_resumesContinuation() async {
        let gates = ApprovalGateManager()
        let roomID = UUID()

        async let result = gates.waitForApproval(roomID: roomID)
        // 약간의 지연 후 승인
        try? await Task.sleep(for: .milliseconds(50))
        gates.approve(roomID: roomID)

        let approved = await result
        #expect(approved == true)
    }

    @Test("reject — false로 continuation 해제")
    @MainActor
    func reject_resumesWithFalse() async {
        let gates = ApprovalGateManager()
        let roomID = UUID()

        async let result = gates.waitForApproval(roomID: roomID)
        try? await Task.sleep(for: .milliseconds(50))
        gates.reject(roomID: roomID)

        let approved = await result
        #expect(approved == false)
    }

    @Test("approve — 대기 중이 아니면 no-op")
    @MainActor
    func approve_noPending_noop() {
        let gates = ApprovalGateManager()
        // 크래시 없이 무시되어야 함
        gates.approve(roomID: UUID())
    }

    @Test("waitForUserInput + provideUserInput")
    @MainActor
    func userInput_roundtrip() async {
        let gates = ApprovalGateManager()
        let roomID = UUID()

        async let input = gates.waitForUserInput(roomID: roomID)
        try? await Task.sleep(for: .milliseconds(50))
        gates.provideUserInput(roomID: roomID, input: "사용자 답변")

        let result = await input
        #expect(result == "사용자 답변")
    }

    @Test("waitForIntent + provideIntent")
    @MainActor
    func intent_roundtrip() async {
        let gates = ApprovalGateManager()
        let roomID = UUID()

        async let intent = gates.waitForIntent(roomID: roomID)
        try? await Task.sleep(for: .milliseconds(50))
        gates.provideIntent(roomID: roomID, intent: .discussion)

        let result = await intent
        #expect(result == .discussion)
    }

    @Test("waitForDocType + provideDocType")
    @MainActor
    func docType_roundtrip() async {
        let gates = ApprovalGateManager()
        let roomID = UUID()

        async let docType = gates.waitForDocType(roomID: roomID)
        try? await Task.sleep(for: .milliseconds(50))
        gates.provideDocType(roomID: roomID, docType: .prd)

        let result = await docType
        #expect(result == .prd)
    }

    @Test("waitForTeamConfirmation + confirmTeam")
    @MainActor
    func teamConfirmation_roundtrip() async {
        let gates = ApprovalGateManager()
        let roomID = UUID()
        let agentIDs: Set<UUID> = [UUID(), UUID()]

        async let team = gates.waitForTeamConfirmation(roomID: roomID)
        try? await Task.sleep(for: .milliseconds(50))
        gates.confirmTeam(roomID: roomID, selectedIDs: agentIDs)

        let result = await team
        #expect(result == agentIDs)
    }

    @Test("skipTeamConfirmation — nil 반환")
    @MainActor
    func skipTeam_returnsNil() async {
        let gates = ApprovalGateManager()
        let roomID = UUID()

        async let team = gates.waitForTeamConfirmation(roomID: roomID)
        try? await Task.sleep(for: .milliseconds(50))
        gates.skipTeamConfirmation(roomID: roomID)

        let result = await team
        #expect(result == nil)
    }

    @Test("cancelAll — 모든 pending continuation 해제")
    @MainActor
    func cancelAll_releasesAll() async {
        let gates = ApprovalGateManager()
        let roomID = UUID()

        // 승인 게이트 등록
        async let approval = gates.waitForApproval(roomID: roomID)
        try? await Task.sleep(for: .milliseconds(50))
        gates.cancelAll(for: roomID)

        let result = await approval
        #expect(result == false)  // 취소 시 false
    }

    @Test("hasPendingApproval 확인")
    @MainActor
    func hasPendingApproval() async {
        let gates = ApprovalGateManager()
        let roomID = UUID()

        #expect(gates.hasPendingApproval(for: roomID) == false)

        async let _ = gates.waitForApproval(roomID: roomID)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(gates.hasPendingApproval(for: roomID) == true)

        gates.approve(roomID: roomID)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(gates.hasPendingApproval(for: roomID) == false)
    }
}
