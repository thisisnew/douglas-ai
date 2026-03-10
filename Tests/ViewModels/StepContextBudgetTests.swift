import Testing
import Foundation
@testable import DOUGLAS

@Suite("Step Context Budget Tests")
struct StepContextBudgetTests {

    // MARK: - 산출물 예산

    @Test("산출물 합계가 예산 이내면 전체 포함")
    func artifactContext_underBudget_includesFullContent() {
        let artifact = DiscussionArtifact(
            type: .generic, title: "분석 결과",
            content: "짧은 산출물 내용", producedBy: "테스트"
        )
        let result = StepContextBudget.apply(
            artifacts: [artifact],
            systemPromptSize: 5000,
            historySize: 3000
        )
        #expect(result.artifactContext.contains("짧은 산출물 내용"))
        #expect(!result.shouldTrimHistory)
    }

    @Test("산출물 합계가 예산 초과 시 요약 모드 전환")
    func artifactContext_overBudget_truncatesToSummary() {
        // 100K 초과하도록 대형 산출물 생성
        let largeContent = String(repeating: "A", count: 60_000)
        let artifact1 = DiscussionArtifact(
            type: .apiSpec, title: "API 명세서",
            content: largeContent, producedBy: "백엔드"
        )
        let artifact2 = DiscussionArtifact(
            type: .taskBreakdown, title: "작업 분해",
            content: largeContent, producedBy: "프론트"
        )
        let result = StepContextBudget.apply(
            artifacts: [artifact1, artifact2],
            systemPromptSize: 5000,
            historySize: 3000
        )
        // 전체 내용이 아닌 요약 포함
        #expect(result.artifactContext.contains("산출물 요약"))
        #expect(result.artifactContext.contains("API 명세서"))
        // 원본 60K 내용이 아닌 200자 프리뷰
        #expect(!result.artifactContext.contains(String(repeating: "A", count: 1000)))
    }

    @Test("산출물 요약 후에도 초과 시 history도 축소 플래그")
    func historyAndArtifact_overBudget_bothReduced() {
        // system prompt + history가 이미 90K
        let result = StepContextBudget.apply(
            artifacts: [],
            systemPromptSize: 50_000,
            historySize: 55_000
        )
        // 산출물 없지만 전체 초과 → shouldTrimHistory
        #expect(result.shouldTrimHistory)
    }

    // MARK: - buildRoomHistory 메시지 크기 제한

    @Test("buildRoomHistory — 2000자 초과 메시지 절단")
    @MainActor func buildRoomHistory_truncatesLongMessages() {
        let manager = RoomManager()
        let room = manager.createRoom(title: "테스트", agentIDs: [], createdBy: .user)
        let longContent = String(repeating: "B", count: 5000)
        let msg = ChatMessage(role: .assistant, content: longContent, messageType: .text)
        manager.appendMessage(msg, to: room.id)

        let history = manager.buildRoomHistory(roomID: room.id, limit: 5)
        #expect(history.count == 1)
        let content = history[0].content ?? ""
        #expect(content.count <= 2001) // 2000 + "…"
        #expect(content.hasSuffix("…"))
    }
}
