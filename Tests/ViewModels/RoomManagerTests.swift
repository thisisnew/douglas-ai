import Testing
import Foundation
@testable import DOUGLAS

@Suite("RoomManager Tests")
@MainActor
struct RoomManagerTests {

    // MARK: - Helper

    private func makeManager() -> RoomManager {
        RoomManager()
    }

    private func makeConfiguredManager() -> (RoomManager, AgentStore, ProviderManager) {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let providerManager = ProviderManager(defaults: defaults)
        let manager = RoomManager()
        manager.configure(agentStore: store, providerManager: providerManager)
        return (manager, store, providerManager)
    }

    /// 방을 생성하고 inProgress로 전이 (completeRoom 테스트용)
    private func createInProgressRoom(_ manager: RoomManager, title: String = "Test", agentIDs: [UUID] = []) -> Room {
        let room = manager.createRoom(title: title, agentIDs: agentIDs, createdBy: .user)
        // planning → inProgress 전이
        if let idx = manager.rooms.firstIndex(where: { $0.id == room.id }) {
            _ = manager.rooms[idx].transitionTo(.inProgress)
        }
        return room
    }

    // MARK: - 초기 상태

    @Test("init - 빈 상태")
    func initEmpty() {
        let manager = makeManager()
        #expect(manager.rooms.isEmpty)
        #expect(manager.selectedRoomID == nil)
        #expect(manager.pendingAutoOpenRoomID == nil)
    }

    @Test("configure - 의존성 설정")
    func configureTest() {
        let (manager, store, providerManager) = makeConfiguredManager()
        #expect(manager.agentStore != nil)
        #expect(manager.providerManager != nil)
        #expect(manager.agentStore === store)
        #expect(manager.providerManager === providerManager)
    }

    // MARK: - 방 생성

    @Test("createRoom - 기본 생성")
    func createRoomBasic() {
        let manager = makeManager()
        let agentIDs = [UUID(), UUID()]
        let room = manager.createRoom(title: "Test Room", agentIDs: agentIDs, createdBy: .user)

        #expect(room.title == "Test Room")
        #expect(room.assignedAgentIDs.count == 2)
        #expect(room.status == .planning)
        #expect(room.mode == .task)
        #expect(room.messages.isEmpty)
        #expect(manager.rooms.count == 1)
        #expect(manager.selectedRoomID == room.id)
    }

    @Test("createRoom - 토론 모드")
    func createRoomDiscussion() {
        let manager = makeManager()
        let room = manager.createRoom(
            title: "Discussion",
            agentIDs: [],
            createdBy: .user,
            mode: .discussion,
            maxDiscussionRounds: 5
        )
        #expect(room.mode == .discussion)
        #expect(room.maxDiscussionRounds == 5)
    }

    @Test("createRoom - 마스터 위임 생성")
    func createRoomByMaster() {
        let manager = makeManager()
        let masterID = UUID()
        let room = manager.createRoom(title: "Delegated", agentIDs: [], createdBy: .master(agentID: masterID))
        #expect(room.createdBy == .master(agentID: masterID))
    }

    @Test("createRoom - 여러 방 생성")
    func createMultipleRooms() {
        let manager = makeManager()
        manager.createRoom(title: "Room1", agentIDs: [], createdBy: .user)
        manager.createRoom(title: "Room2", agentIDs: [], createdBy: .user)
        manager.createRoom(title: "Room3", agentIDs: [], createdBy: .user)
        #expect(manager.rooms.count == 3)
    }

    @Test("createRoom - selectedRoomID 업데이트")
    func createRoomUpdatesSelection() {
        let manager = makeManager()
        let room1 = manager.createRoom(title: "Room1", agentIDs: [], createdBy: .user)
        #expect(manager.selectedRoomID == room1.id)
        let room2 = manager.createRoom(title: "Room2", agentIDs: [], createdBy: .user)
        #expect(manager.selectedRoomID == room2.id)
    }

    // MARK: - 계산 프로퍼티

    @Test("selectedRoom - 선택된 방 반환")
    func selectedRoomProperty() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Selected", agentIDs: [], createdBy: .user)
        #expect(manager.selectedRoom?.id == room.id)
    }

    @Test("selectedRoom - 선택 없으면 nil")
    func selectedRoomNil() {
        let manager = makeManager()
        manager.selectedRoomID = nil
        #expect(manager.selectedRoom == nil)
    }

    @Test("activeRooms - 활성 방만 포함")
    func activeRoomsFilters() {
        let manager = makeManager()
        manager.createRoom(title: "Active1", agentIDs: [], createdBy: .user)
        manager.createRoom(title: "Active2", agentIDs: [], createdBy: .user)
        let toComplete = createInProgressRoom(manager, title: "Completed")
        manager.completeRoom(toComplete.id)

        #expect(manager.activeRooms.count == 2)
        #expect(manager.activeRooms.allSatisfy { $0.isActive })
    }

    @Test("completedRooms - 비활성 방만 포함")
    func completedRoomsFilters() {
        let manager = makeManager()
        manager.createRoom(title: "Active", agentIDs: [], createdBy: .user)
        let done = createInProgressRoom(manager, title: "Done")
        manager.completeRoom(done.id)

        #expect(manager.completedRooms.count == 1)
        #expect(manager.completedRooms.allSatisfy { !$0.isActive })
    }

    // MARK: - 메시지 추가

    @Test("appendMessage - 메시지 추가")
    func appendMessageTest() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Test", agentIDs: [], createdBy: .user)
        let msg = ChatMessage(role: .user, content: "Hello")
        manager.appendMessage(msg, to: room.id)

        #expect(manager.rooms.first?.messages.count == 1)
        #expect(manager.rooms.first?.messages.first?.content == "Hello")
    }

    @Test("appendMessage - 존재하지 않는 방")
    func appendMessageNonExistingRoom() {
        let manager = makeManager()
        let msg = ChatMessage(role: .user, content: "Hello")
        manager.appendMessage(msg, to: UUID())
        #expect(manager.rooms.isEmpty)
    }

    @Test("appendMessage - 여러 메시지")
    func appendMultipleMessages() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Test", agentIDs: [], createdBy: .user)
        for i in 0..<5 {
            manager.appendMessage(ChatMessage(role: .user, content: "msg \(i)"), to: room.id)
        }
        #expect(manager.rooms.first?.messages.count == 5)
    }

    // MARK: - 에이전트 추가

    @Test("addAgent - 방에 에이전트 추가")
    func addAgentToRoom() {
        let (manager, store, _) = makeConfiguredManager()
        let room = manager.createRoom(title: "Test", agentIDs: [], createdBy: .user)
        let agent = makeTestAgent(name: "Worker")
        store.addAgent(agent)

        manager.addAgent(agent.id, to: room.id)

        #expect(manager.rooms.first?.assignedAgentIDs.contains(agent.id) == true)
        #expect(manager.rooms.first?.messages.contains(where: { $0.role == .system }) == true)
    }

    @Test("addAgent - 중복 추가 방지")
    func addAgentDuplicate() {
        let manager = makeManager()
        let agentID = UUID()
        manager.createRoom(title: "Test", agentIDs: [agentID], createdBy: .user)
        manager.addAgent(agentID, to: manager.rooms.first!.id)
        #expect(manager.rooms.first?.assignedAgentIDs.count == 1)
    }

    @Test("addAgent - 존재하지 않는 방")
    func addAgentNonExistingRoom() {
        let manager = makeManager()
        manager.addAgent(UUID(), to: UUID())
    }

    // MARK: - 방 상태 관리

    @Test("completeRoom - inProgress에서 completed로 전이")
    func completeRoomTest() {
        let manager = makeManager()
        let room = createInProgressRoom(manager)
        #expect(manager.rooms.first?.status == .inProgress)

        manager.completeRoom(room.id)
        let found = manager.rooms.first(where: { $0.id == room.id })
        #expect(found?.status == .completed)
        #expect(found?.completedAt != nil)
    }

    @Test("completeRoom - planning에서는 전이 불가")
    func completeRoomFromPlanning() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Test", agentIDs: [], createdBy: .user)
        manager.completeRoom(room.id)
        // planning → completed 직접 전이는 불가
        #expect(manager.rooms.first?.status == .planning)
    }

    @Test("completeRoom - 존재하지 않는 방")
    func completeRoomNonExisting() {
        let manager = makeManager()
        manager.completeRoom(UUID())
    }

    @Test("deleteRoom - 방 삭제")
    func deleteRoomTest() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Test", agentIDs: [], createdBy: .user)
        manager.deleteRoom(room.id)
        #expect(manager.rooms.isEmpty)
    }

    @Test("deleteRoom - 선택된 방 삭제 시 선택 해제")
    func deleteSelectedRoom() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Test", agentIDs: [], createdBy: .user)
        #expect(manager.selectedRoomID == room.id)
        manager.deleteRoom(room.id)
        #expect(manager.selectedRoomID == nil)
    }

    @Test("deleteRoom - 존재하지 않는 방")
    func deleteNonExistingRoom() {
        let manager = makeManager()
        manager.createRoom(title: "Test", agentIDs: [], createdBy: .user)
        let countBefore = manager.rooms.count
        manager.deleteRoom(UUID())
        #expect(manager.rooms.count == countBefore)
    }

    @Test("deleteRoom - 다른 방에 영향 없음")
    func deleteRoomIsolation() {
        let manager = makeManager()
        let room1 = manager.createRoom(title: "Room1", agentIDs: [], createdBy: .user)
        let room2 = manager.createRoom(title: "Room2", agentIDs: [], createdBy: .user)
        manager.deleteRoom(room1.id)
        #expect(manager.rooms.count == 1)
        #expect(manager.rooms.first?.id == room2.id)
    }

    // MARK: - activeRoomCount

    @Test("activeRoomCount - 에이전트가 참여 중인 방 수")
    func activeRoomCountForAgent() {
        let manager = makeManager()
        let agentID = UUID()
        manager.createRoom(title: "Room1", agentIDs: [agentID], createdBy: .user)
        manager.createRoom(title: "Room2", agentIDs: [agentID], createdBy: .user)
        manager.createRoom(title: "Room3", agentIDs: [UUID()], createdBy: .user)

        #expect(manager.activeRoomCount(for: agentID) == 2)
    }

    @Test("activeRoomCount - 완료된 방 제외")
    func activeRoomCountExcludesCompleted() {
        let manager = makeManager()
        let agentID = UUID()
        manager.createRoom(title: "Active", agentIDs: [agentID], createdBy: .user)
        let done = createInProgressRoom(manager, title: "Done", agentIDs: [agentID])
        manager.completeRoom(done.id)

        #expect(manager.activeRoomCount(for: agentID) == 1)
    }

    @Test("activeRoomCount - 에이전트 미참여")
    func activeRoomCountZero() {
        let manager = makeManager()
        manager.createRoom(title: "Room", agentIDs: [UUID()], createdBy: .user)
        #expect(manager.activeRoomCount(for: UUID()) == 0)
    }

    // MARK: - syncAgentStatuses

    @Test("syncAgentStatuses - idle (참여 방 0개)")
    func syncStatusIdle() {
        let (manager, store, _) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Worker")
        store.addAgent(agent)

        manager.syncAgentStatuses()
        let updated = store.agents.first(where: { $0.id == agent.id })
        #expect(updated?.status == .idle)
    }

    @Test("syncAgentStatuses - working (참여 방 1개)")
    func syncStatusWorking() {
        let (manager, store, _) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Worker")
        store.addAgent(agent)
        manager.createRoom(title: "Room", agentIDs: [agent.id], createdBy: .user)

        manager.syncAgentStatuses()
        let updated = store.agents.first(where: { $0.id == agent.id })
        #expect(updated?.status == .working)
    }

    @Test("syncAgentStatuses - busy (참여 방 2+개)")
    func syncStatusBusy() {
        let (manager, store, _) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Worker")
        store.addAgent(agent)
        manager.createRoom(title: "Room1", agentIDs: [agent.id], createdBy: .user)
        manager.createRoom(title: "Room2", agentIDs: [agent.id], createdBy: .user)

        manager.syncAgentStatuses()
        let updated = store.agents.first(where: { $0.id == agent.id })
        #expect(updated?.status == .busy)
    }

    @Test("syncAgentStatuses - error 상태는 유지")
    func syncStatusPreservesError() {
        let (manager, store, _) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Worker")
        store.addAgent(agent)
        store.updateStatus(agentID: agent.id, status: .error, errorMessage: "fail")

        manager.syncAgentStatuses()
        let updated = store.agents.first(where: { $0.id == agent.id })
        #expect(updated?.status == .error)
    }

    // MARK: - 상태 전이 시나리오

    @Test("방 생명주기: planning → inProgress → completed")
    func roomLifecycleComplete() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Lifecycle", agentIDs: [], createdBy: .user)
        #expect(room.status == .planning)
        #expect(room.isActive)

        // planning → inProgress
        if let idx = manager.rooms.firstIndex(where: { $0.id == room.id }) {
            _ = manager.rooms[idx].transitionTo(.inProgress)
        }
        #expect(manager.rooms.first?.status == .inProgress)

        // inProgress → completed
        manager.completeRoom(room.id)
        let completed = manager.rooms.first(where: { $0.id == room.id })
        #expect(completed?.status == .completed)
        #expect(completed?.isActive == false)
        #expect(completed?.completedAt != nil)
    }

    @Test("방 생명주기: 생성 → 삭제")
    func roomLifecycleDelete() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Lifecycle", agentIDs: [], createdBy: .user)
        manager.deleteRoom(room.id)
        #expect(manager.rooms.first(where: { $0.id == room.id }) == nil)
    }
}
