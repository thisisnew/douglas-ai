import Foundation

/// 토론 세션 상태 (라운드, 산출물, 브리핑, 결정 로그)
struct DiscussionSession: Codable {
    var currentRound: Int
    var isCheckpoint: Bool
    var decisionLog: [DecisionEntry]
    var artifacts: [DiscussionArtifact]
    var briefing: RoomBriefing?

    init(
        currentRound: Int = 0,
        isCheckpoint: Bool = false,
        decisionLog: [DecisionEntry] = [],
        artifacts: [DiscussionArtifact] = [],
        briefing: RoomBriefing? = nil
    ) {
        self.currentRound = currentRound
        self.isCheckpoint = isCheckpoint
        self.decisionLog = decisionLog
        self.artifacts = artifacts
        self.briefing = briefing
    }
}
