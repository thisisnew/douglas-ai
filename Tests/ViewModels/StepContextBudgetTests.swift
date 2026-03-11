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
            systemPromptSize: 1000,   // 토큰 단위
            historySize: 500          // 토큰 단위
        )
        #expect(result.artifactContext.contains("짧은 산출물 내용"))
        #expect(!result.shouldTrimHistory)
    }

    @Test("산출물 합계가 예산 초과 시 요약 모드 전환")
    func artifactContext_overBudget_truncatesToSummary() {
        // 대형 산출물 생성 (30K 토큰 예산 초과하도록)
        let largeContent = String(repeating: "A", count: 60_000) // ~15K tokens
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
            systemPromptSize: 2000,   // 토큰 단위
            historySize: 1000         // 토큰 단위
        )
        // 전체 내용이 아닌 요약 포함
        #expect(result.artifactContext.contains("산출물 요약"))
        #expect(result.artifactContext.contains("API 명세서"))
        // 원본 60K 내용이 아닌 200자 프리뷰
        #expect(!result.artifactContext.contains(String(repeating: "A", count: 1000)))
    }

    @Test("시스템 프롬프트 + history가 예산 초과 시 history 축소 플래그")
    func historyAndArtifact_overBudget_bothReduced() {
        // systemPromptSize + historySize > 30K 토큰
        let result = StepContextBudget.apply(
            artifacts: [],
            systemPromptSize: 18_000,  // 토큰 단위
            historySize: 15_000        // 토큰 단위
        )
        // 산출물 없지만 전체 초과 → shouldTrimHistory
        #expect(result.shouldTrimHistory)
    }

    // MARK: - 토큰 기반 예산

    @Test("tokenBudget 값이 30K 토큰")
    func tokenBudgetValue() {
        #expect(StepContextBudget.tokenBudget == 30_000)
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

    // MARK: - buildRoomHistory afterIndex

    @Test("buildRoomHistory — afterIndex 이후 메시지만 반환")
    @MainActor func buildRoomHistory_afterIndex_filtersOldMessages() {
        let manager = RoomManager()
        let room = manager.createRoom(title: "테스트", agentIDs: [], createdBy: .user)

        // 토론 단계 메시지 3개
        for i in 0..<3 {
            manager.appendMessage(
                ChatMessage(role: .assistant, content: "토론 \(i)", messageType: .text),
                to: room.id
            )
        }
        let offset = manager.rooms.first(where: { $0.id == room.id })!.messages.count

        // Build 단계 메시지 2개
        for i in 0..<2 {
            manager.appendMessage(
                ChatMessage(role: .assistant, content: "빌드 \(i)", messageType: .text),
                to: room.id
            )
        }

        // afterIndex 없이 → 전체 5개
        let allHistory = manager.buildRoomHistory(roomID: room.id, limit: 10)
        #expect(allHistory.count == 5)

        // afterIndex 적용 → Build 메시지만 2개
        let buildHistory = manager.buildRoomHistory(roomID: room.id, limit: 10, afterIndex: offset)
        #expect(buildHistory.count == 2)
        #expect(buildHistory[0].content == "빌드 0")
        #expect(buildHistory[1].content == "빌드 1")
    }

    @Test("buildRoomHistory — afterIndex nil이면 기존 동작")
    @MainActor func buildRoomHistory_afterIndex_nil_returnsAll() {
        let manager = RoomManager()
        let room = manager.createRoom(title: "테스트", agentIDs: [], createdBy: .user)
        manager.appendMessage(
            ChatMessage(role: .user, content: "메시지", messageType: .text),
            to: room.id
        )
        let history = manager.buildRoomHistory(roomID: room.id, limit: 10, afterIndex: nil)
        #expect(history.count == 1)
    }
}
