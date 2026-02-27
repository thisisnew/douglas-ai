import Testing
import Foundation
@testable import DOUGLASLib

@Suite("Room Model Tests")
struct RoomTests {

    // MARK: - RoomStatus

    @Test("RoomStatus rawValue")
    func roomStatusRawValues() {
        #expect(RoomStatus.planning.rawValue == "planning")
        #expect(RoomStatus.inProgress.rawValue == "inProgress")
        #expect(RoomStatus.completed.rawValue == "completed")
        #expect(RoomStatus.failed.rawValue == "failed")
    }

    // MARK: - RoomCreator

    @Test("RoomCreator - master")
    func roomCreatorMaster() throws {
        let id = UUID()
        let creator = RoomCreator.master(agentID: id)
        let data = try JSONEncoder().encode(creator)
        let decoded = try JSONDecoder().decode(RoomCreator.self, from: data)
        #expect(decoded == creator)
    }

    @Test("RoomCreator - user")
    func roomCreatorUser() throws {
        let creator = RoomCreator.user
        let data = try JSONEncoder().encode(creator)
        let decoded = try JSONDecoder().decode(RoomCreator.self, from: data)
        #expect(decoded == .user)
    }

    @Test("RoomCreator Equatable")
    func roomCreatorEquatable() {
        let id = UUID()
        #expect(RoomCreator.user == RoomCreator.user)
        #expect(RoomCreator.master(agentID: id) == RoomCreator.master(agentID: id))
        #expect(RoomCreator.user != RoomCreator.master(agentID: id))
    }

    // MARK: - RoomPlan

    @Test("RoomPlan Codable")
    func roomPlanCodable() throws {
        let plan = RoomPlan(summary: "테스트 계획", estimatedSeconds: 300, steps: ["1단계", "2단계"])
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(RoomPlan.self, from: data)
        #expect(decoded.summary == "테스트 계획")
        #expect(decoded.estimatedSeconds == 300)
        #expect(decoded.steps == ["1단계", "2단계"])
    }

    // MARK: - Room

    @Test("Room 기본 초기화")
    func roomInit() {
        let agentIDs = [UUID(), UUID()]
        let room = Room(title: "테스트 방", assignedAgentIDs: agentIDs, createdBy: .user)
        #expect(room.title == "테스트 방")
        #expect(room.assignedAgentIDs.count == 2)
        #expect(room.status == .planning)
        #expect(room.messages.isEmpty)
        #expect(room.plan == nil)
        #expect(room.timerStartedAt == nil)
        #expect(room.timerDurationSeconds == nil)
        #expect(room.completedAt == nil)
        #expect(room.currentStepIndex == 0)
    }

    @Test("Room isActive - planning")
    func roomIsActivePlanning() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .planning)
        #expect(room.isActive == true)
    }

    @Test("Room isActive - inProgress")
    func roomIsActiveInProgress() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        #expect(room.isActive == true)
    }

    @Test("Room isActive - completed")
    func roomIsActiveCompleted() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .completed)
        #expect(room.isActive == false)
    }

    @Test("Room isActive - failed")
    func roomIsActiveFailed() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .failed)
        #expect(room.isActive == false)
    }

    @Test("Room timerDisplayText - 각 상태")
    func roomTimerDisplayText() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .planning)
        #expect(room.timerDisplayText == "계획 중...")

        room.status = .completed
        #expect(room.timerDisplayText == "완료")

        room.status = .failed
        #expect(room.timerDisplayText == "실패")
    }

    @Test("Room timerDisplayText - inProgress 타이머 없음")
    func roomTimerDisplayTextNoTimer() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        #expect(room.timerDisplayText == "진행 중")
    }

    @Test("Room remainingSeconds - 타이머 없음")
    func roomRemainingNoTimer() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        #expect(room.remainingSeconds == nil)
    }

    @Test("Room remainingSeconds - 타이머 진행 중")
    func roomRemainingWithTimer() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        room.timerStartedAt = Date()
        room.timerDurationSeconds = 300
        // 방금 시작했으므로 ~300초 남아야 함
        if let remaining = room.remainingSeconds {
            #expect(remaining >= 298 && remaining <= 300)
        } else {
            Issue.record("Expected remaining seconds")
        }
    }

    @Test("Room remainingSeconds - 시간 초과")
    func roomRemainingExpired() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        room.timerStartedAt = Date().addingTimeInterval(-600) // 10분 전
        room.timerDurationSeconds = 300 // 5분
        #expect(room.remainingSeconds == 0) // max(0, ...)
    }

    @Test("Room Codable 라운드트립")
    func roomCodable() throws {
        let agentID = UUID()
        var room = Room(title: "코딩 방", assignedAgentIDs: [agentID], createdBy: .master(agentID: agentID))
        room.status = .inProgress
        room.plan = RoomPlan(summary: "계획", estimatedSeconds: 120, steps: ["1단계"])
        room.currentStepIndex = 0

        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.id == room.id)
        #expect(decoded.title == "코딩 방")
        #expect(decoded.assignedAgentIDs == [agentID])
        #expect(decoded.status == .inProgress)
        #expect(decoded.plan?.summary == "계획")
        #expect(decoded.plan?.steps.count == 1)
        #expect(decoded.createdBy == .master(agentID: agentID))
    }

    @Test("Room Identifiable")
    func roomIdentifiable() {
        let a = Room(title: "A", assignedAgentIDs: [], createdBy: .user)
        let b = Room(title: "B", assignedAgentIDs: [], createdBy: .user)
        #expect(a.id != b.id)
    }

    // MARK: - RoomMode

    @Test("RoomMode rawValue")
    func roomModeRawValues() {
        #expect(RoomMode.task.rawValue == "task")
        #expect(RoomMode.discussion.rawValue == "discussion")
    }

    @Test("RoomMode Codable")
    func roomModeCodable() throws {
        for mode in [RoomMode.task, RoomMode.discussion] {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(RoomMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test("Room 기본 mode는 task")
    func roomDefaultModeIsTask() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        #expect(room.mode == .task)
    }

    @Test("Room discussion 모드 생성")
    func roomDiscussionMode() {
        let room = Room(title: "토론", assignedAgentIDs: [], createdBy: .user, mode: .discussion, maxDiscussionRounds: 5)
        #expect(room.mode == .discussion)
        #expect(room.maxDiscussionRounds == 5)
        #expect(room.currentRound == 0)
    }

    // MARK: - discussionProgressText

    @Test("discussionProgressText - planning 상태 + currentRound 0")
    func discussionProgressTextReady() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, mode: .discussion)
        #expect(room.discussionProgressText == "토론 준비 중")
    }

    @Test("discussionProgressText - planning 상태 + 진행 중")
    func discussionProgressTextInProgress() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, mode: .discussion, maxDiscussionRounds: 3)
        room.currentRound = 1
        #expect(room.discussionProgressText == "토론 중 (1라운드)")
    }

    @Test("discussionProgressText - 완료 (status != planning)")
    func discussionProgressTextCompleted() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, mode: .discussion, maxDiscussionRounds: 3)
        room.status = .completed
        #expect(room.discussionProgressText == "토론 완료")
    }

    // MARK: - timerDisplayText 추가 케이스

    @Test("Room timerDisplayText - inProgress 시간 초과")
    func roomTimerDisplayTextExpired() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        room.timerStartedAt = Date().addingTimeInterval(-600)
        room.timerDurationSeconds = 300
        #expect(room.timerDisplayText == "시간 초과")
    }

    @Test("Room timerDisplayText - inProgress 타이머 포맷")
    func roomTimerDisplayTextFormatted() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        room.timerStartedAt = Date()
        room.timerDurationSeconds = 300
        let text = room.timerDisplayText
        // "4:59" 또는 "5:00" 형태
        #expect(text.contains(":"))
        #expect(!text.contains("진행 중"))
        #expect(!text.contains("시간 초과"))
    }

    // MARK: - 레거시 디코딩

    @Test("Decodable - mode 없는 레거시 JSON")
    func decodeLegacyWithoutMode() throws {
        let agentID = UUID()
        let roomID = UUID()
        let json: [String: Any] = [
            "id": roomID.uuidString,
            "title": "Legacy Room",
            "assignedAgentIDs": [agentID.uuidString],
            "messages": [],
            "status": "planning",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "createdBy": ["user": [:]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let room = try decoder.decode(Room.self, from: data)
        #expect(room.mode == .task) // 기본값
    }

    @Test("Decodable - maxDiscussionRounds 없는 레거시 JSON")
    func decodeLegacyWithoutDiscussionRounds() throws {
        let roomID = UUID()
        let json: [String: Any] = [
            "id": roomID.uuidString,
            "title": "Legacy",
            "assignedAgentIDs": [] as [String],
            "messages": [],
            "status": "inProgress",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "createdBy": ["user": [:]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let room = try decoder.decode(Room.self, from: data)
        #expect(room.maxDiscussionRounds == 3) // 기본값
        #expect(room.currentRound == 0) // 기본값
        #expect(room.currentStepIndex == 0) // 기본값
    }

    @Test("Codable - discussion 모드 라운드트립")
    func codableDiscussionRoundTrip() throws {
        var room = Room(
            title: "토론방",
            assignedAgentIDs: [UUID()],
            createdBy: .user,
            mode: .discussion,
            maxDiscussionRounds: 5
        )
        room.currentRound = 2
        room.status = .inProgress

        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.mode == .discussion)
        #expect(decoded.maxDiscussionRounds == 5)
        #expect(decoded.currentRound == 2)
    }
}
