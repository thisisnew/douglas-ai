import Testing
import Foundation
@testable import DOUGLAS

@Suite("DebateStrategy Tests")
struct DebateStrategyTests {

    // MARK: - DebateMode

    @Test("DebateMode 3가지 케이스 존재")
    func debateModeAllCases() {
        #expect(DebateMode.allCases.count == 3)
        #expect(DebateMode.allCases.contains(.dialectic))
        #expect(DebateMode.allCases.contains(.collaborative))
        #expect(DebateMode.allCases.contains(.coordination))
    }

    @Test("DebateMode → Strategy 팩토리")
    func debateModeStrategy() {
        #expect(DebateMode.dialectic.strategy.mode == .dialectic)
        #expect(DebateMode.collaborative.strategy.mode == .collaborative)
        #expect(DebateMode.coordination.strategy.mode == .coordination)
    }

    @Test("DebateMode Codable")
    func debateModeCodable() throws {
        let mode = DebateMode.dialectic
        let data = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(DebateMode.self, from: data)
        #expect(decoded == mode)
    }

    // MARK: - Dialectic Strategy

    @Test("dialectic: 최소 턴 수 = 2")
    func dialecticMinTurns() {
        let strategy = DialecticStrategy()
        #expect(strategy.minimumTurns == 2)
    }

    @Test("dialectic: [합의] 태그 → 합의")
    func dialecticExplicitConsensus() {
        let strategy = DialecticStrategy()
        #expect(strategy.isConsensus(response: "모두 동의합니다. [합의]") == true)
    }

    @Test("dialectic: [전면 동의] 태그 → 합의")
    func dialecticFullAgreement() {
        let strategy = DialecticStrategy()
        #expect(strategy.isConsensus(response: "[전면 동의] A의 지적 수용.") == true)
    }

    @Test("dialectic: [이의] 태그 → 비합의")
    func dialecticObjection() {
        let strategy = DialecticStrategy()
        #expect(strategy.isConsensus(response: "[이의] 이 부분은 재검토 필요") == false)
    }

    @Test("dialectic: 약한 동의 → 비합의")
    func dialecticWeakAgreement() {
        let strategy = DialecticStrategy()
        #expect(strategy.isConsensus(response: "좋은 방향입니다. 저도 이렇게 생각합니다.") == false)
        #expect(strategy.isConsensus(response: "좋은 계획이네요.") == false)
        #expect(strategy.isConsensus(response: "동의합니다") == false)
    }

    @Test("dialectic: 태그 없는 일반 응답 → 비합의")
    func dialecticNoTag() {
        let strategy = DialecticStrategy()
        #expect(strategy.isConsensus(response: "이 접근에는 확장성 문제가 있을 수 있습니다.") == false)
    }

    @Test("dialectic: 쟁점 추출")
    func dialecticExtractConcerns() {
        let strategy = DialecticStrategy()
        let response = "이 설계에는 리스크가 있습니다. 확장성 문제점이 보입니다. 대안으로 마이크로서비스를 고려해야 합니다."
        let concerns = strategy.extractConcerns(from: response)
        #expect(concerns.count >= 2)
    }

    @Test("dialectic: Turn 2 프롬프트에 역할과 의견 포함")
    func dialecticTurn2Prompt() {
        let strategy = DialecticStrategy()
        let prompt = strategy.turn2Prompt(agentRole: "백엔드 개발자", otherOpinions: "REST가 좋겠습니다")
        #expect(prompt.contains("백엔드 개발자"))
        #expect(prompt.contains("REST가 좋겠습니다"))
        #expect(prompt.contains("빈틈"))
        #expect(prompt.contains("대안"))
    }

    // MARK: - Collaborative Strategy

    @Test("collaborative: 최소 턴 수 = 1")
    func collaborativeMinTurns() {
        let strategy = CollaborativeStrategy()
        #expect(strategy.minimumTurns == 1)
    }

    @Test("collaborative: [합의] 태그 → 합의")
    func collaborativeExplicitConsensus() {
        let strategy = CollaborativeStrategy()
        #expect(strategy.isConsensus(response: "[합의] 인터페이스 확정") == true)
    }

    @Test("collaborative: 약한 동의 + 근거 있음 → 합의")
    func collaborativeWeakAgreeWithReason() {
        let strategy = CollaborativeStrategy()
        #expect(strategy.isConsensus(response: "좋은 방향입니다. 왜냐하면 프론트에서 캐싱이 가능하기 때문입니다.") == true)
    }

    @Test("collaborative: 약한 동의 + 근거 없음 → 비합의")
    func collaborativeWeakAgreeNoReason() {
        let strategy = CollaborativeStrategy()
        #expect(strategy.isConsensus(response: "좋은 방향입니다.") == false)
    }

    @Test("collaborative: 갭/연결점 추출")
    func collaborativeExtractConcerns() {
        let strategy = CollaborativeStrategy()
        let response = "API 연결 지점이 명확하지 않습니다. 인증 부분에 회색 지대가 있습니다."
        let concerns = strategy.extractConcerns(from: response)
        #expect(concerns.count >= 1)
    }

    @Test("collaborative: Turn 2 프롬프트에 연결 지점 키워드")
    func collaborativeTurn2Prompt() {
        let strategy = CollaborativeStrategy()
        let prompt = strategy.turn2Prompt(agentRole: "프론트엔드", otherOpinions: "API는 REST로")
        #expect(prompt.contains("연결 지점"))
        #expect(prompt.contains("회색 지대"))
        #expect(prompt.contains("영향"))
    }

    // MARK: - Coordination Strategy

    @Test("coordination: 최소 턴 수 = 1")
    func coordinationMinTurns() {
        let strategy = CoordinationStrategy()
        #expect(strategy.minimumTurns == 1)
    }

    @Test("coordination: 약한 동의 → 합의")
    func coordinationWeakAgreement() {
        let strategy = CoordinationStrategy()
        #expect(strategy.isConsensus(response: "좋은 방향입니다.") == true)
        #expect(strategy.isConsensus(response: "동의합니다") == true)
        #expect(strategy.isConsensus(response: "그렇게 하죠") == true)
        #expect(strategy.isConsensus(response: "좋습니다") == true)
    }

    @Test("coordination: [이의] → 비합의")
    func coordinationObjection() {
        let strategy = CoordinationStrategy()
        #expect(strategy.isConsensus(response: "[이의] 일정이 촉박합니다") == false)
    }

    @Test("coordination: 쟁점 추출 → 빈 배열")
    func coordinationNoConcerns() {
        let strategy = CoordinationStrategy()
        let concerns = strategy.extractConcerns(from: "리스크가 있지만 진행합시다")
        #expect(concerns.isEmpty)
    }

    // MARK: - DecisionEntry.concerns

    @Test("DecisionEntry에 concerns 필드 추가")
    func decisionEntryConcerns() {
        let entry = DecisionEntry(
            round: 1,
            decision: "REST API 채택",
            supporters: ["백엔드", "프론트"],
            concerns: ["확장성 리스크", "캐싱 전략 미결"]
        )
        #expect(entry.concerns?.count == 2)
        #expect(entry.concerns?.first == "확장성 리스크")
    }

    @Test("DecisionEntry concerns nil 기본값")
    func decisionEntryNoConcerns() {
        let entry = DecisionEntry(round: 1, decision: "합의")
        #expect(entry.concerns == nil)
    }

    // MARK: - DiscussionSession 확장

    @Test("DiscussionSession에 debateMode 필드")
    func discussionSessionDebateMode() {
        var session = DiscussionSession()
        session.debateMode = .dialectic
        #expect(session.debateMode == .dialectic)
    }

    @Test("DiscussionSession에 actionItems 필드")
    func discussionSessionActionItems() {
        var session = DiscussionSession()
        let item = ActionItem(description: "API 설계", suggestedAgentName: "백엔드", priority: 1)
        session.actionItems = [item]
        #expect(session.actionItems?.count == 1)
        #expect(session.actionItems?.first?.description == "API 설계")
    }

    @Test("DiscussionSession 기본값 유지")
    func discussionSessionDefaults() {
        let session = DiscussionSession()
        #expect(session.currentRound == 0)
        #expect(session.debateMode == nil)
        #expect(session.actionItems == nil)
    }
}
