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

    // MARK: - Phase 2 개선 3a: 시스템 프롬프트 캐시

    @Test("SystemPromptCache — 같은 키는 캐시 hit")
    func systemPromptCacheHit() {
        var cache = SystemPromptCache()
        let agentID = UUID()
        let ruleIDs: Set<UUID> = [UUID(), UUID()]
        cache.set("프롬프트 A", agentID: agentID, activeRuleIDs: ruleIDs)
        let result = cache.get(agentID: agentID, activeRuleIDs: ruleIDs)
        #expect(result == "프롬프트 A")
    }

    @Test("SystemPromptCache — 다른 ruleIDs는 캐시 miss")
    func systemPromptCacheMiss() {
        var cache = SystemPromptCache()
        let agentID = UUID()
        cache.set("프롬프트 A", agentID: agentID, activeRuleIDs: [UUID()])
        let result = cache.get(agentID: agentID, activeRuleIDs: [UUID()])
        #expect(result == nil)
    }

    @Test("SystemPromptCache — nil ruleIDs 지원")
    func systemPromptCacheNilRules() {
        var cache = SystemPromptCache()
        let agentID = UUID()
        cache.set("프롬프트 B", agentID: agentID, activeRuleIDs: nil)
        let result = cache.get(agentID: agentID, activeRuleIDs: nil)
        #expect(result == "프롬프트 B")
    }

    @Test("SystemPromptCache — invalidate 시 전부 제거")
    func systemPromptCacheInvalidate() {
        var cache = SystemPromptCache()
        let agentID = UUID()
        cache.set("프롬프트", agentID: agentID, activeRuleIDs: nil)
        cache.invalidateAll()
        #expect(cache.get(agentID: agentID, activeRuleIDs: nil) == nil)
    }

    // MARK: - Phase 2 개선 4: 토론 문맥 압축

    @Test("DiscussionHistoryFilter — .discussionRound 제외")
    func historyFilterExcludesRoundMarkers() {
        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: "── 토론 라운드 1 ──", messageType: .discussionRound),
            ChatMessage(role: .assistant, content: "백엔드 의견", agentName: "백엔드", messageType: .discussion),
            ChatMessage(role: .assistant, content: "프론트 의견", agentName: "프론트", messageType: .discussion),
            ChatMessage(role: .system, content: "── 토론 라운드 2 ──", messageType: .discussionRound),
            ChatMessage(role: .assistant, content: "백엔드 추가", agentName: "백엔드", messageType: .discussion),
        ]
        let filtered = DiscussionHistoryFilter.filterForHistory(messages)
        #expect(filtered.count == 3)
        #expect(filtered.allSatisfy { $0.messageType != .discussionRound })
    }

    @Test("DiscussionHistoryFilter — suffix(20) 계산 시 토론 발언만 카운트")
    func historyFilterSuffixCountsOnlyDiscussion() {
        // 25개 메시지: 5개 .discussionRound + 20개 .discussion
        var messages: [ChatMessage] = []
        for round in 0..<5 {
            messages.append(ChatMessage(role: .system, content: "라운드 \(round)", messageType: .discussionRound))
            for i in 0..<4 {
                messages.append(ChatMessage(role: .assistant, content: "발언 \(round)-\(i)", agentName: "에이전트\(i)", messageType: .discussion))
            }
        }
        let filtered = DiscussionHistoryFilter.filterForHistory(messages)
        // .discussionRound 5개 제외, .discussion 20개 → suffix(20) = 20개
        #expect(filtered.count == 20)
        #expect(filtered.allSatisfy { $0.messageType == .discussion || $0.messageType == .text })
    }

    @Test("DiscussionHistoryFilter — .text(사용자 입력)는 포함")
    func historyFilterIncludesUserText() {
        let messages: [ChatMessage] = [
            ChatMessage(role: .user, content: "사용자 질문", messageType: .text),
            ChatMessage(role: .assistant, content: "에이전트 답변", agentName: "백엔드", messageType: .discussion),
        ]
        let filtered = DiscussionHistoryFilter.filterForHistory(messages)
        #expect(filtered.count == 2)
        #expect(filtered[0].content == "사용자 질문")
    }

    @Test("DiscussionHistoryBuilder — 이전 라운드를 RoundSummary로 압축")
    func historyBuilderCompressesPreviousRounds() {
        let roundSummaries = [
            RoundSummary(
                round: 0,
                agentPositions: [
                    AgentPosition(agentName: "백엔드", stance: "REST 선호"),
                    AgentPosition(agentName: "프론트", stance: "GraphQL 선호"),
                ],
                agreements: ["기본 CRUD는 REST"],
                disagreements: ["실시간 처리"],
                userFeedback: nil
            )
        ]
        let currentRound = 1
        let currentRoundMessages: [ChatMessage] = [
            ChatMessage(role: .assistant, content: "라운드2 발언", agentName: "백엔드", messageType: .discussion),
        ]

        let result = DiscussionHistoryBuilder.build(
            currentRound: currentRound,
            roundSummaries: roundSummaries,
            currentRoundMessages: currentRoundMessages,
            currentAgentName: nil
        )
        // 이전 라운드 요약 1개 + 현재 라운드 발언 1개 = 2개
        #expect(result.count == 2)
        #expect(result[0].content.contains("라운드 1 요약"))
        #expect(result[0].content.contains("REST 선호"))
        #expect(result[1].content.contains("라운드2 발언"))
    }

    @Test("DiscussionHistoryBuilder — 요약 없으면 전체 메시지 사용")
    func historyBuilderNoSummaries() {
        let messages: [ChatMessage] = [
            ChatMessage(role: .assistant, content: "발언1", agentName: "A", messageType: .discussion),
            ChatMessage(role: .assistant, content: "발언2", agentName: "B", messageType: .discussion),
        ]
        let result = DiscussionHistoryBuilder.build(
            currentRound: 0,
            roundSummaries: [],
            currentRoundMessages: messages,
            currentAgentName: "A"
        )
        #expect(result.count == 2)
        // A의 발언은 assistant, B의 발언은 user
        #expect(result[0].role == "assistant")
        #expect(result[1].role == "user")
    }

    // MARK: - Phase 3 개선 5: 라운드별 RoundSummary 생성

    @Test("RoundSummaryGenerator — 에이전트 발언에서 stance 추출 (첫 문장)")
    func generatorExtractsStance() {
        let messages: [ChatMessage] = [
            ChatMessage(role: .assistant, content: "REST API가 이 경우 적합합니다. 이유는 단순성과 캐싱입니다.", agentName: "백엔드", messageType: .discussion),
            ChatMessage(role: .assistant, content: "GraphQL이 유연합니다. 클라이언트 요구에 맞춤 가능합니다.", agentName: "프론트", messageType: .discussion),
        ]
        let summary = RoundSummaryGenerator.generate(
            round: 0,
            messages: messages,
            decisionLog: [],
            userFeedback: nil
        )
        #expect(summary.agentPositions.count == 2)
        #expect(summary.agentPositions[0].agentName == "백엔드")
        #expect(summary.agentPositions[0].stance.contains("REST"))
        #expect(summary.agentPositions[1].agentName == "프론트")
        #expect(summary.agentPositions[1].stance.contains("GraphQL"))
    }

    @Test("RoundSummaryGenerator — DecisionLog에서 agreements 추출")
    func generatorExtractsAgreements() {
        let decisionLog = [
            DecisionEntry(round: 0, decision: "기본 CRUD는 REST", supporters: ["백엔드", "프론트"]),
            DecisionEntry(round: 1, decision: "다른 라운드 결정", supporters: ["백엔드"]),
        ]
        let summary = RoundSummaryGenerator.generate(
            round: 0,
            messages: [],
            decisionLog: decisionLog,
            userFeedback: nil
        )
        #expect(summary.agreements == ["기본 CRUD는 REST"])
    }

    @Test("RoundSummaryGenerator — [반대]/[우려] 태그에서 disagreements 추출")
    func generatorExtractsDisagreements() {
        let messages: [ChatMessage] = [
            ChatMessage(role: .assistant, content: "성능이 좋습니다. [반대] 실시간 처리에서는 WebSocket이 필요합니다.", agentName: "백엔드", messageType: .discussion),
            ChatMessage(role: .assistant, content: "[우려] 보안 측면에서 GraphQL은 쿼리 복잡성 공격에 취약합니다.", agentName: "보안", messageType: .discussion),
        ]
        let summary = RoundSummaryGenerator.generate(
            round: 0,
            messages: messages,
            decisionLog: [],
            userFeedback: nil
        )
        #expect(summary.disagreements.count == 2)
        #expect(summary.disagreements[0].contains("WebSocket"))
        #expect(summary.disagreements[1].contains("쿼리 복잡성"))
    }

    @Test("RoundSummaryGenerator — 사용자 피드백 포함")
    func generatorIncludesUserFeedback() {
        let summary = RoundSummaryGenerator.generate(
            round: 0,
            messages: [],
            decisionLog: [],
            userFeedback: "REST로 가자"
        )
        #expect(summary.userFeedback == "REST로 가자")
    }

    @Test("RoundSummaryGenerator — 빈 메시지 처리")
    func generatorHandlesEmptyMessages() {
        let summary = RoundSummaryGenerator.generate(
            round: 0,
            messages: [],
            decisionLog: [],
            userFeedback: nil
        )
        #expect(summary.agentPositions.isEmpty)
        #expect(summary.agreements.isEmpty)
        #expect(summary.disagreements.isEmpty)
        #expect(summary.userFeedback == nil)
    }
}
