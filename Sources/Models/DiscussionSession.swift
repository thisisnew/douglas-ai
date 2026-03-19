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
    /// Research intent 전용 구조화된 브리핑
    var researchBriefing: ResearchBriefing?
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

    // MARK: - 도메인 메서드 (불변식 보호)

    /// 추가 라운드 진행 가능 여부
    var canContinue: Bool {
        currentRound < maxRounds
    }

    /// 토론이 완료되었는지 (briefing이 생성됨)
    var isCompleted: Bool {
        briefing != nil || researchBriefing != nil
    }

    /// 토론 모드 선택 — DebateClassifier에 위임 + 결과를 세션에 저장
    mutating func selectDebateMode(
        topic: String,
        agentRoles: [String],
        modifiers: Set<IntentModifier>
    ) {
        let mode = DebateClassifier.classify(topic: topic, agentRoles: agentRoles, modifiers: modifiers)
        self.debateMode = mode
        self.maxRounds = mode.maxRounds
    }

    /// 라운드 완료 — 요약 기록 + 다음 라운드 전진 (마지막이면 전진 안 함)
    mutating func completeRound(summary: RoundSummary) {
        roundSummaries.append(summary)
        if currentRound < maxRounds - 1 {
            currentRound = currentRound + 1
        }
    }

    /// 라운드 전진 — 음수 방지
    mutating func advanceRound(to round: Int) {
        guard round >= 0 else { return }
        currentRound = round
    }

    /// 체크포인트 설정 (사용자 피드백 대기)
    mutating func setCheckpoint() {
        isCheckpoint = true
    }

    /// 체크포인트 해제
    mutating func clearCheckpoint() {
        isCheckpoint = false
    }

    /// 결정 기록 추가
    mutating func addDecision(_ entry: DecisionEntry) {
        decisionLog.append(entry)
    }

    /// 라운드 요약 추가
    mutating func addRoundSummary(_ summary: RoundSummary) {
        roundSummaries.append(summary)
    }

    /// 기존 라운드 요약 교체 (피드백 반영 시)
    mutating func updateRoundSummary(at index: Int, with summary: RoundSummary) {
        guard index >= 0, index < roundSummaries.count else { return }
        roundSummaries[index] = summary
    }

    /// 토론 종결 — briefing + 전문 아카이브 설정
    mutating func conclude(briefing: RoomBriefing, fullLog: String) {
        self.briefing = briefing
        self.fullDiscussionLog = fullLog
    }

    init(
        currentRound: Int = 0,
        isCheckpoint: Bool = false,
        decisionLog: [DecisionEntry] = [],
        artifacts: [DiscussionArtifact] = [],
        briefing: RoomBriefing? = nil,
        researchBriefing: ResearchBriefing? = nil,
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
        self.researchBriefing = researchBriefing
        self.fullDiscussionLog = fullDiscussionLog
        self.debateMode = debateMode
        self.actionItems = actionItems
        self.maxRounds = maxRounds
        self.roundSummaries = roundSummaries
    }

    // MARK: - Codable (하위 호환)

    private enum CodingKeys: String, CodingKey {
        case currentRound, isCheckpoint, decisionLog, artifacts, briefing, researchBriefing
        case fullDiscussionLog, debateMode, actionItems, maxRounds, roundSummaries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentRound = try container.decode(Int.self, forKey: .currentRound)
        isCheckpoint = try container.decode(Bool.self, forKey: .isCheckpoint)
        decisionLog = try container.decode([DecisionEntry].self, forKey: .decisionLog)
        artifacts = try container.decode([DiscussionArtifact].self, forKey: .artifacts)
        briefing = try container.decodeIfPresent(RoomBriefing.self, forKey: .briefing)
        researchBriefing = try container.decodeIfPresent(ResearchBriefing.self, forKey: .researchBriefing)
        fullDiscussionLog = try container.decodeIfPresent(String.self, forKey: .fullDiscussionLog)
        debateMode = try container.decodeIfPresent(DebateMode.self, forKey: .debateMode)
        actionItems = try container.decodeIfPresent([ActionItem].self, forKey: .actionItems)
        maxRounds = try container.decodeIfPresent(Int.self, forKey: .maxRounds) ?? 2
        roundSummaries = try container.decodeIfPresent([RoundSummary].self, forKey: .roundSummaries) ?? []
    }
}
