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

    /// 사용자에게 보여줄 한국어 에러 메시지
    var userFacingMessage: String {
        switch self {
        case .agentUnmatchable(let reason):
            return "적합한 에이전트를 찾지 못했습니다: \(reason)"
        case .approvalTimeout:
            return "승인 대기 시간이 초과되었습니다."
        case .approvalRejected:
            return "승인이 거부되었습니다."
        case .phaseTransitionInvalid(let from, let to):
            return "허용되지 않는 단계 전이입니다: \(from?.displayName ?? "시작") → \(to.displayName)"
        case .llmFailure(_, let detail):
            return "AI 응답 생성에 실패했습니다: \(detail)"
        case .buildFailure(let output):
            return "빌드에 실패했습니다: \(String(output.prefix(100)))"
        case .qaFailure(let output):
            return "QA/테스트에 실패했습니다: \(String(output.prefix(100)))"
        case .workflowTimeout:
            return "워크플로우가 제한 시간을 초과하여 자동 종료되었습니다."
        case .cancelled:
            return "작업이 취소되었습니다."
        }
    }
}
