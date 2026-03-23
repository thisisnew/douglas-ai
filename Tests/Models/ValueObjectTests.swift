import Testing
import Foundation
@testable import DOUGLAS

@Suite("Value Object Tests")
struct ValueObjectTests {

    // MARK: - WorkflowState

    @Test("WorkflowState - 기본값")
    func workflowStateDefaults() {
        let state = WorkflowState()
        #expect(state.intent == nil)
        #expect(state.documentType == nil)
        #expect(state.autoDocOutput == false)
        #expect(state.needsPlan == false)
        #expect(state.currentPhase == nil)
        #expect(state.completedPhases.isEmpty)
    }

    @Test("WorkflowState - 전체 필드 설정")
    func workflowStateFullFields() {
        let state = WorkflowState(
            intent: .task,
            documentType: DocumentType.technicalDesign,
            autoDocOutput: true,
            needsPlan: true,
            currentPhase: WorkflowPhase.plan,
            completedPhases: [.intake, .intent, .clarify]
        )
        #expect(state.intent == .task)
        #expect(state.documentType == DocumentType.technicalDesign)
        #expect(state.autoDocOutput == true)
        #expect(state.needsPlan == true)
        #expect(state.currentPhase == WorkflowPhase.plan)
        #expect(state.completedPhases.count == 3)
    }

    @Test("WorkflowState - Codable 왕복")
    func workflowStateCodable() throws {
        let state = WorkflowState(
            intent: .discussion,
            currentPhase: .assemble,
            completedPhases: [.intake, .intent]
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkflowState.self, from: data)
        #expect(decoded == state)
    }

    @Test("WorkflowState - Equatable")
    func workflowStateEquatable() {
        let a = WorkflowState(intent: .task, needsPlan: true)
        let b = WorkflowState(intent: .task, needsPlan: true)
        #expect(a == b)
    }

    @Test("WorkflowState - Equatable 불일치")
    func workflowStateNotEqual() {
        let a = WorkflowState(intent: .task)
        let b = WorkflowState(intent: .discussion)
        #expect(a != b)
    }

    // MARK: - WorkflowState 도메인 메서드

    @Test("advanceToPhase — 전이 기록 + currentPhase 갱신")
    func advanceToPhase() {
        var state = WorkflowState(currentPhase: .intake)
        state.advanceToPhase(.intent)
        #expect(state.currentPhase == .intent)
        #expect(state.phaseTransitions.count == 1)
        #expect(state.phaseTransitions[0].from == .intake)
        #expect(state.phaseTransitions[0].to == .intent)
    }

    @Test("advanceToPhase — nil에서 시작")
    func advanceFromNil() {
        var state = WorkflowState()
        state.advanceToPhase(.intake)
        #expect(state.currentPhase == .intake)
        #expect(state.phaseTransitions.count == 1)
        #expect(state.phaseTransitions[0].from == nil)
    }

    @Test("completePhase — completedPhases에 추가")
    func completePhase() {
        var state = WorkflowState(currentPhase: .intake)
        state.completePhase(.intake)
        #expect(state.completedPhases.contains(.intake))
    }

    @Test("completePhase — 중복 추가 무해")
    func completePhaseIdempotent() {
        var state = WorkflowState(completedPhases: [.intake])
        state.completePhase(.intake)
        #expect(state.completedPhases.count == 1)
    }

    @Test("clearCurrentPhase — nil로 설정")
    func clearCurrentPhase() {
        var state = WorkflowState(currentPhase: .build)
        state.clearCurrentPhase()
        #expect(state.currentPhase == nil)
    }

    @Test("recordPhaseSummary — 요약 저장")
    func recordPhaseSummary() {
        var state = WorkflowState()
        state.recordPhaseSummary(phase: .intake, summary: "요약 텍스트")
        #expect(state.phaseSummaries[.intake] == "요약 텍스트")
    }

    // MARK: - DiscussionSession 도메인 메서드

    @Test("advanceRound — 라운드 증가")
    func advanceRound() {
        var session = DiscussionSession()
        session.advanceRound(to: 1)
        #expect(session.currentRound == 1)
    }

    @Test("advanceRound — 음수 무시")
    func advanceRoundNegative() {
        var session = DiscussionSession(currentRound: 2)
        session.advanceRound(to: -1)
        #expect(session.currentRound == 2)
    }

    @Test("setCheckpoint/clearCheckpoint")
    func checkpointToggle() {
        var session = DiscussionSession()
        session.setCheckpoint()
        #expect(session.isCheckpoint == true)
        session.clearCheckpoint()
        #expect(session.isCheckpoint == false)
    }

    @Test("addDecision — decisionLog에 추가")
    func addDecision() {
        var session = DiscussionSession()
        let entry = DecisionEntry(round: 0, decision: "동의함", supporters: ["A"])
        session.addDecision(entry)
        #expect(session.decisionLog.count == 1)
        #expect(session.decisionLog[0].decision == "동의함")
    }

    @Test("addRoundSummary — 라운드 요약 추가")
    func addRoundSummary() {
        var session = DiscussionSession()
        let summary = RoundSummary(round: 0, agentPositions: [], agreements: ["합의"], disagreements: [], userFeedback: nil)
        session.addRoundSummary(summary)
        #expect(session.roundSummaries.count == 1)
        #expect(session.roundSummaries[0].agreements == ["합의"])
    }

    @Test("updateRoundSummary — 기존 요약 교체")
    func updateRoundSummary() {
        var session = DiscussionSession()
        let original = RoundSummary(round: 0, agentPositions: [], agreements: [], disagreements: [], userFeedback: nil)
        session.addRoundSummary(original)
        let updated = RoundSummary(round: 0, agentPositions: [], agreements: [], disagreements: [], userFeedback: "피드백")
        session.updateRoundSummary(at: 0, with: updated)
        #expect(session.roundSummaries[0].userFeedback == "피드백")
    }

    @Test("updateRoundSummary — 범위 밖 인덱스 무시")
    func updateRoundSummaryOutOfBounds() {
        var session = DiscussionSession()
        let summary = RoundSummary(round: 0, agentPositions: [], agreements: [], disagreements: [], userFeedback: nil)
        session.updateRoundSummary(at: 5, with: summary)
        #expect(session.roundSummaries.isEmpty)
    }

    @Test("conclude — briefing + fullLog 설정")
    func conclude() {
        var session = DiscussionSession()
        let briefing = RoomBriefing(summary: "요약", keyDecisions: [], agentResponsibilities: [:], openIssues: [])
        session.conclude(briefing: briefing, fullLog: "전문")
        #expect(session.briefing?.summary == "요약")
        #expect(session.fullDiscussionLog == "전문")
    }

    // MARK: - ClarifyContext

    @Test("ClarifyContext - 기본값")
    func clarifyContextDefaults() {
        let ctx = ClarifyContext()
        #expect(ctx.intakeData == nil)
        #expect(ctx.clarifySummary == nil)
        #expect(ctx.clarifyQuestionCount == 0)
        #expect(ctx.assumptions == nil)
        #expect(ctx.userAnswers == nil)
        #expect(ctx.delegationInfo == nil)
        #expect(ctx.playbook == nil)
    }

    @Test("ClarifyContext - 일부 필드 설정")
    func clarifyContextPartialFields() {
        let ctx = ClarifyContext(
            clarifySummary: "사용자가 REST API 서버를 구현하려 합니다.",
            clarifyQuestionCount: 3
        )
        #expect(ctx.clarifySummary == "사용자가 REST API 서버를 구현하려 합니다.")
        #expect(ctx.clarifyQuestionCount == 3)
    }

    @Test("ClarifyContext - Codable 왕복")
    func clarifyContextCodable() throws {
        let ctx = ClarifyContext(
            clarifySummary: "요약",
            clarifyQuestionCount: 2
        )
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(ClarifyContext.self, from: data)
        #expect(decoded.clarifySummary == ctx.clarifySummary)
        #expect(decoded.clarifyQuestionCount == ctx.clarifyQuestionCount)
    }

    // MARK: - ProjectContext

    @Test("ProjectContext - 기본값")
    func projectContextDefaults() {
        let ctx = ProjectContext()
        #expect(ctx.projectPaths.isEmpty)
        #expect(ctx.worktreePath == nil)
        #expect(ctx.buildCommand == nil)
        #expect(ctx.testCommand == nil)
    }

    @Test("ProjectContext - 전체 필드 설정")
    func projectContextFullFields() {
        let ctx = ProjectContext(
            projectPaths: ["/path/to/project"],
            worktreePath: "/tmp/worktree",
            buildCommand: "swift build",
            testCommand: "swift test"
        )
        #expect(ctx.projectPaths == ["/path/to/project"])
        #expect(ctx.worktreePath == "/tmp/worktree")
        #expect(ctx.buildCommand == "swift build")
        #expect(ctx.testCommand == "swift test")
    }

    @Test("ProjectContext - Codable 왕복")
    func projectContextCodable() throws {
        let ctx = ProjectContext(
            projectPaths: ["/a", "/b"],
            buildCommand: "make"
        )
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(ProjectContext.self, from: data)
        #expect(decoded == ctx)
    }

    @Test("ProjectContext - Equatable")
    func projectContextEquatable() {
        let a = ProjectContext(projectPaths: ["/x"])
        let b = ProjectContext(projectPaths: ["/x"])
        #expect(a == b)
    }

    // MARK: - Room 값 객체 접근자 통합

    @Test("Room.workflowState - get/set 왕복")
    func roomWorkflowStateAccessor() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        #expect(room.workflowState.intent == nil)

        room.setWorkflowIntent(.task)
        room.setWorkflowNeedsPlan(true)
        room.setWorkflowCurrentPhase(.plan)
        #expect(room.workflowState.intent == .task)
        #expect(room.workflowState.needsPlan == true)
        #expect(room.workflowState.currentPhase == WorkflowPhase.plan)
    }

    @Test("Room.workflowState - 개별 프로퍼티와 동기화")
    func roomWorkflowStateSync() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.setWorkflowIntent(.discussion)
        room.setWorkflowCurrentPhase(.assemble)
        room.setWorkflowCompletedPhases([.intake])

        let state = room.workflowState
        #expect(state.intent == .discussion)
        #expect(state.currentPhase == .assemble)
        #expect(state.completedPhases.contains(.intake))
    }

    @Test("Room.clarifyContext - get/set 왕복")
    func roomClarifyContextAccessor() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.setClarifySummary("요약")
        #expect(room.clarifyContext.clarifySummary == "요약")
    }

    @Test("Room.projectContext - get/set 왕복")
    func roomProjectContextAccessor() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.projectContext = ProjectContext(
            projectPaths: ["/new/path"],
            buildCommand: "swift build"
        )
        #expect(room.projectContext.projectPaths == ["/new/path"])
        #expect(room.projectContext.buildCommand == "swift build")
    }

    @Test("Room.projectContext - 개별 프로퍼티 수정 후 동기화")
    func roomProjectContextIndividualSync() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user, projectPaths: ["/original"])
        room.projectContext.worktreePath = "/tmp/wt"

        let ctx = room.projectContext
        #expect(ctx.projectPaths == ["/original"])
        #expect(ctx.worktreePath == "/tmp/wt")
    }

    // MARK: - DiscussionSession

    @Test("DiscussionSession - 기본값")
    func discussionSessionDefaults() {
        let session = DiscussionSession()
        #expect(session.currentRound == 0)
        #expect(session.isCheckpoint == false)
        #expect(session.decisionLog.isEmpty)
        #expect(session.artifacts.isEmpty)
        #expect(session.briefing == nil)
    }

    @Test("DiscussionSession - 필드 설정")
    func discussionSessionFields() {
        let session = DiscussionSession(currentRound: 3, isCheckpoint: true)
        #expect(session.currentRound == 3)
        #expect(session.isCheckpoint == true)
    }

    @Test("DiscussionSession - Codable 왕복")
    func discussionSessionCodable() throws {
        let session = DiscussionSession(currentRound: 2, isCheckpoint: true)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(DiscussionSession.self, from: data)
        #expect(decoded.currentRound == 2)
        #expect(decoded.isCheckpoint == true)
    }

    @Test("Room.discussion - get/set 왕복")
    func roomDiscussionAccessor() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.discussion = DiscussionSession(currentRound: 5, isCheckpoint: true)
        #expect(room.discussion.currentRound == 5)
        #expect(room.discussion.isCheckpoint == true)
    }

    @Test("Room.discussion - 개별 프로퍼티 수정 후 동기화")
    func roomDiscussionSync() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.discussion.currentRound = 3
        room.discussion.isCheckpoint = true
        let session = room.discussion
        #expect(session.currentRound == 3)
        #expect(session.isCheckpoint == true)
    }

    // MARK: - BuildQAState

    @Test("BuildQAState - 기본값")
    func buildQAStateDefaults() {
        let state = BuildQAState()
        #expect(state.buildLoopStatus == nil)
        #expect(state.buildRetryCount == 0)
        #expect(state.maxBuildRetries == 3)
        #expect(state.lastBuildResult == nil)
        #expect(state.qaLoopStatus == nil)
        #expect(state.qaRetryCount == 0)
        #expect(state.maxQARetries == 3)
        #expect(state.lastQAResult == nil)
    }

    @Test("BuildQAState - Codable 왕복")
    func buildQAStateCodable() throws {
        let state = BuildQAState(buildRetryCount: 2, maxBuildRetries: 5)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BuildQAState.self, from: data)
        #expect(decoded.buildRetryCount == 2)
        #expect(decoded.maxBuildRetries == 5)
    }

    @Test("Room.buildQA - get/set 왕복")
    func roomBuildQAAccessor() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.buildQA = BuildQAState(buildRetryCount: 1, qaRetryCount: 2)
        #expect(room.buildQA.buildRetryCount == 1)
        #expect(room.buildQA.qaRetryCount == 2)
    }

    @Test("Room.buildQA - 개별 프로퍼티 동기화")
    func roomBuildQASync() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.buildQA.buildRetryCount = 3
        room.buildQA.maxBuildRetries = 10
        let state = room.buildQA
        #expect(state.buildRetryCount == 3)
        #expect(state.maxBuildRetries == 10)
    }

    // MARK: - WorkflowState.advanceToPhase 전이 검증

    @Test("advanceToPhase — quickAnswer에서 design 전이 거부 (멤버십)")
    func advanceToPhase_quickAnswerToDesign_rejected() {
        var state = WorkflowState(intent: .quickAnswer)
        let ok = state.advanceToPhase(.design)
        #expect(ok == false)
        #expect(state.currentPhase == nil)
    }

    @Test("advanceToPhase — quickAnswer에서 understand → assemble 순서 정상")
    func advanceToPhase_quickAnswerToAssemble_allowed() {
        var state = WorkflowState(intent: .quickAnswer, currentPhase: .understand, completedPhases: [.understand])
        let ok = state.advanceToPhase(.assemble)
        #expect(ok == true)
        #expect(state.currentPhase == .assemble)
    }

    @Test("advanceToPhase — intent nil이면 모든 전이 허용 (레거시 호환)")
    func advanceToPhase_nilIntent_alwaysAllowed() {
        var state = WorkflowState()
        let ok = state.advanceToPhase(.build)
        #expect(ok == true)
        #expect(state.currentPhase == .build)
    }

    @Test("advanceToPhase — withExecution modifier로 discussion에서 build 허용")
    func advanceToPhase_withExecutionModifier_buildAllowed() {
        // discussion + withExecution: understand → assemble → design → build → review → deliver
        var state = WorkflowState(
            intent: .discussion,
            completedPhases: [.understand, .assemble, .design],
            modifiers: [.withExecution]
        )
        let ok = state.advanceToPhase(.build)
        #expect(ok == true)
        #expect(state.currentPhase == .build)
    }

    @Test("advanceToPhase — task에서 design 완료 후 build 전이 허용")
    func advanceToPhase_taskToBuild_allowed() {
        var state = WorkflowState(
            intent: .task, currentPhase: .design,
            completedPhases: [.understand, .assemble, .design]
        )
        let ok = state.advanceToPhase(.build)
        #expect(ok == true)
        #expect(state.currentPhase == .build)
    }

    @Test("advanceToPhase — 첫 phase(understand)는 선행 조건 없이 허용")
    func advanceToPhase_firstPhase_allowed() {
        var state = WorkflowState(intent: .task)
        let ok = state.advanceToPhase(.understand)
        #expect(ok == true)
        #expect(state.currentPhase == .understand)
    }

    @Test("advanceToPhase — 전이 기록이 추가됨")
    func advanceToPhase_recordsTransition() {
        var state = WorkflowState(intent: .task)
        _ = state.advanceToPhase(.understand)
        #expect(state.phaseTransitions.count == 1)
        #expect(state.phaseTransitions[0].to == .understand)
    }

    @Test("advanceToPhase — understand 미완료 상태에서 assemble 전이 거부 (순서)")
    func advanceToPhase_skipUnderstand_rejected() {
        var state = WorkflowState(intent: .task)
        let ok = state.advanceToPhase(.assemble)
        #expect(ok == false)
        #expect(state.currentPhase == nil)
    }

    @Test("advanceToPhase — skipPhases로 완료 처리된 phase는 건너뛰기 허용")
    func advanceToPhase_skippedPhasesTreatedAsComplete() {
        // understand가 skipPhases로 이미 completedPhases에 들어간 상태
        var state = WorkflowState(intent: .task, completedPhases: [.understand])
        let ok = state.advanceToPhase(.assemble)
        #expect(ok == true)
        #expect(state.currentPhase == .assemble)
    }

    // MARK: - WorkflowState.completePhase 검증

    @Test("completePhase — 현재 phase와 일치하면 완료 허용")
    func completePhase_matchingCurrent_allowed() {
        var state = WorkflowState(intent: .task, currentPhase: .understand)
        let ok = state.completePhase(.understand)
        #expect(ok == true)
        #expect(state.completedPhases.contains(.understand))
    }

    @Test("completePhase — 현재 phase와 불일치하면 거부")
    func completePhase_mismatchCurrent_rejected() {
        var state = WorkflowState(intent: .task, currentPhase: .understand)
        let ok = state.completePhase(.deliver)
        #expect(ok == false)
        #expect(!state.completedPhases.contains(.deliver))
    }

    // MARK: - ToolExecutionContext.isAutonomousExecution

    @Test("isAutonomousExecution — build 단계에서 true")
    func isAutonomous_buildPhase() {
        let ctx = ToolExecutionContext(
            roomID: nil, agentsByName: [:], agentListString: "",
            inviteAgent: { _ in false }, currentPhase: .build
        )
        #expect(ctx.isAutonomousExecution == true)
    }

    @Test("isAutonomousExecution — execute 단계에서 true")
    func isAutonomous_executePhase() {
        let ctx = ToolExecutionContext(
            roomID: nil, agentsByName: [:], agentListString: "",
            inviteAgent: { _ in false }, currentPhase: .execute
        )
        #expect(ctx.isAutonomousExecution == true)
    }

    @Test("isAutonomousExecution — design 단계에서 false")
    func isAutonomous_designPhase() {
        let ctx = ToolExecutionContext(
            roomID: nil, agentsByName: [:], agentListString: "",
            inviteAgent: { _ in false }, currentPhase: .design
        )
        #expect(ctx.isAutonomousExecution == false)
    }

    @Test("isAutonomousExecution — nil 단계에서 false (레거시 호환)")
    func isAutonomous_nilPhase() {
        let ctx = ToolExecutionContext(
            roomID: nil, agentsByName: [:], agentListString: "",
            inviteAgent: { _ in false }, currentPhase: nil
        )
        #expect(ctx.isAutonomousExecution == false)
    }

    // MARK: - BuildQAState 도메인 메서드

    @Test("startBuildLoop — status=building, retryCount=0")
    func buildQA_startBuild() {
        var state = BuildQAState()
        state.startBuildLoop()
        #expect(state.buildLoopStatus == .building)
        #expect(state.buildRetryCount == 0)
    }

    @Test("recordBuildSuccess — status=passed, result 저장")
    func buildQA_buildSuccess() {
        var state = BuildQAState()
        state.startBuildLoop()
        let result = BuildResult(success: true, output: "ok", exitCode: 0)
        state.recordBuildSuccess(result: result)
        #expect(state.buildLoopStatus == .passed)
        #expect(state.lastBuildResult?.success == true)
    }

    @Test("recordBuildFailure — retryCount 증가, status=fixing")
    func buildQA_buildFailure() {
        var state = BuildQAState()
        state.startBuildLoop()
        let result = BuildResult(success: false, output: "error", exitCode: 1)
        state.recordBuildFailure(result: result)
        #expect(state.buildRetryCount == 1)
        #expect(state.buildLoopStatus == .fixing)
        #expect(state.lastBuildResult?.success == false)
    }

    @Test("markBuildFailed — status=failed")
    func buildQA_markBuildFailed() {
        var state = BuildQAState()
        state.markBuildFailed()
        #expect(state.buildLoopStatus == .failed)
    }

    @Test("startQALoop — status=testing, retryCount=0")
    func buildQA_startQA() {
        var state = BuildQAState()
        state.startQALoop()
        #expect(state.qaLoopStatus == .testing)
        #expect(state.qaRetryCount == 0)
    }

    @Test("recordQASuccess — status=passed")
    func buildQA_qaSuccess() {
        var state = BuildQAState()
        state.startQALoop()
        let result = QAResult(success: true, output: "pass", exitCode: 0)
        state.recordQASuccess(result: result)
        #expect(state.qaLoopStatus == .passed)
    }

    @Test("recordQAFailure — retryCount 증가, status=analyzing")
    func buildQA_qaFailure() {
        var state = BuildQAState()
        state.startQALoop()
        let result = QAResult(success: false, output: "fail", exitCode: 1)
        state.recordQAFailure(result: result)
        #expect(state.qaRetryCount == 1)
        #expect(state.qaLoopStatus == .analyzing)
    }

    @Test("resetBuild — 초기화")
    func buildQA_resetBuild() {
        var state = BuildQAState()
        state.startBuildLoop()
        state.recordBuildFailure(result: BuildResult(success: false, output: "e", exitCode: 1))
        state.resetBuild()
        #expect(state.buildLoopStatus == nil)
        #expect(state.buildRetryCount == 0)
        #expect(state.lastBuildResult == nil)
    }

    @Test("resetQA — 초기화")
    func buildQA_resetQA() {
        var state = BuildQAState()
        state.startQALoop()
        state.resetQA()
        #expect(state.qaLoopStatus == nil)
        #expect(state.qaRetryCount == 0)
        #expect(state.lastQAResult == nil)
    }
}
