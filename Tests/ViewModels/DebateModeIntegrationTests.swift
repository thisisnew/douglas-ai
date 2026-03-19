import Testing
import Foundation
@testable import DOUGLAS

@Suite("DebateMode Integration Tests")
struct DebateModeIntegrationTests {

    // MARK: - Turn 2 프롬프트가 debateMode 전략에 따라 달라지는지 검증

    @Test("dialectic 모드 → 빈틈/리스크/대안 키워드 포함")
    func dialecticTurn2Prompt() {
        let strategy = DebateMode.dialectic.strategy
        let prompt = strategy.turn2Prompt(agentRole: "백엔드 개발자", otherOpinions: "의견 내용")
        #expect(prompt.contains("빈틈"))
        #expect(prompt.contains("리스크"))
        #expect(prompt.contains("대안"))
    }

    @Test("collaborative 모드 → 연결 지점/회색 지대/영향 키워드 포함")
    func collaborativeTurn2Prompt() {
        let strategy = DebateMode.collaborative.strategy
        let prompt = strategy.turn2Prompt(agentRole: "프론트엔드 개발자", otherOpinions: "의견 내용")
        #expect(prompt.contains("연결 지점"))
        #expect(prompt.contains("회색 지대"))
        #expect(prompt.contains("영향"))
    }

    @Test("coordination 모드 → 보완점/조율 키워드 포함, 동의 허용")
    func coordinationTurn2Prompt() {
        let strategy = DebateMode.coordination.strategy
        let prompt = strategy.turn2Prompt(agentRole: "QA 전문가", otherOpinions: "의견 내용")
        #expect(prompt.contains("보완점") || prompt.contains("조율"))
        #expect(prompt.contains("동의"))
    }

    // MARK: - DebateClassifier → DebateMode → Strategy 파이프라인

    @Test("백엔드+프론트 → collaborative 모드 전략 생성")
    func classifierToStrategy() {
        let mode = DebateClassifier.classify(
            topic: "새 기능 구현",
            agentRoles: ["백엔드 개발자", "프론트엔드 개발자"]
        )
        #expect(mode == .collaborative)
        let strategy = mode.strategy
        #expect(strategy.minimumTurns == 1)
    }

    @Test("같은 도메인 3명 → dialectic 모드 전략 생성")
    func overlappingRolesToDialectic() {
        let mode = DebateClassifier.classify(
            topic: "API 설계 방향",
            agentRoles: ["백엔드 개발자", "서버 엔지니어", "API 설계자"]
        )
        #expect(mode == .dialectic)
        let strategy = mode.strategy
        #expect(strategy.minimumTurns == 2)
    }

    // MARK: - DiscussionSession에 debateMode 저장 검증

    @Test("DiscussionSession.debateMode 설정 및 strategy 접근")
    func sessionDebateMode() {
        var session = DiscussionSession()
        #expect(session.debateMode == nil)

        session.debateMode = .collaborative
        #expect(session.debateMode?.strategy.mode == .collaborative)
        #expect(session.debateMode?.strategy is CollaborativeStrategy)
    }

    // MARK: - FollowUpClassifier → 후속 intent + 정책 통합 검증

    @Test("토론 완료 + '구현하자' → implementAll + task intent")
    func followUpToTask() {
        let decision = FollowUpClassifier.classify(
            message: "이거 구현하자",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .implementAll)
        #expect(decision.resolvedWorkflowIntent == .task)
        #expect(decision.contextPolicy.keepBriefing == true)
        #expect(decision.contextPolicy.keepActionItems == true)
    }

    @Test("구현 완료 + '검토해줘' → reviewResult + workLog 유지")
    func followUpToReview() {
        let decision = FollowUpClassifier.classify(
            message: "결과 검토해줘",
            previousState: .implementCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: true
        )
        #expect(decision.intent == .reviewResult)
        #expect(decision.contextPolicy.keepWorkLog == true)
    }

    @Test("FollowUpDecision.skipPhases가 completedPhases와 호환")
    func skipPhasesCompatibility() {
        let decision = FollowUpClassifier.classify(
            message: "구현하자",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        // discussionCompleted → implementAll: understand만 스킵, assemble은 에이전트 재평가 위해 유지
        #expect(decision.skipPhases.contains(.understand))
        #expect(!decision.skipPhases.contains(.assemble))
        // design은 스킵하지 않음 (계획 생성 필요)
        #expect(!decision.skipPhases.contains(.design))
    }
}
