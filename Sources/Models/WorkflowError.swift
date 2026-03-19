import Foundation

/// 워크플로우 도메인 에러 — 페이즈 실행, 승인, LLM 호출 등에서 발생하는 구조화된 에러
enum WorkflowError: Error, Equatable {
    /// 적합한 에이전트를 찾지 못함
    case agentUnmatchable(reason: String)
    /// 승인 대기 시간 초과
    case approvalTimeout(roomID: UUID)
    /// 사용자가 승인을 거부함
    case approvalRejected(roomID: UUID)
    /// 허용되지 않는 페이즈 전이
    case phaseTransitionInvalid(from: WorkflowPhase?, to: WorkflowPhase)
    /// LLM 호출 실패
    case llmFailure(agentID: UUID, detail: String)
    /// 빌드 실패
    case buildFailure(output: String)
    /// QA/테스트 실패
    case qaFailure(output: String)
    /// 워크플로우 전체 시간 초과
    case workflowTimeout
    /// 사용자 취소
    case cancelled
}
