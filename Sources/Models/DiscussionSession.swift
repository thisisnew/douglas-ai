import Foundation

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

    init(
        currentRound: Int = 0,
        isCheckpoint: Bool = false,
        decisionLog: [DecisionEntry] = [],
        artifacts: [DiscussionArtifact] = [],
        briefing: RoomBriefing? = nil,
        fullDiscussionLog: String? = nil,
        debateMode: DebateMode? = nil,
        actionItems: [ActionItem]? = nil
    ) {
        self.currentRound = currentRound
        self.isCheckpoint = isCheckpoint
        self.decisionLog = decisionLog
        self.artifacts = artifacts
        self.briefing = briefing
        self.fullDiscussionLog = fullDiscussionLog
        self.debateMode = debateMode
        self.actionItems = actionItems
    }
}
