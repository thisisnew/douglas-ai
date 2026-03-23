import Testing
import Foundation
@testable import DOUGLAS

@Suite("PhaseContextSummary Tests")
struct PhaseContextSummaryTests {

    // MARK: - WorkflowState.phaseSummaries 저장/조회

    @Test("phaseSummaries 초기값은 빈 딕셔너리")
    func initialEmpty() {
        let state = WorkflowState()
        #expect(state.phaseSummaries.isEmpty)
    }

    @Test("phaseSummaries 저장 후 조회")
    func storeAndRetrieve() {
        var state = WorkflowState()
        state.phaseSummaries[.understand] = "목표: API 서버 리팩토링, 제약: Swift 5.9"
        state.phaseSummaries[.design] = "3턴 토론 완료, 합의: REST → GraphQL 전환"

        #expect(state.phaseSummaries[.understand] == "목표: API 서버 리팩토링, 제약: Swift 5.9")
        #expect(state.phaseSummaries[.design]?.contains("GraphQL") == true)
        #expect(state.phaseSummaries[.build] == nil)
    }

    @Test("phaseSummaries Codable 라운드트립")
    func codableRoundTrip() throws {
        var state = WorkflowState()
        state.intent = .task
        state.phaseSummaries[.understand] = "TaskBrief 생성 완료"
        state.phaseSummaries[.assemble] = "백엔드 + 프론트 매칭"

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkflowState.self, from: data)

        #expect(decoded.phaseSummaries.count == 2)
        #expect(decoded.phaseSummaries[.understand] == "TaskBrief 생성 완료")
        #expect(decoded.phaseSummaries[.assemble] == "백엔드 + 프론트 매칭")
    }

    @Test("phaseSummaries 하위 호환: 필드 없어도 디코딩 성공")
    func backwardCompatible() throws {
        // phaseSummaries 필드가 없는 JSON
        let json = """
        {"intent":"task","autoDocOutput":false,"needsPlan":false,"completedPhases":["understand"]}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkflowState.self, from: data)
        #expect(decoded.phaseSummaries.isEmpty)
        #expect(decoded.intent == .task)
    }

    // MARK: - PhaseContextSummarizer

    @Test("summarizePhase — understand 요약 생성")
    func summarizeUnderstand() {
        var room = makeTestRoom()
        room.setTaskBrief(TaskBrief(
            goal: "API 리팩토링",
            constraints: ["Swift 5.9"],
            successCriteria: ["빌드 통과"],
            nonGoals: ["UI 변경 없음"],
            overallRisk: .medium,
            outputType: .code
        ))
        let summary = PhaseContextSummarizer.summarize(phase: .understand, room: room)
        #expect(summary.contains("API 리팩토링"))
        #expect(summary.contains("Swift 5.9"))
    }

    @Test("summarizePhase — design 요약에 토론 요약 포함")
    func summarizeDesign() {
        var room = makeTestRoom()
        room.discussion.briefing = RoomBriefing(
            summary: "REST vs GraphQL 논의 결과 GraphQL 채택",
            keyDecisions: ["GraphQL 채택"],
            agentResponsibilities: [:],
            openIssues: []
        )
        let summary = PhaseContextSummarizer.summarize(phase: .design, room: room)
        #expect(summary.contains("GraphQL"))
    }

    @Test("summarizePhase — build 요약에 계획 정보 포함")
    func summarizeBuild() {
        var room = makeTestRoom()
        room.plan = RoomPlan(summary: "3단계 API 구현", estimatedSeconds: 600, steps: [
            RoomStep(text: "모델 정의"),
            RoomStep(text: "라우터 구현"),
            RoomStep(text: "테스트 작성"),
        ])
        let summary = PhaseContextSummarizer.summarize(phase: .build, room: room)
        #expect(summary.contains("3단계"))
    }

    @Test("summarizePhase — 정보 없는 페이즈 → 빈 문자열")
    func summarizeEmpty() {
        let room = makeTestRoom()
        let summary = PhaseContextSummarizer.summarize(phase: .review, room: room)
        #expect(summary.isEmpty)
    }

    @Test("buildContextForPhase — 이전 페이즈 요약을 조합")
    func buildContextCombinesSummaries() {
        var room = makeTestRoom()
        room.recordWorkflowPhaseSummary(phase: .understand, summary: "목표: API 리팩토링")
        room.recordWorkflowPhaseSummary(phase: .assemble, summary: "에이전트: 백엔드, 프론트")

        let context = PhaseContextSummarizer.buildContextForPhase(.design, room: room)
        #expect(context.contains("API 리팩토링"))
        #expect(context.contains("백엔드"))
    }

    @Test("buildContextForPhase — 요약 없으면 빈 문자열")
    func buildContextEmpty() {
        let room = makeTestRoom()
        let context = PhaseContextSummarizer.buildContextForPhase(.understand, room: room)
        #expect(context.isEmpty)
    }

    // MARK: - Helper

    private func makeTestRoom() -> Room {
        Room(
            title: "테스트",
            assignedAgentIDs: [],
            createdBy: .user
        )
    }
}
