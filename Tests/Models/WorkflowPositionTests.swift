import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkflowPosition Tests")
struct WorkflowPositionTests {

    // MARK: - Helpers

    private func makeAgent(
        name: String,
        persona: String,
        skillTags: [String] = [],
        workModes: Set<WorkMode> = [],
        outputStyles: Set<OutputStyle> = []
    ) -> Agent {
        var agent = Agent(
            name: name,
            persona: persona,
            providerName: "TestProvider",
            modelName: "test-model",
            skillTags: skillTags
        )
        agent.workModes = workModes
        agent.outputStyles = outputStyles
        return agent
    }

    // MARK: - WorkflowPosition enum

    @Test("WorkflowPosition — 12 cases")
    func positionCaseCount() {
        #expect(WorkflowPosition.allCases.count == 12)
    }

    @Test("WorkflowPosition — Codable 라운드트립")
    func positionCodable() throws {
        let position = WorkflowPosition.implementer
        let data = try JSONEncoder().encode(position)
        let decoded = try JSONDecoder().decode(WorkflowPosition.self, from: data)
        #expect(decoded == .implementer)
    }

    @Test("WorkflowPosition — rawValue")
    func positionRawValue() {
        #expect(WorkflowPosition.architect.rawValue == "architect")
        #expect(WorkflowPosition.tester.rawValue == "tester")
        #expect(WorkflowPosition.coordinator.rawValue == "coordinator")
    }

    @Test("WorkflowPosition — displayName 존재")
    func positionDisplayName() {
        for position in WorkflowPosition.allCases {
            #expect(!position.displayName.isEmpty)
        }
    }

    // MARK: - PositionInferenceService (Agent 데이터로 호출)

    @Test("goodPositions — create+execute → implementer, writer")
    func goodPositionsCreateExecute() {
        let agent = makeAgent(
            name: "백엔드 개발자",
            persona: "서버 개발 전문",
            workModes: [.create, .execute]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.implementer))
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.writer))
    }

    @Test("goodPositions — research → researcher, analyst")
    func goodPositionsResearch() {
        let agent = makeAgent(
            name: "리서치 전문가",
            persona: "조사 분석 전문",
            workModes: [.research]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.researcher))
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.analyst))
    }

    @Test("goodPositions — review → reviewer, auditor")
    func goodPositionsReview() {
        let agent = makeAgent(
            name: "코드 리뷰어",
            persona: "코드 리뷰 전문",
            workModes: [.review]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.reviewer))
    }

    @Test("goodPositions — plan → planner, architect")
    func goodPositionsPlan() {
        let agent = makeAgent(
            name: "전략가",
            persona: "전략 기획",
            workModes: [.plan]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.planner))
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.architect))
    }

    @Test("goodPositions — persona '번역' → translator")
    func goodPositionsTranslator() {
        let agent = makeAgent(
            name: "번역 전문가",
            persona: "다국어 번역 및 현지화 전문가",
            workModes: [.create]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.translator))
    }

    @Test("goodPositions — persona 'QA' → tester")
    func goodPositionsQA() {
        let agent = makeAgent(
            name: "QA 엔지니어",
            persona: "QA 및 테스트 자동화 전문",
            workModes: [.review]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.tester))
    }

    @Test("goodPositions — persona '기획' → coordinator")
    func goodPositionsPM() {
        let agent = makeAgent(
            name: "PM",
            persona: "프로젝트 기획 및 관리",
            workModes: [.plan]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.coordinator))
    }

    @Test("goodPositions — persona '법률' → auditor")
    func goodPositionsLegal() {
        let agent = makeAgent(
            name: "법무 전문가",
            persona: "법률 자문 및 컴플라이언스",
            workModes: [.review]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.auditor))
    }

    @Test("goodPositions — persona '아키텍처' → architect")
    func goodPositionsArchitect() {
        let agent = makeAgent(
            name: "아키텍트",
            persona: "시스템 아키텍처 설계 전문",
            workModes: [.plan, .create]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.architect))
    }

    @Test("goodPositions — persona '데이터 분석' → analyst")
    func goodPositionsAnalyst() {
        let agent = makeAgent(
            name: "데이터 분석가",
            persona: "데이터 분석 및 시각화",
            workModes: [.research]
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(.analyst))
    }

    @Test("goodPositions — 빈 workModes → 빈 포지션")
    func goodPositionsEmpty() {
        let agent = makeAgent(
            name: "에이전트",
            persona: "일반",
            workModes: []
        )
        #expect(PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).isEmpty)
    }

    // MARK: - PositionTemplate

    @Test("PositionTemplate — task intent → implementer(required)")
    func templateTask() {
        let slots = PositionTemplate.slots(for: .task)
        #expect(slots.contains(where: { $0.position == .implementer && $0.priority == .required }))
    }

    @Test("PositionTemplate — complex intent → architect + implementer(required)")
    func templateComplex() {
        let slots = PositionTemplate.slots(for: .complex)
        #expect(slots.contains(where: { $0.position == .architect && $0.priority == .required }))
        #expect(slots.contains(where: { $0.position == .implementer && $0.priority == .required }))
    }

    @Test("PositionTemplate — discussion intent → analyst + advisor")
    func templateDiscussion() {
        let slots = PositionTemplate.slots(for: .discussion)
        #expect(slots.contains(where: { $0.position == .analyst }))
        #expect(slots.contains(where: { $0.position == .advisor }))
    }

    @Test("PositionTemplate — research intent → researcher(required)")
    func templateResearch() {
        let slots = PositionTemplate.slots(for: .research)
        #expect(slots.contains(where: { $0.position == .researcher && $0.priority == .required }))
    }

    @Test("PositionTemplate — documentation intent → writer(required)")
    func templateDocumentation() {
        let slots = PositionTemplate.slots(for: .documentation)
        #expect(slots.contains(where: { $0.position == .writer && $0.priority == .required }))
    }

    @Test("PositionTemplate — quickAnswer intent → advisor(required)")
    func templateQuickAnswer() {
        let slots = PositionTemplate.slots(for: .quickAnswer)
        #expect(slots.contains(where: { $0.position == .advisor && $0.priority == .required }))
    }

    // MARK: - Room.agentPositions

    @Test("Room.agentPositions — 기본값 빈 Dictionary")
    func roomPositionsDefault() {
        let room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        #expect(room.agentPositions.isEmpty)
    }

    @Test("Room.agentPositions — Codable 하위 호환 (없는 데이터)")
    func roomPositionsBackcompat() throws {
        // agentPositions 없이 인코딩된 Room → 디코딩 시 빈 Dict
        let room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        // agentPositions가 비어있으면 encode 시 키 자체가 생략됨
        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.agentPositions.isEmpty)
    }

    @Test("Room.agentPositions — Codable 라운드트립")
    func roomPositionsRoundtrip() throws {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        let agentID = UUID()
        room.agentPositions[agentID] = .implementer
        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.agentPositions[agentID] == .implementer)
    }

    // MARK: - Tier2 포지션 보너스

    // MARK: - isDiscussionLike

    @Test("isDiscussionLike — discussion은 true")
    func discussionLikeForDiscussion() {
        #expect(WorkflowIntent.discussion.isDiscussionLike)
    }

    @Test("isDiscussionLike — research는 true")
    func discussionLikeForResearch() {
        #expect(WorkflowIntent.research.isDiscussionLike)
    }

    @Test("isDiscussionLike — task는 false")
    func discussionLikeForTask() {
        #expect(!WorkflowIntent.task.isDiscussionLike)
    }

    @Test("isDiscussionLike — quickAnswer는 false")
    func discussionLikeForQuickAnswer() {
        #expect(!WorkflowIntent.quickAnswer.isDiscussionLike)
    }

    @Test("isDiscussionLike — documentation은 false")
    func discussionLikeForDocumentation() {
        #expect(!WorkflowIntent.documentation.isDiscussionLike)
    }

    @Test("isDiscussionLike — complex는 false")
    func discussionLikeForComplex() {
        #expect(!WorkflowIntent.complex.isDiscussionLike)
    }

    // MARK: - Tier2 포지션 보너스

    @Test("matchByTags — 포지션 일치 에이전트가 더 높은 점수")
    func positionBonusInMatching() {
        // task intent → implementer 필요
        // agent A: create+execute (goodPositions에 implementer 포함)
        // agent B: research (goodPositions에 implementer 미포함)
        let implementerAgent = makeAgent(
            name: "백엔드 A",
            persona: "서버 개발",
            skillTags: ["백엔드"],
            workModes: [.create, .execute]
        )
        let researcherAgent = makeAgent(
            name: "백엔드 B",
            persona: "백엔드 리서치",
            skillTags: ["백엔드"],
            workModes: [.research]
        )
        let (_, confA) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [implementerAgent],
            excluding: [],
            intent: .task
        )
        let (_, confB) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [researcherAgent],
            excluding: [],
            intent: .task
        )
        #expect(confA > confB)
    }
}
