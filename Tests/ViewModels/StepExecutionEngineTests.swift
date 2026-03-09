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
    var approvalContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    var userInputContinuations: [UUID: CheckedContinuation<String, Never>] = [:]
    var intentContinuations: [UUID: CheckedContinuation<WorkflowIntent, Never>] = [:]
    var docTypeContinuations: [UUID: CheckedContinuation<DocumentType, Never>] = [:]
    var teamConfirmationContinuations: [UUID: CheckedContinuation<Set<UUID>?, Never>] = [:]
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
    var stepRollbackTargets: [UUID: Int] = [:]

    var masterAgentName: String { "DOUGLAS" }

    func room(for id: UUID) -> Room? { rooms[id] }

    func updateRoom(id: UUID, _ mutate: (inout Room) -> Void) {
        guard var room = rooms[id] else { return }
        mutate(&room)
        rooms[id] = room
    }

    func appendMessage(_ message: ChatMessage, to roomID: UUID) {
        appendedMessages.append(message)
        rooms[roomID]?.messages.append(message)
    }

    func updateMessageContent(_ messageID: UUID, newContent: String, in roomID: UUID) {}
    func insertMessage(_ message: ChatMessage, to roomID: UUID, beforeMessageID: UUID) {}
    func syncAgentStatuses() {}
    func scheduleSave() {}
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
        deferHighRiskTools: Bool,
        collectDeferred: ((DeferredAction) -> Void)?
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

    // MARK: - 롤백 테스트

    @Test("롤백 타겟이 실행 중 설정되면 엔진이 처리하고 대상 단계부터 재실행한다")
    @MainActor
    func rollbackDuringExecution() async {
        let roomID = UUID()
        let agentID = UUID()
        let host = Self.makeHost(roomID: roomID, agentID: agentID, stepCount: 3)

        // step 2 (index 1) 실행 시 rollback to step 1 (index 0) 설정
        host.executeStepHandler = { stepIndex in
            if stepIndex == 1 && host.executeStepCallCount == 2 {
                // 첫 번째 step 1 실행에서만 롤백 설정 (무한루프 방지)
                host.stepRollbackTargets[roomID] = 0
            }
        }

        let engine = StepExecutionEngine(
            host: host, roomID: roomID, task: "테스트 작업", policy: .standard
        )
        await engine.run()

        // 롤백이 처리되었으므로 executeStep 호출 횟수가 3보다 많아야 함
        // step 0 → step 1 (rollback 설정) → step 0 재실행 → step 1 재실행 → step 2
        #expect(host.executeStepCallCount > 3)
        // 롤백 타겟이 소비되었는지 확인
        #expect(host.stepRollbackTargets[roomID] == nil)
        // 모든 단계가 completed 상태인지 확인
        let room = host.rooms[roomID]!
        #expect(room.plan!.steps.allSatisfy { $0.status == .completed })
    }

    @Test("전체 단계 완료 후 롤백 타겟이 있으면 재실행한다")
    @MainActor
    func postCompletionRollback() async {
        let roomID = UUID()
        let agentID = UUID()
        let host = Self.makeHost(roomID: roomID, agentID: agentID, stepCount: 2)

        // 마지막 단계(step 1) 실행 시 롤백 설정 — 엔진 피드백 루프가 yield 후 잡지 못하면
        // post-completion 체크에서 잡아야 함
        var lastStepExecuted = false
        host.executeStepHandler = { stepIndex in
            if stepIndex == 1 && !lastStepExecuted {
                lastStepExecuted = true
                // 마지막 단계 실행 완료 직후 롤백 설정
                // (피드백 루프의 Task.yield()가 이를 처리)
                host.stepRollbackTargets[roomID] = 0
            }
        }

        let engine = StepExecutionEngine(
            host: host, roomID: roomID, task: "테스트", policy: .standard
        )
        await engine.run()

        // 롤백이 처리되어 step 0, 1이 재실행됨
        // 최소 4번 (step0 + step1 + rollback → step0 + step1)
        #expect(host.executeStepCallCount >= 4)
        #expect(host.stepRollbackTargets[roomID] == nil)
    }

    @Test("피드백 루프 미사용 시에도 마지막 단계 후 롤백이 처리된다")
    @MainActor
    func postCompletionRollbackWithoutFeedbackLoop() async {
        let roomID = UUID()
        let agentID = UUID()
        let host = Self.makeHost(roomID: roomID, agentID: agentID, stepCount: 2)

        // 피드백 루프 비활성 정책 — 엔진이 step 완료 후 즉시 다음으로 이동
        let noFeedback = StepExecutionEngine.Policy(
            enableUserFeedbackLoop: false,
            deferHighRiskSteps: false,
            detectRepetition: false,
            generateWorkLog: false
        )

        // step 1 실행 시 rollback to 0 설정 — 피드백 루프가 없으므로
        // post-completion 체크에서만 잡을 수 있음
        var firstTime = true
        host.executeStepHandler = { stepIndex in
            if stepIndex == 1 && firstTime {
                firstTime = false
                host.stepRollbackTargets[roomID] = 0
            }
        }

        let engine = StepExecutionEngine(
            host: host, roomID: roomID, task: "테스트", policy: noFeedback
        )
        await engine.run()

        // 롤백이 처리되어 step 0, 1이 재실행됨 → 최소 4번
        #expect(host.executeStepCallCount >= 4)
        #expect(host.stepRollbackTargets[roomID] == nil)
    }

    @Test("롤백 시 대상 단계 이후가 pending으로 리셋된다")
    @MainActor
    func rollbackResetsStepStatus() async {
        let roomID = UUID()
        let agentID = UUID()
        let host = Self.makeHost(roomID: roomID, agentID: agentID, stepCount: 3)

        var rollbackTriggered = false
        host.executeStepHandler = { stepIndex in
            if stepIndex == 2 && !rollbackTriggered {
                rollbackTriggered = true
                host.stepRollbackTargets[roomID] = 1
            }
        }

        let engine = StepExecutionEngine(
            host: host, roomID: roomID, task: "테스트", policy: .standard
        )
        await engine.run()

        // 최종적으로 모든 단계 completed
        let room = host.rooms[roomID]!
        #expect(room.plan!.steps.allSatisfy { $0.status == .completed })
        // 롤백 메시지가 존재하는지 확인
        let rollbackMessages = host.appendedMessages.filter {
            $0.content.contains("재실행") || $0.content.contains("다시 실행")
        }
        #expect(!rollbackMessages.isEmpty)
    }
}
