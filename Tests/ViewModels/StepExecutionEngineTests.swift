import Testing
import Foundation
@testable import DOUGLAS

// MARK: - Mock WorkflowHost

@MainActor
final class MockWorkflowHost: WorkflowHost {
    var rooms: [UUID: Room] = [:]
    var appendedMessages: [ChatMessage] = []
    var executeStepCallCount = 0
    var executeStepHandler: ((Int) -> Void)? // stepIndex callback
    var executeStepResult: Bool = true

    // WorkflowHost conformance
    var speakingAgentIDByRoom: [UUID: UUID] = [:]
    let approvalGates = ApprovalGateManager()
    var pendingQuestionOptions: [UUID: [String]] = [:]
    var pendingIntentSelection: [UUID: WorkflowIntent] = [:]
    var pendingDocTypeSelection: [UUID: Bool] = [:]
    var pendingTeamConfirmation: [UUID: TeamConfirmationState] = [:]
    var reviewAutoApprovalRemaining: [UUID: Int] = [:]
    var agentStore: AgentStore?
    var providerManager: ProviderManager?
    var pluginEventDelegate: ((PluginEvent) -> Void)?
    var pluginInterceptToolDelegate: ((String, [String: String]) async -> ToolInterceptResult)?
    var mentionedAgentIDsByRoom: [UUID: [UUID]] = [:]
    var previousCycleAgentCount: [UUID: Int] = [:]
    var masterAgentName: String { "DOUGLAS" }

    func room(for id: UUID) -> Room? { rooms[id] }

    func updateRoom(id: UUID, _ mutate: (inout Room) -> Void) {
        guard var room = rooms[id] else { return }
        mutate(&room)
        rooms[id] = room
    }

    func appendMessage(_ message: ChatMessage, to roomID: UUID) {
        appendedMessages.append(message)
        rooms[roomID]?.addMessage(message)
    }

    func updateMessageContent(_ messageID: UUID, newContent: String, in roomID: UUID) {}
    func insertMessage(_ message: ChatMessage, to roomID: UUID, beforeMessageID: UUID) {}
    func syncAgentStatuses() {}
    func scheduleSave(immediate: Bool) {}
    func startReviewAutoApproval(roomID: UUID, seconds: Int) {}
    func cancelReviewAutoApproval(roomID: UUID) {}
    func addAgent(_ agentID: UUID, to roomID: UUID, silent: Bool) {}
    func addAgentSuggestion(_ suggestion: RoomAgentSuggestion, to roomID: UUID) {}

    @discardableResult
    func executeStep(
        step: String, fullTask: String, agentID: UUID, roomID: UUID,
        stepIndex: Int, totalSteps: Int,
        fileWriteTracker: FileWriteTracker?,
        progressGroupID: UUID?,
        workingDirectoryOverride: String?
    ) async -> Bool {
        executeStepCallCount += 1
        executeStepHandler?(stepIndex)
        return executeStepResult
    }
}

// MARK: - Tests

@Suite("StepExecutionEngine Rollback Tests")
struct StepExecutionEngineTests {

    /// 헬퍼: 테스트용 Room + Plan 생성
    @MainActor
    private static func makeHost(
        roomID: UUID,
        agentID: UUID,
        stepCount: Int
    ) -> MockWorkflowHost {
        let host = MockWorkflowHost()
        let steps = (0..<stepCount).map { i in
            RoomStep(text: "단계 \(i + 1)", assignedAgentID: agentID)
        }
        let plan = RoomPlan(summary: "테스트 계획", estimatedSeconds: 60, steps: steps)
        var room = Room(
            id: roomID,
            title: "테스트",
            assignedAgentIDs: [agentID],
            createdBy: .user
        )
        room.plan = plan
        host.rooms[roomID] = room
        // AgentStore에 더미 에이전트 등록
        let store = AgentStore()
        store.agents = [Agent(id: agentID, name: "테스터", persona: "테스트 에이전트", providerName: "test", modelName: "test")]
        host.agentStore = store
        return host
    }

    // MARK: - Step Journal

    @Test("단계 완료 시 stepJournal에 결과 요약 기록")
    @MainActor
    func stepJournal_recordedOnCompletion() async {
        let roomID = UUID()
        let agentID = UUID()
        let host = Self.makeHost(roomID: roomID, agentID: agentID, stepCount: 2)

        // executeStep에서 assistant 메시지 추가 시뮬레이션
        host.executeStepHandler = { stepIndex in
            let msg = ChatMessage(
                role: .assistant,
                content: "단계 \(stepIndex + 1) 결과: 작업 완료",
                messageType: .text
            )
            host.appendMessage(msg, to: roomID)
        }

        let engine = StepExecutionEngine(
            host: host, roomID: roomID, task: "테스트", policy: .standard
        )
        await engine.run()

        let room = host.rooms[roomID]!
        #expect(room.plan!.stepJournal.count == 2)
        #expect(room.plan!.stepJournal[0].contains("단계 1 결과"))
        #expect(room.plan!.stepJournal[1].contains("단계 2 결과"))
    }

    @Test("stepJournal 항목이 300자로 잘림")
    @MainActor
    func stepJournal_cappedAt300Chars() async {
        let roomID = UUID()
        let agentID = UUID()
        let host = Self.makeHost(roomID: roomID, agentID: agentID, stepCount: 1)

        // 긴 응답 시뮬레이션
        host.executeStepHandler = { _ in
            let longContent = String(repeating: "가", count: 500)
            let msg = ChatMessage(role: .assistant, content: longContent, messageType: .text)
            host.appendMessage(msg, to: roomID)
        }

        let engine = StepExecutionEngine(
            host: host, roomID: roomID, task: "테스트", policy: .standard
        )
        await engine.run()

        let room = host.rooms[roomID]!
        #expect(room.plan!.stepJournal.count == 1)
        #expect(room.plan!.stepJournal[0].count <= 300)
    }

}
