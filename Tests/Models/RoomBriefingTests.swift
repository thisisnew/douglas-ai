import Testing
import Foundation
@testable import DOUGLAS

@Suite("RoomBriefing Tests")
struct RoomBriefingTests {

    // MARK: - 기본 초기화

    @Test("기본 초기화")
    func basicInit() {
        let briefing = RoomBriefing(
            summary: "API 인증 시스템을 JWT 기반으로 구현",
            keyDecisions: ["JWT 사용", "Redis 세션 저장"],
            agentResponsibilities: ["백엔드": "API 구현", "QA": "테스트 작성"],
            openIssues: ["토큰 만료 정책 미결"]
        )
        #expect(briefing.summary == "API 인증 시스템을 JWT 기반으로 구현")
        #expect(briefing.keyDecisions.count == 2)
        #expect(briefing.agentResponsibilities.count == 2)
        #expect(briefing.openIssues.count == 1)
    }

    @Test("빈 필드 초기화")
    func emptyFields() {
        let briefing = RoomBriefing(
            summary: "요약만 있음",
            keyDecisions: [],
            agentResponsibilities: [:],
            openIssues: []
        )
        #expect(briefing.summary == "요약만 있음")
        #expect(briefing.keyDecisions.isEmpty)
        #expect(briefing.agentResponsibilities.isEmpty)
        #expect(briefing.openIssues.isEmpty)
    }

    // MARK: - Codable

    @Test("Codable 라운드트립")
    func codableRoundTrip() throws {
        let original = RoomBriefing(
            summary: "테스트 브리핑",
            keyDecisions: ["결정1", "결정2"],
            agentResponsibilities: ["에이전트A": "역할A"],
            openIssues: ["이슈1"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoomBriefing.self, from: data)
        #expect(decoded.summary == original.summary)
        #expect(decoded.keyDecisions == original.keyDecisions)
        #expect(decoded.agentResponsibilities == original.agentResponsibilities)
        #expect(decoded.openIssues == original.openIssues)
    }

    @Test("빈 배열/딕셔너리 Codable")
    func codableEmpty() throws {
        let original = RoomBriefing(
            summary: "빈 브리핑",
            keyDecisions: [],
            agentResponsibilities: [:],
            openIssues: []
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoomBriefing.self, from: data)
        #expect(decoded.summary == "빈 브리핑")
        #expect(decoded.keyDecisions.isEmpty)
        #expect(decoded.agentResponsibilities.isEmpty)
        #expect(decoded.openIssues.isEmpty)
    }

    @Test("한국어 내용 Codable")
    func codableKorean() throws {
        let original = RoomBriefing(
            summary: "사용자 인증 시스템을 JWT 기반으로 구현하기로 합의",
            keyDecisions: ["JWT 토큰 사용", "Redis에 세션 저장", "토큰 만료 시간 24시간"],
            agentResponsibilities: ["백엔드 개발자": "API 엔드포인트 구현", "QA 엔지니어": "통합 테스트 작성"],
            openIssues: ["리프레시 토큰 정책 미결"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoomBriefing.self, from: data)
        #expect(decoded.summary.contains("JWT"))
        #expect(decoded.keyDecisions.count == 3)
        #expect(decoded.agentResponsibilities["백엔드 개발자"] == "API 엔드포인트 구현")
    }

    // MARK: - asContextString

    @Test("전체 필드 컨텍스트 문자열")
    func contextStringFull() {
        let briefing = RoomBriefing(
            summary: "JWT 인증 구현",
            keyDecisions: ["JWT 사용", "Redis 저장"],
            agentResponsibilities: ["백엔드": "API", "QA": "테스트"],
            openIssues: ["만료 정책"]
        )
        let result = briefing.asContextString()
        #expect(result.contains("[요약] JWT 인증 구현"))
        #expect(result.contains("[결정사항]"))
        #expect(result.contains("- JWT 사용"))
        #expect(result.contains("- Redis 저장"))
        #expect(result.contains("[역할 분담]"))
        #expect(result.contains("[미결 사항]"))
        #expect(result.contains("- 만료 정책"))
    }

    @Test("요약만 있을 때 컨텍스트 문자열")
    func contextStringSummaryOnly() {
        let briefing = RoomBriefing(
            summary: "간단한 작업",
            keyDecisions: [],
            agentResponsibilities: [:],
            openIssues: []
        )
        let result = briefing.asContextString()
        #expect(result.contains("[요약] 간단한 작업"))
        #expect(!result.contains("[결정사항]"))
        #expect(!result.contains("[역할 분담]"))
        #expect(!result.contains("[미결 사항]"))
    }

    @Test("미결 사항 없을 때 섹션 생략")
    func contextStringNoOpenIssues() {
        let briefing = RoomBriefing(
            summary: "완료된 작업",
            keyDecisions: ["결정1"],
            agentResponsibilities: ["A": "역할A"],
            openIssues: []
        )
        let result = briefing.asContextString()
        #expect(result.contains("[결정사항]"))
        #expect(result.contains("[역할 분담]"))
        #expect(!result.contains("[미결 사항]"))
    }

    // MARK: - Room.briefing 역호환

    @Test("Room briefing nil 초기값")
    func roomBriefingNilByDefault() {
        let room = Room(
            title: "테스트 방",
            assignedAgentIDs: [UUID()],
            createdBy: .user
        )
        #expect(room.discussion.briefing == nil)
    }

    @Test("Room briefing 없는 JSON 디코딩 (역호환)")
    func roomDecodingWithoutBriefing() throws {
        // briefing 필드가 없는 기존 데이터
        let room = Room(
            title: "구 데이터",
            assignedAgentIDs: [UUID()],
            createdBy: .user
        )
        let data = try JSONEncoder().encode(room)
        // briefing이 nil인 상태로 인코딩 → 디코딩 시 nil
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.discussion.briefing == nil)
        #expect(decoded.title == "구 데이터")
    }

    @Test("Room briefing 포함 Codable 라운드트립")
    func roomBriefingCodable() throws {
        var room = Room(
            title: "브리핑 테스트",
            assignedAgentIDs: [UUID()],
            createdBy: .user
        )
        room.discussionSetBriefing(RoomBriefing(
            summary: "테스트 요약",
            keyDecisions: ["결정A"],
            agentResponsibilities: ["에이전트": "역할"],
            openIssues: []
        ))
        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.discussion.briefing != nil)
        #expect(decoded.discussion.briefing?.summary == "테스트 요약")
        #expect(decoded.discussion.briefing?.keyDecisions == ["결정A"])
    }

    @Test("Room briefing + artifacts 동시 Codable")
    func roomBriefingWithArtifacts() throws {
        var room = Room(
            title: "풀 테스트",
            assignedAgentIDs: [UUID()],
            createdBy: .user
        )
        room.discussionSetBriefing(RoomBriefing(
            summary: "API 설계 완료",
            keyDecisions: ["REST API"],
            agentResponsibilities: [:],
            openIssues: []
        ))
        room.discussionAddArtifact(DiscussionArtifact(
            type: .apiSpec,
            title: "인증 API",
            content: "POST /auth/login",
            producedBy: "백엔드"
        ))
        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.discussion.briefing?.summary == "API 설계 완료")
        #expect(decoded.discussion.artifacts.count == 1)
        #expect(decoded.discussion.artifacts[0].title == "인증 API")
    }
}
