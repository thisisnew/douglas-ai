import Foundation

// MARK: - 라운드별 구조화 요약

/// 에이전트별 핵심 주장
struct AgentPosition: Codable, Equatable {
    let agentName: String
    let stance: String
}

/// 라운드별 구조화 요약 — 토론 히스토리 압축 + 후속 처리에서 재참조
struct RoundSummary: Codable, Equatable {
    let round: Int
    let agentPositions: [AgentPosition]
    let agreements: [String]
    let disagreements: [String]
    let userFeedback: String?

    /// 이전 라운드 요약을 히스토리에 주입할 때 사용하는 텍스트
    var asSummaryText: String {
        var lines: [String] = ["[라운드 \(round + 1) 요약]"]
        for pos in agentPositions {
            lines.append("- \(pos.agentName): \(pos.stance)")
        }
        for agreement in agreements {
            lines.append("- 합의: \(agreement)")
        }
        for disagreement in disagreements {
            lines.append("- 쟁점: \(disagreement)")
        }
        if let feedback = userFeedback, !feedback.isEmpty {
            lines.append("- 피드백: \(feedback)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 토론 세션

/// 토론 세션 상태 (라운드, 산출물, 브리핑, 결정 로그)
struct DiscussionSession: Codable {
    var currentRound: Int
    var isCheckpoint: Bool
    var decisionLog: [DecisionEntry]
    var artifacts: [DiscussionArtifact]
    var briefing: RoomBriefing?
    /// 토론 전문 아카이브 — 브리핑 요약 전 원본 (다음 단계에서 재참조용)
    var fullDiscussionLog: String?
    /// 토론 유형 — Strategy 패턴으로 Turn 2 프롬프트·합의 기준·쟁점 추출 결정
    var debateMode: DebateMode?
    /// 토론에서 도출된 Action Items (후속 구현 사이클에서 사용)
    var actionItems: [ActionItem]?
    /// 최대 토론 라운드 수 (WORKFLOW_SPEC §10.1, DebateMode.maxRounds에서 결정)
    var maxRounds: Int
    /// 라운드별 구조화 요약 — 이전 라운드 압축 + 후속 처리 재참조
    var roundSummaries: [RoundSummary]

    init(
        currentRound: Int = 0,
        isCheckpoint: Bool = false,
        decisionLog: [DecisionEntry] = [],
        artifacts: [DiscussionArtifact] = [],
        briefing: RoomBriefing? = nil,
        fullDiscussionLog: String? = nil,
        debateMode: DebateMode? = nil,
        actionItems: [ActionItem]? = nil,
        maxRounds: Int = 2,
        roundSummaries: [RoundSummary] = []
    ) {
        self.currentRound = currentRound
        self.isCheckpoint = isCheckpoint
        self.decisionLog = decisionLog
        self.artifacts = artifacts
        self.briefing = briefing
        self.fullDiscussionLog = fullDiscussionLog
        self.debateMode = debateMode
        self.actionItems = actionItems
        self.maxRounds = maxRounds
        self.roundSummaries = roundSummaries
    }

    // MARK: - Codable (하위 호환)

    private enum CodingKeys: String, CodingKey {
        case currentRound, isCheckpoint, decisionLog, artifacts, briefing
        case fullDiscussionLog, debateMode, actionItems, maxRounds, roundSummaries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentRound = try container.decode(Int.self, forKey: .currentRound)
        isCheckpoint = try container.decode(Bool.self, forKey: .isCheckpoint)
        decisionLog = try container.decode([DecisionEntry].self, forKey: .decisionLog)
        artifacts = try container.decode([DiscussionArtifact].self, forKey: .artifacts)
        briefing = try container.decodeIfPresent(RoomBriefing.self, forKey: .briefing)
        fullDiscussionLog = try container.decodeIfPresent(String.self, forKey: .fullDiscussionLog)
        debateMode = try container.decodeIfPresent(DebateMode.self, forKey: .debateMode)
        actionItems = try container.decodeIfPresent([ActionItem].self, forKey: .actionItems)
        maxRounds = try container.decodeIfPresent(Int.self, forKey: .maxRounds) ?? 2
        roundSummaries = try container.decodeIfPresent([RoundSummary].self, forKey: .roundSummaries) ?? []
    }
}
