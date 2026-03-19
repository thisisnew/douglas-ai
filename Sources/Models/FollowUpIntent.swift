import Foundation

// MARK: - 후속 의도

/// 후속 메시지의 의도 유형 — 결정론적 분기의 핵심
enum FollowUpIntent: Equatable {
    // 구현 계열
    case implementAll                    // "구현하자" — 전체 actionItems 실행
    case implementPartial([Int])         // "1번이랑 3번만 하자" — 선택 실행
    case retryExecution                  // "다시 해줘" — 같은 계획 재실행

    // 토론 계열
    case continueDiscussion              // "더 논의하자" — 이어서 토론
    case modifyAndDiscuss(String)        // "1번 방향을 바꿔서" — 부분 재토론
    case restartDiscussion               // "다시 논의하자" — 전체 재토론
    case reviewResult                    // "검토해줘" — 구현 결과 리뷰

    // 기타
    case documentResult                  // "정리해줘" — 문서화
    case newTask                         // 이전 맥락과 무관한 새 작업
}

// MARK: - 컨텍스트 캐리오버 정책

/// 후속 사이클에서 어떤 컨텍스트를 유지/리셋할지 결정
struct ContextCarryoverPolicy: Equatable {
    let keepIntakeData: Bool
    let keepAgents: Bool
    let keepBriefing: Bool
    let keepActionItems: Bool
    let keepDecisionLog: Bool
    let keepWorkLog: Bool
    let keepStepResults: Bool

    /// 각 FollowUpIntent에 대해 결정론적 정책 반환
    static func policy(for intent: FollowUpIntent) -> ContextCarryoverPolicy {
        switch intent {
        case .implementAll:
            return ContextCarryoverPolicy(
                keepIntakeData: true, keepAgents: false, keepBriefing: true,
                keepActionItems: true, keepDecisionLog: true,
                keepWorkLog: false, keepStepResults: false
            )
        case .implementPartial:
            return ContextCarryoverPolicy(
                keepIntakeData: true, keepAgents: false, keepBriefing: true,
                keepActionItems: true,  // 필터링은 별도 처리
                keepDecisionLog: true,
                keepWorkLog: false, keepStepResults: false
            )
        case .continueDiscussion:
            return ContextCarryoverPolicy(
                keepIntakeData: true, keepAgents: true, keepBriefing: true,
                keepActionItems: true, keepDecisionLog: true,
                keepWorkLog: false, keepStepResults: false
            )
        case .modifyAndDiscuss:
            return ContextCarryoverPolicy(
                keepIntakeData: true, keepAgents: true, keepBriefing: true,
                keepActionItems: true,  // 수정 대상만 변경
                keepDecisionLog: true,
                keepWorkLog: false, keepStepResults: false
            )
        case .restartDiscussion:
            return ContextCarryoverPolicy(
                keepIntakeData: true, keepAgents: true, keepBriefing: false,
                keepActionItems: false, keepDecisionLog: false,
                keepWorkLog: false, keepStepResults: false
            )
        case .reviewResult:
            return ContextCarryoverPolicy(
                keepIntakeData: true, keepAgents: true, keepBriefing: true,
                keepActionItems: true, keepDecisionLog: true,
                keepWorkLog: true, keepStepResults: true
            )
        case .documentResult:
            return ContextCarryoverPolicy(
                keepIntakeData: true, keepAgents: true, keepBriefing: true,
                keepActionItems: true, keepDecisionLog: true,
                keepWorkLog: true, keepStepResults: true
            )
        case .retryExecution:
            return ContextCarryoverPolicy(
                keepIntakeData: true, keepAgents: true, keepBriefing: true,
                keepActionItems: true, keepDecisionLog: true,
                keepWorkLog: false, keepStepResults: false
            )
        case .newTask:
            return ContextCarryoverPolicy(
                keepIntakeData: true, keepAgents: false, keepBriefing: false,
                keepActionItems: false, keepDecisionLog: false,
                keepWorkLog: false, keepStepResults: false
            )
        }
    }
}

// MARK: - 후속 결정

/// FollowUpClassifier의 출력 — 후속 사이클의 모든 결정을 포함
struct FollowUpDecision: Equatable {
    let intent: FollowUpIntent
    let resolvedWorkflowIntent: WorkflowIntent
    let contextPolicy: ContextCarryoverPolicy
    let skipPhases: Set<WorkflowPhase>
    let needsPlan: Bool
}
