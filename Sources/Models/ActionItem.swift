import Foundation

/// 토론에서 도출된 작업 항목 — 후속 구현 사이클에서 계획 생성의 기초
struct ActionItem: Codable, Identifiable, Equatable {
    let id: UUID
    /// 작업 설명
    let description: String
    /// 추천 담당 에이전트 이름 (AgentAssigner가 agentID로 매핑)
    let suggestedAgentName: String?
    /// 우선순위 (1=높음, 2=중간, 3=낮음)
    let priority: Int
    /// 도출 근거 (토론에서 왜 이 작업이 필요한지)
    let rationale: String?
    /// 선행 작업 인덱스 (의존성)
    let dependencies: [Int]?

    init(
        id: UUID = UUID(),
        description: String,
        suggestedAgentName: String? = nil,
        priority: Int = 2,
        rationale: String? = nil,
        dependencies: [Int]? = nil
    ) {
        self.id = id
        self.description = description
        self.suggestedAgentName = suggestedAgentName
        self.priority = priority
        self.rationale = rationale
        self.dependencies = dependencies
    }
}
