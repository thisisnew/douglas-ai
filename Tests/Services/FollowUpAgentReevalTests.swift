import Testing
import Foundation
@testable import DOUGLAS

@Suite("P1 #6: 후속 사이클 에이전트 역할 재평가")
struct FollowUpAgentReevalTests {

    // MARK: - FollowUpClassifier skipPhases 테스트

    @Test("implementAll + discussionCompleted → assemble 스킵 안 함 (에이전트 재평가 필요)")
    func implementAllAfterDiscussionShouldNotSkipAssemble() {
        let decision = FollowUpClassifier.classify(
            message: "이제 구현하자",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .implementAll)
        #expect(!decision.skipPhases.contains(.assemble),
                "토론→구현 전환 시 assemble을 스킵하면 토론 에이전트가 구현을 담당하게 됨")
        #expect(decision.skipPhases.contains(.understand))
    }

    @Test("implementPartial + discussionCompleted → assemble 스킵 안 함")
    func implementPartialAfterDiscussionShouldNotSkipAssemble() {
        let decision = FollowUpClassifier.classify(
            message: "1번이랑 3번만 구현하자",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .implementPartial([0, 2]))
        #expect(!decision.skipPhases.contains(.assemble))
    }

    @Test("implementAll + implementCompleted → assemble 스킵 (이미 구현 에이전트)")
    func implementAllAfterImplementShouldSkipAssemble() {
        let decision = FollowUpClassifier.classify(
            message: "이제 구현하자",
            previousState: .implementCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: true
        )
        // 이미 구현을 수행한 에이전트이므로 재평가 불필요
        #expect(decision.skipPhases.contains(.assemble))
    }

    @Test("retryExecution → assemble 스킵 유지 (같은 에이전트로 재시도)")
    func retryKeepsAssembleSkip() {
        let decision = FollowUpClassifier.classify(
            message: "다시 해줘",
            previousState: .failed,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .retryExecution)
        #expect(decision.skipPhases.contains(.assemble))
    }

    @Test("continueDiscussion → assemble 스킵 유지 (토론 계속)")
    func continueDiscussionKeepsAssembleSkip() {
        let decision = FollowUpClassifier.classify(
            message: "더 논의하자",
            previousState: .discussionCompleted,
            hasActionItems: false,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .continueDiscussion)
        #expect(decision.skipPhases.contains(.assemble))
    }

    // MARK: - ContextCarryoverPolicy 에이전트 정책

    @Test("implementAll 정책: keepAgents false (재매칭 허용)")
    func implementAllPolicyShouldNotKeepAgents() {
        let policy = ContextCarryoverPolicy.policy(for: .implementAll)
        #expect(policy.keepAgents == false,
                "토론→구현 전환 시 에이전트를 유지하면 부적합 에이전트가 남음")
    }

    @Test("implementPartial 정책: keepAgents false")
    func implementPartialPolicyShouldNotKeepAgents() {
        let policy = ContextCarryoverPolicy.policy(for: .implementPartial([0]))
        #expect(policy.keepAgents == false)
    }

    @Test("continueDiscussion 정책: keepAgents true (토론 계속)")
    func continueDiscussionKeepsAgents() {
        let policy = ContextCarryoverPolicy.policy(for: .continueDiscussion)
        #expect(policy.keepAgents == true)
    }

    @Test("retryExecution 정책: keepAgents true (같은 에이전트 재시도)")
    func retryKeepsAgents() {
        let policy = ContextCarryoverPolicy.policy(for: .retryExecution)
        #expect(policy.keepAgents == true)
    }
}
