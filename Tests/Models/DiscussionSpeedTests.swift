import Testing
import Foundation
@testable import DOUGLAS

@Suite("Discussion Speed Optimization Tests")
struct DiscussionSpeedTests {

    // MARK: - 개선 1: 토론 라운드 상한

    @Test("DebateMode.dialectic.maxRounds == 3")
    func dialecticMaxRounds() {
        #expect(DebateMode.dialectic.maxRounds == 3)
    }

    @Test("DebateMode.collaborative.maxRounds == 2")
    func collaborativeMaxRounds() {
        #expect(DebateMode.collaborative.maxRounds == 2)
    }

    @Test("DebateMode.coordination.maxRounds == 2")
    func coordinationMaxRounds() {
        #expect(DebateMode.coordination.maxRounds == 2)
    }

    @Test("DiscussionSession.maxRounds 기본값은 2")
    func sessionDefaultMaxRounds() {
        let session = DiscussionSession()
        #expect(session.maxRounds == 2)
    }

    @Test("DiscussionSession.maxRounds는 debateMode에 따라 설정 가능")
    func sessionMaxRoundsFromMode() {
        var session = DiscussionSession()
        session.debateMode = .dialectic
        session.maxRounds = DebateMode.dialectic.maxRounds
        #expect(session.maxRounds == 3)
    }

    @Test("DiscussionSession Codable 하위 호환 — maxRounds 없는 데이터")
    func sessionCodableBackcompat() throws {
        // maxRounds 없는 기존 JSON
        let json = """
        {"currentRound": 1, "isCheckpoint": false, "decisionLog": [], "artifacts": []}
        """
        let data = json.data(using: .utf8)!
        let session = try JSONDecoder().decode(DiscussionSession.self, from: data)
        #expect(session.maxRounds == 2)
        #expect(session.currentRound == 1)
    }

    @Test("DiscussionSession Codable 라운드트립 — maxRounds 포함")
    func sessionCodableRoundtrip() throws {
        var session = DiscussionSession()
        session.maxRounds = 3
        session.debateMode = .dialectic

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(DiscussionSession.self, from: data)
        #expect(decoded.maxRounds == 3)
        #expect(decoded.debateMode == .dialectic)
    }

    // MARK: - 개선 5: 라운드별 구조화 상태

    @Test("RoundSummary 생성 및 Codable")
    func roundSummaryCodable() throws {
        let summary = RoundSummary(
            round: 0,
            agentPositions: [
                AgentPosition(agentName: "백엔드", stance: "REST가 적합"),
                AgentPosition(agentName: "프론트", stance: "GraphQL이 유연"),
            ],
            agreements: ["기본 CRUD는 REST"],
            disagreements: ["실시간 데이터 처리 방식"],
            userFeedback: nil
        )

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(RoundSummary.self, from: data)
        #expect(decoded.round == 0)
        #expect(decoded.agentPositions.count == 2)
        #expect(decoded.agentPositions[0].stance == "REST가 적합")
        #expect(decoded.agreements == ["기본 CRUD는 REST"])
        #expect(decoded.disagreements == ["실시간 데이터 처리 방식"])
    }

    @Test("DiscussionSession.roundSummaries 기본값 빈 배열")
    func sessionRoundSummariesDefault() {
        let session = DiscussionSession()
        #expect(session.roundSummaries.isEmpty)
    }

    @Test("DiscussionSession.roundSummaries Codable 하위 호환")
    func roundSummariesBackcompat() throws {
        let json = """
        {"currentRound": 0, "isCheckpoint": false, "decisionLog": [], "artifacts": []}
        """
        let data = json.data(using: .utf8)!
        let session = try JSONDecoder().decode(DiscussionSession.self, from: data)
        #expect(session.roundSummaries.isEmpty)
    }

    @Test("RoundSummary.asSummaryText — 요약 텍스트 생성")
    func roundSummaryText() {
        let summary = RoundSummary(
            round: 0,
            agentPositions: [
                AgentPosition(agentName: "백엔드", stance: "REST가 적합"),
                AgentPosition(agentName: "프론트", stance: "GraphQL이 유연"),
            ],
            agreements: ["기본 CRUD는 REST"],
            disagreements: ["실시간 처리 방식"],
            userFeedback: "REST 기반으로 가자"
        )

        let text = summary.asSummaryText
        #expect(text.contains("백엔드: REST가 적합"))
        #expect(text.contains("프론트: GraphQL이 유연"))
        #expect(text.contains("합의: 기본 CRUD는 REST"))
        #expect(text.contains("쟁점: 실시간 처리 방식"))
        #expect(text.contains("피드백: REST 기반으로 가자"))
    }
}
