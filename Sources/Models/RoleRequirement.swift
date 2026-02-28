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

    enum Priority: String, Codable {
        case required    // 필수
        case optional    // 선택
    }

    enum MatchStatus: String, Codable {
        case pending     // 매칭 전
        case matched     // 기존 에이전트 매칭됨
        case suggested   // 새 에이전트 생성 제안됨
        case unmatched   // 매칭 실패
    }

    init(
        id: UUID = UUID(),
        roleName: String,
        reason: String = "",
        priority: Priority = .required,
        matchedAgentID: UUID? = nil,
        status: MatchStatus = .pending
    ) {
        self.id = id
        self.roleName = roleName
        self.reason = reason
        self.priority = priority
        self.matchedAgentID = matchedAgentID
        self.status = status
    }
}
