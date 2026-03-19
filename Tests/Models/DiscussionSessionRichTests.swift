import Testing
import Foundation
@testable import DOUGLAS

@Suite("DiscussionSession Rich Model")
struct DiscussionSessionRichTests {

    // MARK: - canContinue

    @Test("canContinue — 라운드 미달이면 true")
    func canContinue_underMax() {
        var session = DiscussionSession(currentRound: 0, maxRounds: 3)
        #expect(session.canContinue == true)
        session.currentRound = 2
        #expect(session.canContinue == true)
    }

    @Test("canContinue — 최대 라운드 도달이면 false")
    func canContinue_atMax() {
        var session = DiscussionSession(currentRound: 3, maxRounds: 3)
        #expect(session.canContinue == false)
    }

    @Test("canContinue — 최대 라운드 초과이면 false")
    func canContinue_overMax() {
        let session = DiscussionSession(currentRound: 5, maxRounds: 3)
        #expect(session.canContinue == false)
    }

    // MARK: - selectDebateMode

    @Test("selectDebateMode — dialectic 조건 (같은 도메인 겹침)")
    func selectDebateMode_dialectic() {
        var session = DiscussionSession()
        session.selectDebateMode(
            topic: "아키텍처 선택",
            agentRoles: ["백엔드 개발자", "서버 엔지니어", "API 전문가"],
            modifiers: []
        )
        #expect(session.debateMode == .dialectic)
        #expect(session.maxRounds == 3)
    }

    @Test("selectDebateMode — adversarial modifier이면 무조건 dialectic")
    func selectDebateMode_adversarial() {
        var session = DiscussionSession()
        session.selectDebateMode(
            topic: "일반 주제",
            agentRoles: ["프론트엔드", "디자이너"],
            modifiers: [.adversarial]
        )
        #expect(session.debateMode == .dialectic)
        #expect(session.maxRounds == 3)
    }

    @Test("selectDebateMode — collaborative 조건 (다른 도메인)")
    func selectDebateMode_collaborative() {
        var session = DiscussionSession()
        session.selectDebateMode(
            topic: "기능 개발",
            agentRoles: ["백엔드 개발자", "프론트엔드 개발자"],
            modifiers: []
        )
        #expect(session.debateMode == .collaborative)
        #expect(session.maxRounds == 2)
    }

    @Test("selectDebateMode — coordination 조건 (보완적 + 조율 키워드)")
    func selectDebateMode_coordination() {
        var session = DiscussionSession()
        session.selectDebateMode(
            topic: "API 스펙 확정하자",
            agentRoles: ["백엔드 개발자", "프론트엔드 개발자"],
            modifiers: []
        )
        #expect(session.debateMode == .coordination)
        #expect(session.maxRounds == 2)
    }

    // MARK: - completeRound

    @Test("completeRound — 요약 추가 + 라운드 전진")
    func completeRound_advancesAndRecords() {
        var session = DiscussionSession(currentRound: 0, maxRounds: 3)
        let summary = RoundSummary(
            round: 0,
            agentPositions: [AgentPosition(agentName: "Agent A", stance: "찬성")],
            agreements: ["합의 1"],
            disagreements: [],
            userFeedback: nil
        )

        session.completeRound(summary: summary)

        #expect(session.roundSummaries.count == 1)
        #expect(session.roundSummaries[0].round == 0)
        #expect(session.currentRound == 1)
    }

    @Test("completeRound — maxRounds-1 라운드에서는 전진하지 않음")
    func completeRound_lastRound_noAdvance() {
        // maxRounds=3이면 라운드 0,1,2 실행. currentRound=2(마지막)에서 completeRound 시 전진 안 함
        var session = DiscussionSession(currentRound: 2, maxRounds: 3)
        let summary = RoundSummary(
            round: 2,
            agentPositions: [],
            agreements: [],
            disagreements: [],
            userFeedback: nil
        )

        session.completeRound(summary: summary)

        #expect(session.roundSummaries.count == 1)
        #expect(session.currentRound == 2)  // 전진하지 않음 (2 < 3-1 == false)
    }

    // MARK: - isCompleted

    @Test("isCompleted — briefing 없으면 false")
    func isCompleted_noBriefing() {
        let session = DiscussionSession()
        #expect(session.isCompleted == false)
    }

    @Test("isCompleted — briefing 있으면 true")
    func isCompleted_withBriefing() {
        var session = DiscussionSession()
        session.briefing = RoomBriefing(
            summary: "결론",
            keyDecisions: [],
            agentResponsibilities: [:],
            openIssues: []
        )
        #expect(session.isCompleted == true)
    }
}
