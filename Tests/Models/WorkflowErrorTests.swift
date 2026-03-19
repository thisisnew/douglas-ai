import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkflowError 도메인 에러")
struct WorkflowErrorTests {

    @Test("Equatable — 같은 케이스 비교")
    func equatable_sameCases() {
        let id = UUID()
        #expect(WorkflowError.cancelled == WorkflowError.cancelled)
        #expect(WorkflowError.workflowTimeout == WorkflowError.workflowTimeout)
        #expect(WorkflowError.approvalRejected(roomID: id) == WorkflowError.approvalRejected(roomID: id))
        #expect(WorkflowError.buildFailure(output: "err") == WorkflowError.buildFailure(output: "err"))
    }

    @Test("Equatable — 다른 케이스 비교")
    func equatable_differentCases() {
        #expect(WorkflowError.cancelled != WorkflowError.workflowTimeout)
        #expect(WorkflowError.buildFailure(output: "a") != WorkflowError.buildFailure(output: "b"))
        #expect(WorkflowError.buildFailure(output: "x") != WorkflowError.qaFailure(output: "x"))
    }

    @Test("Error 프로토콜 준수")
    func conformsToError() {
        let error: Error = WorkflowError.cancelled
        #expect(error is WorkflowError)
    }

    @Test("agentUnmatchable reason 보존")
    func agentUnmatchable_preservesReason() {
        let error = WorkflowError.agentUnmatchable(reason: "백엔드 전문가 없음")
        if case .agentUnmatchable(let reason) = error {
            #expect(reason == "백엔드 전문가 없음")
        } else {
            Issue.record("Expected agentUnmatchable")
        }
    }

    @Test("phaseTransitionInvalid from/to 보존")
    func phaseTransitionInvalid_preservesPhases() {
        let error = WorkflowError.phaseTransitionInvalid(from: .design, to: .understand)
        if case .phaseTransitionInvalid(let from, let to) = error {
            #expect(from == .design)
            #expect(to == .understand)
        } else {
            Issue.record("Expected phaseTransitionInvalid")
        }
    }

    @Test("llmFailure agentID/detail 보존")
    func llmFailure_preservesFields() {
        let agentID = UUID()
        let error = WorkflowError.llmFailure(agentID: agentID, detail: "timeout")
        if case .llmFailure(let id, let detail) = error {
            #expect(id == agentID)
            #expect(detail == "timeout")
        } else {
            Issue.record("Expected llmFailure")
        }
    }
}
