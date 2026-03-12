import Foundation

// MARK: - 역할 요구사항

/// Assemble 단계에서 분석가가 산출한 역할 요구사항
struct RoleRequirement: Identifiable, Codable {
    let id: UUID
    let roleName: String            // "백엔드 개발자", "QA 엔지니어" 등
    let reason: String              // 왜 이 역할이 필요한지
    let priority: Priority
    var matchedAgentID: UUID?       // 매칭된 에이전트 ID
    var status: MatchStatus
    var confidence: Double          // 매칭 신뢰도 (0.0~1.0) — Plan C
    var position: WorkflowPosition? // LLM이 지정한 워크플로우 포지션

    enum Priority: String, Codable {
        case required    // 필수
        case optional    // 선택
    }

    enum MatchStatus: String, Codable {
        case pending     // 매칭 전
        case matched     // 기존 에이전트 매칭됨 (confidence >= 0.7)
        case suggested   // 사용자 확인 필요 (0.5 <= confidence < 0.7)
        case unmatched   // 매칭 실패 (confidence < 0.5)
    }

    init(
        id: UUID = UUID(),
        roleName: String,
        reason: String = "",
        priority: Priority = .required,
        matchedAgentID: UUID? = nil,
        status: MatchStatus = .pending,
        confidence: Double = 0,
        position: WorkflowPosition? = nil
    ) {
        self.id = id
        self.roleName = roleName
        self.reason = reason
        self.priority = priority
        self.matchedAgentID = matchedAgentID
        self.status = status
        self.confidence = confidence
        self.position = position
    }

    // MARK: - 상태 전이 (Rich Model)

    /// 매칭 결과 적용 (상태 전이 로직 캡슐화)
    mutating func applyMatch(agent: Agent, confidence: Double, config: MatchScoringConfig = .default) {
        self.confidence = confidence
        self.matchedAgentID = agent.id

        if confidence >= config.autoMatchThreshold {
            self.status = .matched
        } else if confidence >= config.suggestThreshold {
            self.status = .suggested
        } else {
            self.status = .unmatched
            self.matchedAgentID = nil
        }
    }

    /// 매칭 실패 시 상태 초기화
    mutating func markUnmatched() {
        self.status = .unmatched
        self.matchedAgentID = nil
        self.confidence = 0
    }

    /// 매칭 성공 여부 (usedAgentIDs에 추가할지 판단)
    var isEffectivelyMatched: Bool {
        status == .matched || status == .suggested
    }
}
