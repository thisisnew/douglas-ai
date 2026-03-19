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

    // MARK: - userFacingMessage

    @Test("userFacingMessage — 모든 케이스가 비어있지 않음")
    func userFacingMessage_nonEmpty() {
        let id = UUID()
        let cases: [WorkflowError] = [
            .agentUnmatchable(reason: "없음"),
            .approvalTimeout(roomID: id),
            .approvalRejected(roomID: id),
            .phaseTransitionInvalid(from: .design, to: .build),
            .llmFailure(agentID: id, detail: "timeout"),
            .buildFailure(output: "error log"),
            .qaFailure(output: "test failed"),
            .workflowTimeout,
            .cancelled
        ]
        for error in cases {
            #expect(!error.userFacingMessage.isEmpty, "userFacingMessage should not be empty for \(error)")
        }
    }

    @Test("userFacingMessage — 한국어 포함")
    func userFacingMessage_korean() {
        #expect(WorkflowError.workflowTimeout.userFacingMessage.contains("제한 시간"))
        #expect(WorkflowError.cancelled.userFacingMessage.contains("취소"))
        #expect(WorkflowError.approvalRejected(roomID: UUID()).userFacingMessage.contains("거부"))
    }

    @Test("userFacingMessage — buildFailure output 100자 제한")
    func userFacingMessage_buildOutputTruncation() {
        let longOutput = String(repeating: "x", count: 200)
        let msg = WorkflowError.buildFailure(output: longOutput).userFacingMessage
        #expect(msg.count < 200)
    }

    @Test("userFacingMessage — phaseTransitionInvalid from nil")
    func userFacingMessage_phaseTransitionFromNil() {
        let msg = WorkflowError.phaseTransitionInvalid(from: nil, to: .design).userFacingMessage
        #expect(msg.contains("시작"))
    }
}
