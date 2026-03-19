import Foundation

/// 작업 항목의 완료 상태
enum ActionItemCompletionStatus: String, Codable, Equatable {
    case pending      // 미착수
    case inProgress   // 진행 중
    case completed    // 완료
}

/// 토론에서 도출된 작업 항목 — 후속 구현 사이클에서 계획 생성의 기초
struct ActionItem: Identifiable, Equatable {
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
    /// 완료 상태 (부분 구현 후 후속 토론에서 구분용)
    var completionStatus: ActionItemCompletionStatus

    init(
        id: UUID = UUID(),
        description: String,
        suggestedAgentName: String? = nil,
        priority: Int = 2,
        rationale: String? = nil,
        dependencies: [Int]? = nil,
        completionStatus: ActionItemCompletionStatus = .pending
    ) {
        self.id = id
        self.description = description
        self.suggestedAgentName = suggestedAgentName
        self.priority = priority
        self.rationale = rationale
        self.dependencies = dependencies
        self.completionStatus = completionStatus
    }
}

// MARK: - Jira 연동

extension ActionItem {
    /// Jira 서브태스크 생성용 payload 딕셔너리
    func toJiraSubtaskPayload(parentKey: String, projectKey: String) -> [String: String] {
        let summary = String(description.prefix(255))
        var desc = description
        if let rationale = rationale, !rationale.isEmpty {
            desc += "\n\n근거: \(rationale)"
        }
        if let agentName = suggestedAgentName {
            desc += "\n담당 제안: \(agentName)"
        }
        return [
            "parentKey": parentKey,
            "projectKey": projectKey,
            "summary": summary,
            "description": desc,
        ]
    }
}

// MARK: - Codable (하위 호환: completionStatus 누락 시 .pending)

extension ActionItem: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        suggestedAgentName = try container.decodeIfPresent(String.self, forKey: .suggestedAgentName)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 2
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        dependencies = try container.decodeIfPresent([Int].self, forKey: .dependencies)
        completionStatus = try container.decodeIfPresent(ActionItemCompletionStatus.self, forKey: .completionStatus) ?? .pending
    }
}
