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

        room.workflowState = WorkflowState(intent: .task, needsPlan: true, currentPhase: .plan)
        #expect(room.intent == .task)
        #expect(room.needsPlan == true)
        #expect(room.currentPhase == WorkflowPhase.plan)
    }

    @Test("Room.workflowState - 개별 프로퍼티와 동기화")
    func roomWorkflowStateSync() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.intent = .discussion
        room.currentPhase = .assemble
        room.completedPhases = [.intake]

        let state = room.workflowState
        #expect(state.intent == .discussion)
        #expect(state.currentPhase == .assemble)
        #expect(state.completedPhases.contains(.intake))
    }

    @Test("Room.clarifyContext - get/set 왕복")
    func roomClarifyContextAccessor() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.clarifyContext = ClarifyContext(
            clarifySummary: "요약",
            clarifyQuestionCount: 5
        )
        #expect(room.clarifySummary == "요약")
        #expect(room.clarifyQuestionCount == 5)
    }

    @Test("Room.projectContext - get/set 왕복")
    func roomProjectContextAccessor() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.projectContext = ProjectContext(
            projectPaths: ["/new/path"],
            buildCommand: "swift build"
        )
        #expect(room.projectPaths == ["/new/path"])
        #expect(room.buildCommand == "swift build")
    }

    @Test("Room.projectContext - 개별 프로퍼티 수정 후 동기화")
    func roomProjectContextIndividualSync() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user, projectPaths: ["/original"])
        room.worktreePath = "/tmp/wt"

        let ctx = room.projectContext
        #expect(ctx.projectPaths == ["/original"])
        #expect(ctx.worktreePath == "/tmp/wt")
    }
}
