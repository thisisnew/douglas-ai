import Testing
import Foundation
@testable import DOUGLAS

@Suite("FollowUpClassifier Tests")
struct FollowUpClassifierTests {

    // MARK: - 구현 계열

    @Test("구현하자 + actionItems → implementAll")
    func implementAll() {
        let decision = FollowUpClassifier.classify(
            message: "이제 구현하자",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .implementAll)
        #expect(decision.resolvedWorkflowIntent == .task)
        #expect(decision.needsPlan == true)
        #expect(decision.skipPhases.contains(.understand))
        #expect(decision.skipPhases.contains(.assemble))
    }

    @Test("1번이랑 3번만 하자 → implementPartial")
    func implementPartial() {
        let decision = FollowUpClassifier.classify(
            message: "1번이랑 3번만 구현하자",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .implementPartial([0, 2]))
        #expect(decision.needsPlan == true)
    }

    // MARK: - 토론 계열

    @Test("더 논의하자 → continueDiscussion")
    func continueDiscussion() {
        let decision = FollowUpClassifier.classify(
            message: "더 논의하자",
            previousState: .discussionCompleted,
            hasActionItems: false,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .continueDiscussion)
        #expect(decision.resolvedWorkflowIntent == .discussion)
        #expect(decision.contextPolicy.keepBriefing == true)
    }

    @Test("다시 논의하자 → restartDiscussion")
    func restartDiscussion() {
        let decision = FollowUpClassifier.classify(
            message: "다시 논의하자",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .restartDiscussion)
        #expect(decision.contextPolicy.keepBriefing == false)
        #expect(decision.contextPolicy.keepActionItems == false)
    }

    @Test("방향 바꿔서 → modifyAndDiscuss")
    func modifyAndDiscuss() {
        let decision = FollowUpClassifier.classify(
            message: "1번 방향을 바꿔서 다시 해보자",
            previousState: .discussionCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .modifyAndDiscuss("1번 방향을 바꿔서 다시 해보자"))
    }

    // MARK: - 구현 완료 후

    @Test("검토해줘 → reviewResult")
    func reviewResult() {
        let decision = FollowUpClassifier.classify(
            message: "잘된 건지 검토해줘",
            previousState: .implementCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: true
        )
        #expect(decision.intent == .reviewResult)
        #expect(decision.contextPolicy.keepWorkLog == true)
    }

    @Test("정리해줘 → documentResult")
    func documentResult() {
        let decision = FollowUpClassifier.classify(
            message: "결과 정리해줘",
            previousState: .implementCompleted,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: true
        )
        #expect(decision.intent == .documentResult)
        #expect(decision.resolvedWorkflowIntent == .documentation)
    }

    // MARK: - 실패 후

    @Test("실패 + 다시 해줘 → retryExecution")
    func retryAfterFailure() {
        let decision = FollowUpClassifier.classify(
            message: "다시 해줘",
            previousState: .failed,
            hasActionItems: true,
            hasBriefing: true,
            hasWorkLog: false
        )
        #expect(decision.intent == .retryExecution)
        #expect(decision.needsPlan == false)  // 기존 계획 재사용
        #expect(decision.skipPhases.contains(.design))
    }

    @Test("실패 + 접근 바꿔서 → restartDiscussion")
    func changeApproachAfterFailure() {
        let decision = FollowUpClassifier.classify(
            message: "접근을 바꿔서 해보자",
            previousState: .failed,
            hasActionItems: false,
            hasBriefing: false,
            hasWorkLog: false
        )
        #expect(decision.intent == .restartDiscussion)
    }

    // MARK: - 캐리오버 정책

    @Test("implementAll 정책: briefing/agents/actionItems 유지")
    func implementAllPolicy() {
        let policy = ContextCarryoverPolicy.policy(for: .implementAll)
        #expect(policy.keepIntakeData == true)
        #expect(policy.keepAgents == true)
        #expect(policy.keepBriefing == true)
        #expect(policy.keepActionItems == true)
        #expect(policy.keepWorkLog == false)
    }

    @Test("restartDiscussion 정책: briefing/actionItems/decisionLog 리셋")
    func restartPolicy() {
        let policy = ContextCarryoverPolicy.policy(for: .restartDiscussion)
        #expect(policy.keepIntakeData == true)
        #expect(policy.keepAgents == true)
        #expect(policy.keepBriefing == false)
        #expect(policy.keepActionItems == false)
        #expect(policy.keepDecisionLog == false)
    }

    @Test("newTask 정책: 대부분 리셋")
    func newTaskPolicy() {
        let policy = ContextCarryoverPolicy.policy(for: .newTask)
        #expect(policy.keepIntakeData == true)
        #expect(policy.keepAgents == false)
        #expect(policy.keepBriefing == false)
        #expect(policy.keepActionItems == false)
    }

    // MARK: - 인덱스 파싱

    @Test("'1번이랑 3번' → [0, 2]")
    func parseIndices() {
        let indices = FollowUpClassifier.parseItemIndices(from: "1번이랑 3번만 하자")
        #expect(indices == [0, 2])
    }

    @Test("'첫 번째' → [0]")
    func parseOrdinal() {
        let indices = FollowUpClassifier.parseItemIndices(from: "첫 번째만 해줘")
        #expect(indices == [0])
    }

    @Test("인덱스 없음 → nil")
    func parseNoIndices() {
        let indices = FollowUpClassifier.parseItemIndices(from: "전부 구현하자")
        #expect(indices == nil)
    }
}
