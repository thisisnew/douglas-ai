import Foundation

/// 토론 중 도출된 합의/결정사항 기록
struct DecisionEntry: Codable, Identifiable {
    let id: UUID
    let round: Int              // 합의가 이루어진 토론 라운드
    let decision: String        // 합의 내용
    let supporters: [String]    // 동의 에이전트 이름
    let createdAt: Date

    init(
        id: UUID = UUID(),
        round: Int,
        decision: String,
        supporters: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.round = round
        self.decision = decision
        self.supporters = supporters
        self.createdAt = createdAt
    }
}
