import Testing
import Foundation
@testable import DOUGLAS

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
        #expect(room.timerDisplayText == "준비 중")

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
        let room = Room(title: "토론", assignedAgentIDs: [], createdBy: .user, mode: .discussion)
        #expect(room.mode == .discussion)
        #expect(room.currentRound == 0)
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

    @Test("Decodable - 토론 필드 없는 레거시 JSON")
    func decodeLegacyWithoutDiscussionFields() throws {
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
        #expect(room.currentRound == 0) // 기본값
        #expect(room.currentStepIndex == 0) // 기본값
    }

    @Test("Codable - discussion 모드 라운드트립")
    func codableDiscussionRoundTrip() throws {
        var room = Room(
            title: "토론방",
            assignedAgentIDs: [UUID()],
            createdBy: .user,
            mode: .discussion
        )
        room.currentRound = 2
        room.status = .inProgress

        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.mode == .discussion)
        #expect(decoded.currentRound == 2)
    }

    // MARK: - canTransition

    @Test("canTransition - planning → inProgress 허용")
    func canTransitionPlanningToInProgress() {
        #expect(RoomStatus.planning.canTransition(to: .inProgress) == true)
    }

    @Test("canTransition - planning → failed 허용")
    func canTransitionPlanningToFailed() {
        #expect(RoomStatus.planning.canTransition(to: .failed) == true)
    }

    @Test("canTransition - inProgress → completed 허용")
    func canTransitionInProgressToCompleted() {
        #expect(RoomStatus.inProgress.canTransition(to: .completed) == true)
    }

    @Test("canTransition - inProgress → failed 허용")
    func canTransitionInProgressToFailed() {
        #expect(RoomStatus.inProgress.canTransition(to: .failed) == true)
    }

    @Test("canTransition - completed → inProgress 허용 (후속 메시지)")
    func canTransitionCompletedToInProgress() {
        #expect(RoomStatus.completed.canTransition(to: .inProgress) == true)
        #expect(RoomStatus.completed.canTransition(to: .planning) == true)
        #expect(RoomStatus.completed.canTransition(to: .failed) == false)
    }

    @Test("canTransition - failed → inProgress 허용 (재활성화)")
    func canTransitionFailedToInProgress() {
        #expect(RoomStatus.failed.canTransition(to: .inProgress) == true)
        #expect(RoomStatus.failed.canTransition(to: .planning) == true)
        #expect(RoomStatus.failed.canTransition(to: .completed) == false)
    }

    @Test("canTransition - planning → planning 불가 (같은 상태)")
    func canTransitionSameState() {
        #expect(RoomStatus.planning.canTransition(to: .planning) == false)
    }

    @Test("canTransition - planning → completed 허용 (수동 완료)")
    func canTransitionPlanningToCompleted() {
        #expect(RoomStatus.planning.canTransition(to: .completed) == true)
    }

    @Test("canTransition - inProgress → planning 불가 (역전)")
    func canTransitionInProgressToPlanning() {
        #expect(RoomStatus.inProgress.canTransition(to: .planning) == false)
    }

    // MARK: - transitionTo

    @Test("transitionTo - 유효한 전이 성공")
    func transitionToValid() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .planning)
        let result = room.transitionTo(.inProgress)
        #expect(result == true)
        #expect(room.status == .inProgress)
    }

    @Test("transitionTo - 무효한 전이 실패")
    func transitionToInvalid() {
        // completed → completed (같은 상태 전이)는 허용되지 않음
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .completed)
        let result = room.transitionTo(.completed)
        #expect(result == false)
        #expect(room.status == .completed) // 변경되지 않음
    }

    @Test("transitionTo - planning → failed")
    func transitionToFailed() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .planning)
        let result = room.transitionTo(.failed)
        #expect(result == true)
        #expect(room.status == .failed)
    }

    @Test("transitionTo - inProgress → completed")
    func transitionToCompleted() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        let result = room.transitionTo(.completed)
        #expect(result == true)
        #expect(room.status == .completed)
    }

    // MARK: - setCurrentStep

    @Test("setCurrentStep - 유효 인덱스")
    func setCurrentStepValid() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.plan = RoomPlan(summary: "계획", estimatedSeconds: 60, steps: ["A", "B", "C"])
        room.setCurrentStep(1)
        #expect(room.currentStepIndex == 1)
    }

    @Test("setCurrentStep - 음수 → 0")
    func setCurrentStepNegative() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.plan = RoomPlan(summary: "계획", estimatedSeconds: 60, steps: ["A", "B"])
        room.setCurrentStep(-1)
        #expect(room.currentStepIndex == 0)
    }

    @Test("setCurrentStep - 초과 → 최대")
    func setCurrentStepOverflow() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.plan = RoomPlan(summary: "계획", estimatedSeconds: 60, steps: ["A", "B"])
        room.setCurrentStep(10)
        #expect(room.currentStepIndex == 1) // steps.count - 1 = 1
    }

    @Test("setCurrentStep - plan nil이면 0")
    func setCurrentStepNoPlan() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.setCurrentStep(5)
        #expect(room.currentStepIndex == 0) // max(0, (nil ?? 1) - 1) = 0
    }

    // MARK: - WorkLog

    @Test("WorkLog 기본 초기화")
    func workLogInit() {
        let log = WorkLog(
            roomTitle: "테스트 방",
            participants: ["에이전트A", "에이전트B"],
            task: "테스트 작업",
            discussionSummary: "토론 요약",
            planSummary: "계획 요약",
            outcome: "결과",
            durationSeconds: 120
        )
        #expect(log.roomTitle == "테스트 방")
        #expect(log.participants.count == 2)
        #expect(log.task == "테스트 작업")
        #expect(log.durationSeconds == 120)
    }

    @Test("WorkLog Codable 라운드트립")
    func workLogCodable() throws {
        let log = WorkLog(
            roomTitle: "방",
            participants: ["A"],
            task: "작업",
            outcome: "완료",
            durationSeconds: 60
        )
        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(WorkLog.self, from: data)
        #expect(decoded.roomTitle == "방")
        #expect(decoded.participants == ["A"])
        #expect(decoded.outcome == "완료")
        #expect(decoded.durationSeconds == 60)
        #expect(decoded.discussionSummary == "")
        #expect(decoded.planSummary == "")
    }

    @Test("WorkLog Identifiable - 고유 ID")
    func workLogIdentifiable() {
        let a = WorkLog(roomTitle: "A", participants: [], task: "t", outcome: "o", durationSeconds: 1)
        let b = WorkLog(roomTitle: "A", participants: [], task: "t", outcome: "o", durationSeconds: 1)
        #expect(a.id != b.id)
    }

    // MARK: - Room with WorkLog

    @Test("Room Codable - workLog 포함")
    func roomCodableWithWorkLog() throws {
        var room = Room(title: "Work", assignedAgentIDs: [], createdBy: .user)
        room.workLog = WorkLog(
            roomTitle: "Work",
            participants: ["A"],
            task: "test",
            outcome: "done",
            durationSeconds: 30
        )
        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.workLog?.roomTitle == "Work")
        #expect(decoded.workLog?.durationSeconds == 30)
    }


    // MARK: - Phase B 필드

    @Test("projectPaths, buildCommand 기본값")
    func projectPathDefaults() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        #expect(room.projectPaths.isEmpty)
        #expect(room.primaryProjectPath == nil)
        #expect(room.buildCommand == nil)
        #expect(room.buildLoopStatus == nil)
        #expect(room.buildRetryCount == 0)
        #expect(room.maxBuildRetries == 3)
        #expect(room.lastBuildResult == nil)
    }

    @Test("projectPaths 명시적 설정")
    func projectPathExplicit() {
        let room = Room(
            title: "Build Test",
            assignedAgentIDs: [],
            createdBy: .user,
            projectPaths: ["/Users/test/project", "/Users/test/other"],
            buildCommand: "swift build"
        )
        #expect(room.projectPaths == ["/Users/test/project", "/Users/test/other"])
        #expect(room.primaryProjectPath == "/Users/test/project")
        #expect(room.buildCommand == "swift build")
    }

    @Test("빌드 관련 필드 Codable 라운드트립")
    func buildFieldsCodable() throws {
        var room = Room(
            title: "Build",
            assignedAgentIDs: [],
            createdBy: .user,
            projectPaths: ["/tmp/project"],
            buildCommand: "make"
        )
        room.buildLoopStatus = .building
        room.buildRetryCount = 2
        room.maxBuildRetries = 5
        room.lastBuildResult = BuildResult(success: false, output: "error", exitCode: 1)

        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)

        #expect(decoded.projectPaths == ["/tmp/project"])
        #expect(decoded.primaryProjectPath == "/tmp/project")
        #expect(decoded.buildCommand == "make")
        #expect(decoded.buildLoopStatus == .building)
        #expect(decoded.buildRetryCount == 2)
        #expect(decoded.maxBuildRetries == 5)
        #expect(decoded.lastBuildResult?.success == false)
        #expect(decoded.lastBuildResult?.exitCode == 1)
    }

    @Test("빌드 필드 없는 기존 데이터 역호환")
    func buildFieldsBackwardCompatible() throws {
        let room = Room(title: "Old Room", assignedAgentIDs: [], createdBy: .user)
        let data = try JSONEncoder().encode(room)

        // JSON에서 빌드 관련 키를 제거해 기존 데이터 시뮬레이션
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "projectPaths")
        json.removeValue(forKey: "buildCommand")
        json.removeValue(forKey: "buildLoopStatus")
        json.removeValue(forKey: "buildRetryCount")
        json.removeValue(forKey: "maxBuildRetries")
        json.removeValue(forKey: "lastBuildResult")
        let modifiedData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Room.self, from: modifiedData)
        #expect(decoded.projectPaths.isEmpty)
        #expect(decoded.primaryProjectPath == nil)
        #expect(decoded.buildCommand == nil)
        #expect(decoded.buildLoopStatus == nil)
        #expect(decoded.buildRetryCount == 0)
        #expect(decoded.maxBuildRetries == 3)
        #expect(decoded.lastBuildResult == nil)
    }

    @Test("기존 projectPath(단일) JSON → projectPaths 배열 하위 호환")
    func projectPathLegacyMigration() throws {
        // 기존 형식: "projectPath": "/old/path" (단일 문자열)
        let room = Room(title: "Legacy", assignedAgentIDs: [], createdBy: .user)
        let data = try JSONEncoder().encode(room)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "projectPaths")
        json["projectPath"] = "/old/single/path"
        let modifiedData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Room.self, from: modifiedData)
        #expect(decoded.projectPaths == ["/old/single/path"])
        #expect(decoded.primaryProjectPath == "/old/single/path")
    }

    // MARK: - Phase C-2: 승인 게이트

    @Test("RoomStatus awaitingApproval rawValue")
    func awaitingApprovalRawValue() {
        #expect(RoomStatus.awaitingApproval.rawValue == "awaitingApproval")
    }

    @Test("canTransition - inProgress → awaitingApproval 허용")
    func canTransitionInProgressToAwaiting() {
        #expect(RoomStatus.inProgress.canTransition(to: .awaitingApproval) == true)
    }

    @Test("canTransition - awaitingApproval → inProgress 허용")
    func canTransitionAwaitingToInProgress() {
        #expect(RoomStatus.awaitingApproval.canTransition(to: .inProgress) == true)
    }

    @Test("canTransition - awaitingApproval → failed 허용")
    func canTransitionAwaitingToFailed() {
        #expect(RoomStatus.awaitingApproval.canTransition(to: .failed) == true)
    }

    @Test("canTransition - awaitingApproval → completed 허용")
    func canTransitionAwaitingToCompleted() {
        #expect(RoomStatus.awaitingApproval.canTransition(to: .completed) == true)
    }

    @Test("canTransition - planning → awaitingApproval 허용")
    func canTransitionPlanningToAwaiting() {
        #expect(RoomStatus.planning.canTransition(to: .awaitingApproval) == true)
    }

    @Test("Room isActive - awaitingApproval")
    func roomIsActiveAwaiting() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        var mutable = room
        mutable.status = .awaitingApproval
        #expect(mutable.isActive == true)
    }

    @Test("Room timerDisplayText - awaitingApproval")
    func roomTimerDisplayTextAwaiting() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        room.status = .awaitingApproval
        #expect(room.timerDisplayText == "승인 대기")
    }

    @Test("Room pendingApprovalStepIndex 기본값 nil")
    func pendingApprovalDefault() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        #expect(room.pendingApprovalStepIndex == nil)
    }

    @Test("Room pendingApprovalStepIndex Codable 라운드트립")
    func pendingApprovalCodable() throws {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.pendingApprovalStepIndex = 2
        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.pendingApprovalStepIndex == 2)
    }

    // MARK: - Phase C-3: QA 필드

    @Test("testCommand 기본값 nil")
    func testCommandDefaults() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        #expect(room.testCommand == nil)
        #expect(room.qaLoopStatus == nil)
        #expect(room.qaRetryCount == 0)
        #expect(room.maxQARetries == 3)
        #expect(room.lastQAResult == nil)
    }

    @Test("testCommand 명시적 설정")
    func testCommandExplicit() {
        let room = Room(
            title: "QA Test",
            assignedAgentIDs: [],
            createdBy: .user,
            testCommand: "swift test"
        )
        #expect(room.testCommand == "swift test")
    }

    @Test("QA 필드 Codable 라운드트립")
    func qaFieldsCodable() throws {
        var room = Room(
            title: "QA",
            assignedAgentIDs: [],
            createdBy: .user,
            testCommand: "npm test"
        )
        room.qaLoopStatus = .testing
        room.qaRetryCount = 1
        room.maxQARetries = 5
        room.lastQAResult = QAResult(success: false, output: "FAIL", exitCode: 1)

        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)

        #expect(decoded.testCommand == "npm test")
        #expect(decoded.qaLoopStatus == .testing)
        #expect(decoded.qaRetryCount == 1)
        #expect(decoded.maxQARetries == 5)
        #expect(decoded.lastQAResult?.success == false)
        #expect(decoded.lastQAResult?.exitCode == 1)
    }

    @Test("QA 필드 없는 기존 데이터 역호환")
    func qaFieldsBackwardCompatible() throws {
        let room = Room(title: "Old Room", assignedAgentIDs: [], createdBy: .user)
        let data = try JSONEncoder().encode(room)

        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "testCommand")
        json.removeValue(forKey: "qaLoopStatus")
        json.removeValue(forKey: "qaRetryCount")
        json.removeValue(forKey: "maxQARetries")
        json.removeValue(forKey: "lastQAResult")
        let modifiedData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Room.self, from: modifiedData)
        #expect(decoded.testCommand == nil)
        #expect(decoded.qaLoopStatus == nil)
        #expect(decoded.qaRetryCount == 0)
        #expect(decoded.maxQARetries == 3)
        #expect(decoded.lastQAResult == nil)
    }

    // MARK: - Phase D: RoomAgentSuggestion

    @Test("RoomAgentSuggestion Codable 라운드트립")
    func suggestionCodable() throws {
        let suggestion = RoomAgentSuggestion(
            name: "QA 엔지니어",
            persona: "테스트 전문가",
            recommendedPreset: "개발자",
            reason: "테스트 필요",
            suggestedBy: "분석가"
        )
        let data = try JSONEncoder().encode(suggestion)
        let decoded = try JSONDecoder().decode(RoomAgentSuggestion.self, from: data)
        #expect(decoded.name == "QA 엔지니어")
        #expect(decoded.persona == "테스트 전문가")
        #expect(decoded.recommendedPreset == "개발자")
        #expect(decoded.reason == "테스트 필요")
        #expect(decoded.suggestedBy == "분석가")
        #expect(decoded.status == .pending)
    }

    @Test("Room - pendingAgentSuggestions 기본값 빈 배열")
    func roomDefaultSuggestions() {
        let room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        #expect(room.pendingAgentSuggestions.isEmpty)
    }

    @Test("Room - needsUserAttention: pending suggestion → true")
    func roomNeedsAttentionWithSuggestion() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.pendingAgentSuggestions = [
            RoomAgentSuggestion(name: "Dev", persona: "개발자", suggestedBy: "분석가")
        ]
        #expect(room.needsUserAttention == true)
    }

    @Test("Room - needsUserAttention: no pending → false")
    func roomNoAttentionNeeded() {
        let room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        #expect(room.needsUserAttention == false)
    }

    @Test("Room - needsUserAttention: awaitingApproval → true")
    func roomNeedsAttentionApproval() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        room.transitionTo(.awaitingApproval)
        #expect(room.needsUserAttention == true)
    }

    @Test("Room - pendingAgentSuggestions 역호환 (필드 없는 JSON)")
    func roomSuggestionBackwardCompat() throws {
        let room = Room(title: "역호환", assignedAgentIDs: [], createdBy: .user)
        let data = try JSONEncoder().encode(room)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "pendingAgentSuggestions")
        let modifiedData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Room.self, from: modifiedData)
        #expect(decoded.pendingAgentSuggestions.isEmpty)
    }

    // MARK: - Phase E: awaitingUserInput 상태 전이

    @Test("RoomStatus awaitingUserInput rawValue")
    func awaitingUserInputRawValue() {
        #expect(RoomStatus.awaitingUserInput.rawValue == "awaitingUserInput")
    }

    @Test("canTransition - planning → awaitingUserInput 허용")
    func canTransitionPlanningToAwaitingUserInput() {
        #expect(RoomStatus.planning.canTransition(to: .awaitingUserInput) == true)
    }

    @Test("canTransition - inProgress → awaitingUserInput 허용")
    func canTransitionInProgressToAwaitingUserInput() {
        #expect(RoomStatus.inProgress.canTransition(to: .awaitingUserInput) == true)
    }

    @Test("canTransition - awaitingUserInput → inProgress 허용")
    func canTransitionAwaitingUserInputToInProgress() {
        #expect(RoomStatus.awaitingUserInput.canTransition(to: .inProgress) == true)
    }

    @Test("canTransition - awaitingUserInput → planning 허용")
    func canTransitionAwaitingUserInputToPlanning() {
        #expect(RoomStatus.awaitingUserInput.canTransition(to: .planning) == true)
    }

    @Test("canTransition - awaitingUserInput → failed 허용")
    func canTransitionAwaitingUserInputToFailed() {
        #expect(RoomStatus.awaitingUserInput.canTransition(to: .failed) == true)
    }

    @Test("canTransition - awaitingUserInput → completed 허용")
    func canTransitionAwaitingUserInputToCompleted() {
        #expect(RoomStatus.awaitingUserInput.canTransition(to: .completed) == true)
    }

    @Test("Room isActive - awaitingUserInput")
    func roomIsActiveAwaitingUserInput() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.status = .awaitingUserInput
        #expect(room.isActive == true)
    }

    @Test("Room timerDisplayText - awaitingUserInput")
    func roomTimerDisplayTextAwaitingUserInput() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.status = .awaitingUserInput
        #expect(room.timerDisplayText == "입력 대기")
    }

    @Test("Room needsUserAttention - awaitingUserInput → true")
    func roomNeedsAttentionUserInput() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.status = .awaitingUserInput
        #expect(room.needsUserAttention == true)
    }

    // MARK: - Phase E: 워크플로우 필드

    @Test("Phase E 필드 기본값")
    func phaseEDefaults() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        #expect(room.intent == nil)
        #expect(room.currentPhase == nil)
        #expect(room.assumptions == nil)
        #expect(room.userAnswers == nil)
        #expect(room.playbook == nil)
        #expect(room.intakeData == nil)
        #expect(room.clarifyQuestionCount == 0)
    }

    @Test("Phase E 필드 Codable 라운드트립")
    func phaseEFieldsCodable() throws {
        var room = Room(title: "Workflow", assignedAgentIDs: [], createdBy: .user)
        room.intent = WorkflowIntent.task
        room.currentPhase = .clarify
        room.assumptions = [
            WorkflowAssumption(text: "Swift 5.9 사용", riskLevel: .low)
        ]
        room.userAnswers = [
            UserAnswer(question: "DB?", answer: "PostgreSQL")
        ]
        room.playbook = ProjectPlaybook.team
        room.intakeData = IntakeData(sourceType: .text, rawInput: "작업 내용")
        room.clarifyQuestionCount = 3

        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)

        #expect(decoded.intent == WorkflowIntent.task)
        #expect(decoded.currentPhase == .clarify)
        #expect(decoded.assumptions?.count == 1)
        #expect(decoded.assumptions?[0].text == "Swift 5.9 사용")
        #expect(decoded.userAnswers?.count == 1)
        #expect(decoded.userAnswers?[0].answer == "PostgreSQL")
        #expect(decoded.playbook?.baseBranch == "develop")
        #expect(decoded.intakeData?.sourceType == .text)
        #expect(decoded.clarifyQuestionCount == 3)
    }

    // MARK: - Phase DDD-2: RoomStatus.cancelled + RequestStatus

    @Test("RoomStatus.cancelled rawValue")
    func cancelledRawValue() {
        #expect(RoomStatus.cancelled.rawValue == "cancelled")
    }

    @Test("canTransition - planning → cancelled 허용")
    func canTransitionPlanningToCancelled() {
        #expect(RoomStatus.planning.canTransition(to: .cancelled) == true)
    }

    @Test("canTransition - inProgress → cancelled 허용")
    func canTransitionInProgressToCancelled() {
        #expect(RoomStatus.inProgress.canTransition(to: .cancelled) == true)
    }

    @Test("canTransition - awaitingApproval → cancelled 허용")
    func canTransitionAwaitingToCancelled() {
        #expect(RoomStatus.awaitingApproval.canTransition(to: .cancelled) == true)
    }

    @Test("canTransition - awaitingUserInput → cancelled 허용")
    func canTransitionAwaitingUserInputToCancelled() {
        #expect(RoomStatus.awaitingUserInput.canTransition(to: .cancelled) == true)
    }

    @Test("canTransition - completed → cancelled 불가")
    func canTransitionCompletedToCancelled() {
        #expect(RoomStatus.completed.canTransition(to: .cancelled) == false)
    }

    @Test("canTransition - cancelled → planning 허용 (재활성화)")
    func canTransitionCancelledToPlanning() {
        #expect(RoomStatus.cancelled.canTransition(to: .planning) == true)
    }

    @Test("canTransition - cancelled → inProgress 허용 (재활성화)")
    func canTransitionCancelledToInProgress() {
        #expect(RoomStatus.cancelled.canTransition(to: .inProgress) == true)
    }

    @Test("canTransition - cancelled → completed 불가")
    func canTransitionCancelledToCompleted() {
        #expect(RoomStatus.cancelled.canTransition(to: .completed) == false)
    }

    @Test("Room isActive - cancelled → false")
    func roomIsActiveCancelled() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.status = .cancelled
        #expect(room.isActive == false)
    }

    @Test("RoomStatus.cancelled Codable 라운드트립")
    func cancelledCodable() throws {
        let data = try JSONEncoder().encode(RoomStatus.cancelled)
        let decoded = try JSONDecoder().decode(RoomStatus.self, from: data)
        #expect(decoded == .cancelled)
    }

    @Test("RequestStatus - planning + understand → intentClassified")
    func requestStatusPlanningUnderstand() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .planning)
        room.workflowState.currentPhase = .understand
        #expect(room.requestStatus == .intentClassified)
    }

    @Test("RequestStatus - planning + assemble → agentMatched")
    func requestStatusPlanningAssemble() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .planning)
        room.workflowState.currentPhase = .assemble
        #expect(room.requestStatus == .agentMatched)
    }

    @Test("RequestStatus - planning + design → discussing")
    func requestStatusPlanningDesign() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .planning)
        room.workflowState.currentPhase = .design
        #expect(room.requestStatus == .discussing)
    }

    @Test("RequestStatus - planning + build → executing")
    func requestStatusPlanningBuild() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .planning)
        room.workflowState.currentPhase = .build
        #expect(room.requestStatus == .executing)
    }

    @Test("RequestStatus - inProgress → executing")
    func requestStatusInProgress() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        #expect(room.requestStatus == .executing)
    }

    @Test("RequestStatus - awaitingApproval + planApproval → waitingPlanApproval")
    func requestStatusAwaitingPlanApproval() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        room.status = .awaitingApproval
        room.awaitingType = .planApproval
        #expect(room.requestStatus == .waitingPlanApproval)
    }

    @Test("RequestStatus - awaitingApproval + stepApproval → waitingExecutionApproval")
    func requestStatusAwaitingStepApproval() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        room.status = .awaitingApproval
        room.awaitingType = .stepApproval
        #expect(room.requestStatus == .waitingExecutionApproval)
    }

    @Test("RequestStatus - awaitingUserInput → waitingUserFeedback")
    func requestStatusAwaitingUserInput() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.status = .awaitingUserInput
        #expect(room.requestStatus == .waitingUserFeedback)
    }

    @Test("RequestStatus - completed")
    func requestStatusCompleted() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .completed)
        #expect(room.requestStatus == .completed)
    }

    @Test("RequestStatus - failed")
    func requestStatusFailed() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .failed)
        #expect(room.requestStatus == .failed)
    }

    @Test("RequestStatus - cancelled")
    func requestStatusCancelled() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.status = .cancelled
        #expect(room.requestStatus == .cancelled)
    }

    @Test("RequestStatus - 모든 rawValue 왕복")
    func requestStatusAllRawValues() {
        let allCases: [RequestStatus] = [
            .received, .intentClassified, .waitingClarification,
            .roomCreated, .agentMatched, .waitingAgentConfirmation,
            .discussing, .planning, .executing, .documenting,
            .waitingPlanApproval, .waitingExecutionApproval,
            .waitingUserFeedback, .waitingFinalApproval,
            .completed, .failed, .cancelled
        ]
        for status in allCases {
            #expect(RequestStatus(rawValue: status.rawValue) == status)
        }
    }

    @Test("Phase E 필드 없는 기존 데이터 역호환")
    func phaseEFieldsBackwardCompatible() throws {
        let room = Room(title: "Old", assignedAgentIDs: [], createdBy: .user)
        let data = try JSONEncoder().encode(room)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "intent")
        json.removeValue(forKey: "currentPhase")
        json.removeValue(forKey: "assumptions")
        json.removeValue(forKey: "userAnswers")
        json.removeValue(forKey: "playbook")
        json.removeValue(forKey: "intakeData")
        json.removeValue(forKey: "clarifyQuestionCount")
        let modifiedData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Room.self, from: modifiedData)
        #expect(decoded.intent == nil)
        #expect(decoded.currentPhase == nil)
        #expect(decoded.assumptions == nil)
        #expect(decoded.userAnswers == nil)
        #expect(decoded.playbook == nil)
        #expect(decoded.intakeData == nil)
        #expect(decoded.clarifyQuestionCount == 0)
    }

    // MARK: - RoomPlan stepJournal

    @Test("RoomPlan stepJournal — 인코딩/디코딩 왕복")
    func stepJournal_codable_roundTrip() throws {
        var plan = RoomPlan(summary: "테스트", estimatedSeconds: 60, steps: ["단계 1", "단계 2"])
        plan.stepJournal = ["Step 1 완료: 백엔드 API 구현", "Step 2 완료: 프론트 연동"]

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(RoomPlan.self, from: data)
        #expect(decoded.stepJournal == ["Step 1 완료: 백엔드 API 구현", "Step 2 완료: 프론트 연동"])
    }

    @Test("RoomPlan stepJournal — 기존 저장본에 journal 없으면 빈 배열")
    func stepJournal_backwardCompatible() throws {
        // stepJournal 필드 없는 JSON
        let json = """
        {"summary":"테스트","estimatedSeconds":60,"steps":["단계 1"],"version":1}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RoomPlan.self, from: data)
        #expect(decoded.stepJournal.isEmpty)
    }
}
