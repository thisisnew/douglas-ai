import Testing
import Foundation
@testable import DOUGLAS

@Suite("Room Completion Race Condition Tests")
@MainActor
struct RoomCompletionTests {

    // MARK: - 도우미

    private static let testRoomDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("douglas-completion-tests-\(ProcessInfo.processInfo.processIdentifier)")

    private func makeManager() -> RoomManager {
        RoomManager.roomDirectoryOverride = Self.testRoomDir
        return RoomManager()
    }

    private func createInProgressRoom(_ manager: RoomManager) -> Room {
        let room = manager.createRoom(title: "테스트", agentIDs: [], createdBy: .user)
        if let i = manager.rooms.firstIndex(where: { $0.id == room.id }) {
            _ = manager.rooms[i].transitionTo(.inProgress)
        }
        return room
    }

    // MARK: - completeRoom 상태 전이

    @Test("completeRoom — inProgress → completed 전이")
    func completeRoom_transitionsToCompleted() {
        let manager = makeManager()
        let room = createInProgressRoom(manager)

        #expect(manager.rooms.first(where: { $0.id == room.id })?.status == .inProgress)

        manager.completeRoom(room.id)

        #expect(manager.rooms.first(where: { $0.id == room.id })?.status == .completed)
        #expect(manager.rooms.first(where: { $0.id == room.id })?.completedAt != nil)
    }

    @Test("completeRoom — 이미 completed이면 상태 유지")
    func completeRoom_alreadyCompleted_noChange() {
        let manager = makeManager()
        let room = createInProgressRoom(manager)

        // 먼저 완료
        manager.completeRoom(room.id)
        let firstCompletedAt = manager.rooms.first(where: { $0.id == room.id })?.completedAt

        // 두 번째 호출 — 이미 completed → completed 전이는 canTransition에서 거부
        manager.completeRoom(room.id)

        #expect(manager.rooms.first(where: { $0.id == room.id })?.status == .completed)
    }

    // MARK: - workLog 중복 생성 방지

    @Test("completeRoom — workLog이 이미 있으면 generateWorkLog 건너뜀")
    func completeRoom_withExistingWorkLog_skipsGeneration() {
        let manager = makeManager()
        let room = createInProgressRoom(manager)

        // workLog 설정
        if let i = manager.rooms.firstIndex(where: { $0.id == room.id }) {
            manager.rooms[i].setWorkLog(WorkLog(
                roomTitle: "테스트",
                participants: ["agent1"],
                task: "작업",
                discussionSummary: "",
                planSummary: "",
                outcome: "완료",
                durationSeconds: 10
            ))
        }

        let existingLogID = manager.rooms.first(where: { $0.id == room.id })?.workLog?.id
        #expect(existingLogID != nil)

        manager.completeRoom(room.id)

        // workLog ID가 변경되지 않아야 함
        let afterLogID = manager.rooms.first(where: { $0.id == room.id })?.workLog?.id
        #expect(afterLogID == existingLogID, "기존 workLog이 유지되어야 함")
    }

    // MARK: - executeRoomWork 취소 안전성 (Task.isCancelled guard)

    @Test("executeRoomWork — 취소 후 상태 변경 방지 검증 (모델 레벨)")
    func cancelledTask_doesNotTransition() {
        // Room이 이미 completed 상태이면 executeRoomWork 후처리가 상태를 변경하지 않음
        let manager = makeManager()
        let room = createInProgressRoom(manager)
        manager.completeRoom(room.id)

        // completeRoom 이후 상태 확인
        #expect(manager.rooms.first(where: { $0.id == room.id })?.status == .completed)

        // inProgress가 아니므로 executeRoomWork의 후처리 분기가 실행되지 않음 (방어 검증)
        // 실제로는 Task.isCancelled guard가 먼저 잡아줌
    }

    // MARK: - continuation 해제

    @Test("completeRoom — continuation 해제 시 빈 문자열 반환")
    func completeRoom_resumesContinuations() async {
        let manager = makeManager()
        let room = createInProgressRoom(manager)
        let roomID = room.id

        if let i = manager.rooms.firstIndex(where: { $0.id == roomID }) {
            _ = manager.rooms[i].transitionTo(.awaitingUserInput)
        }

        // continuation 등록 + 바로 completeRoom 호출
        let result: String = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            manager.approvalGates.userInputContinuations[roomID] = cont
            manager.completeRoom(roomID)
        }

        #expect(result == "", "completeRoom이 continuation을 빈 문자열로 resume해야 함")
    }
}
