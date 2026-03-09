import Foundation

// MARK: - 승인 유형

/// 워크플로우에서 발생하는 승인의 종류
enum ApprovalType: String, Codable {
    case clarifyApproval         // 복명복창 승인
    case teamConfirmation        // 에이전트 구성 확인
    case planApproval            // 계획 승인
    case stepApproval            // 개별 단계 승인 (requiresApproval)
    case lastStepConfirmation    // 마지막 단계 직전 확인
    case deliverApproval         // deferred action 실행 승인
    case designApproval          // design/review 단계 승인
}

// MARK: - 대기 유형

/// Room이 awaitingApproval/awaitingUserInput일 때 "무엇을 기다리는지" 명시
enum AwaitingType: String, Codable {
    case clarification           // 복명복창 승인 대기
    case agentConfirmation       // 에이전트 구성 확인 대기
    case planApproval            // 계획 승인 대기
    case stepApproval            // 개별 단계 승인 대기
    case finalApproval           // 마지막 단계 직전 승인 대기
    case irreversibleStep        // 되돌릴 수 없는 단계 승인 대기
    case deliverApproval         // deferred action 승인 대기
    case designApproval          // design/review 승인 대기
    case userFeedback            // 사용자 피드백 대기 (ask_user)
    case discussionCheckpoint    // 토론 체크포인트 대기
}

// MARK: - AwaitingType → ApprovalType 변환

extension AwaitingType {
    /// 대기 유형에 대응하는 승인 유형 (기록용)
    var toApprovalType: ApprovalType {
        switch self {
        case .clarification:           return .clarifyApproval
        case .agentConfirmation:       return .teamConfirmation
        case .planApproval:            return .planApproval
        case .stepApproval:            return .stepApproval
        case .finalApproval:           return .lastStepConfirmation
        case .irreversibleStep:        return .stepApproval
        case .deliverApproval:         return .deliverApproval
        case .designApproval:          return .designApproval
        case .userFeedback:            return .stepApproval
        case .discussionCheckpoint:    return .stepApproval
        }
    }
}

// MARK: - 승인 정책 (WORKFLOW_SPEC §6.4)

/// 자동 진행 vs 사용자 확인 판단 정책
enum ApprovalPolicy {
    /// 팀 구성 자동 승인 가능 여부
    ///
    /// 자동 진행 조건 (ALL):
    /// - intent 신뢰도 HIGH
    /// - 에이전트 경합 없음 (suggestedAgentCount == 0)
    /// - 저위험 작업 (overallRisk == .low)
    /// - 구현/문서화/복합 아님 (비용이 낮은 작업)
    /// - 단일 에이전트 (복수 에이전트 토론 아님)
    /// - 에이전트가 1명 이상 매칭됨
    static func shouldAutoApproveTeam(
        intentConfidence: ConfidenceLevel,
        intent: WorkflowIntent,
        overallRisk: RiskLevel,
        matchedAgentCount: Int,
        suggestedAgentCount: Int
    ) -> Bool {
        // 에이전트 없으면 자동 진행 불가
        guard matchedAgentCount >= 1 else { return false }
        // intent 신뢰도 HIGH 필수
        guard intentConfidence == .high else { return false }
        // 에이전트 경합 없음
        guard suggestedAgentCount == 0 else { return false }
        // 저위험
        guard overallRisk == .low else { return false }
        // 구현/문서화/복합은 비용이 높음 — 사용자 확인 필수
        switch intent {
        case .task, .documentation, .complex:
            return false
        case .quickAnswer, .discussion, .research:
            break
        }
        // 단일 에이전트만 자동 진행
        guard matchedAgentCount == 1 else { return false }

        return true
    }
}

// MARK: - 승인 기록

/// 승인/거절 이벤트의 영속적 기록
struct ApprovalRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let type: ApprovalType
    let timestamp: Date
    let approved: Bool
    let feedback: String?
    let stepIndex: Int?          // step 승인일 때 해당 단계 인덱스
    let planVersion: Int?        // plan 승인일 때 해당 계획 버전

    init(
        id: UUID = UUID(),
        type: ApprovalType,
        timestamp: Date = Date(),
        approved: Bool,
        feedback: String? = nil,
        stepIndex: Int? = nil,
        planVersion: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.approved = approved
        self.feedback = feedback
        self.stepIndex = stepIndex
        self.planVersion = planVersion
    }
}
