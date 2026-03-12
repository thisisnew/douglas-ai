import Testing
import Foundation
@testable import DOUGLAS

@Suite("RoomManager Tests")
@MainActor
struct RoomManagerTests {

    // MARK: - Helper

    /// 테스트용 임시 디렉토리 (프로세스 단위 격리)
    private static let testRoomDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("douglas-roommanager-tests-\(ProcessInfo.processInfo.processIdentifier)")

    private func makeManager() -> RoomManager {
        RoomManager.roomDirectoryOverride = Self.testRoomDir
        return RoomManager()
    }

    private func makeConfiguredManager() -> (RoomManager, AgentStore, ProviderManager) {
        RoomManager.roomDirectoryOverride = Self.testRoomDir
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
            mode: .discussion
        )
        #expect(room.mode == .discussion)
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

    @Test("completeRoom - planning에서도 완료 가능")
    func completeRoomFromPlanning() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Test", agentIDs: [], createdBy: .user)
        manager.completeRoom(room.id)
        let found = manager.rooms.first(where: { $0.id == room.id })
        #expect(found?.status == .completed)
        #expect(found?.completedAt != nil)
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

    @Test("syncAgentStatuses - working (참여 방 2개)")
    func syncStatusWorking2Rooms() {
        let (manager, store, _) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Worker")
        store.addAgent(agent)
        manager.createRoom(title: "Room1", agentIDs: [agent.id], createdBy: .user)
        manager.createRoom(title: "Room2", agentIDs: [agent.id], createdBy: .user)

        manager.syncAgentStatuses()
        let updated = store.agents.first(where: { $0.id == agent.id })
        #expect(updated?.status == .working) // 1~2개 방 = working
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

    // MARK: - createManualRoom

    @Test("createManualRoom - 방 생성 + 메시지 추가")
    func createManualRoom() {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Worker", providerName: "MockProvider")
        store.addAgent(agent)

        let mock = MockAIProvider()
        mock.sendMessageResult = .success("mock response")
        providerManager.testProviderOverrides["MockProvider"] = mock

        manager.createManualRoom(title: "Manual", agentIDs: [agent.id], task: "작업하세요")

        #expect(manager.rooms.count == 1)
        let room = manager.rooms.first!
        #expect(room.title == "Manual")
        #expect(room.messages.contains(where: { $0.role == .user && $0.content == "작업하세요" }))
    }

    // MARK: - sendUserMessage

    @Test("sendUserMessage - 활성 방에 메시지 추가 → 추가 요건 노트")
    func sendUserMessage() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Worker", providerName: "MockProvider")
        store.addAgent(agent)

        let mock = MockAIProvider()
        mock.sendMessageResult = .success("에이전트 응답")
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(title: "Chat", agentIDs: [agent.id], createdBy: .user)
        await manager.sendUserMessage("추가 지시", to: room.id)

        let msgs = manager.rooms.first(where: { $0.id == room.id })?.messages ?? []
        #expect(msgs.contains(where: { $0.role == .user && $0.content == "추가 지시" }))
        // 활성 방이지만 userInput 대기 중이 아니므로 후속 사이클 시작 (추가 요건 노트 없음)
    }

    @Test("sendUserMessage - 활성 방에서 에러 없이 노트 추가")
    func sendUserMessageError() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent = makeTestAgent(name: "ErrorBot", providerName: "MockProvider")
        store.addAgent(agent)

        let mock = MockAIProvider()
        mock.sendMessageResult = .failure(AIProviderError.apiError("서버 오류"))
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(title: "Error", agentIDs: [agent.id], createdBy: .user)
        await manager.sendUserMessage("요청", to: room.id)

        let msgs = manager.rooms.first(where: { $0.id == room.id })?.messages ?? []
        // 활성 방이지만 userInput 대기 중 아님 → 후속 사이클 시작
        #expect(msgs.contains(where: { $0.role == .user && $0.content == "요청" }))
    }

    @Test("sendUserMessage - 존재하지 않는 방 → 무시")
    func sendUserMessageNoRoom() async {
        let (manager, _, _) = makeConfiguredManager()
        await manager.sendUserMessage("hello", to: UUID())
        // 크래시 없이 완료
    }

    // MARK: - speakingAgentIDByRoom

    @Test("deleteRoom - speakingAgentID 정리")
    func deleteRoomClearsSpeaking() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Test", agentIDs: [], createdBy: .user)
        manager.speakingAgentIDByRoom[room.id] = UUID()
        manager.deleteRoom(room.id)
        #expect(manager.speakingAgentIDByRoom[room.id] == nil)
    }

    @Test("completeRoom - speakingAgentID 정리")
    func completeRoomClearsSpeaking() {
        let manager = makeManager()
        let room = createInProgressRoom(manager)
        manager.speakingAgentIDByRoom[room.id] = UUID()
        manager.completeRoom(room.id)
        #expect(manager.speakingAgentIDByRoom[room.id] == nil)
    }

    // MARK: - saveRooms / loadRooms

    @Test("saveRooms / loadRooms 라운드트립")
    func saveLoadRooms() {
        let manager = makeManager()
        let room = manager.createRoom(title: "Persist Test", agentIDs: [], createdBy: .user)
        manager.appendMessage(ChatMessage(role: .user, content: "saved"), to: room.id)

        // 디바운스 대기 대신 직접 저장
        manager.saveRooms()

        let manager2 = makeManager()
        manager2.loadRooms()
        let loaded = manager2.rooms.first(where: { $0.id == room.id })
        #expect(loaded?.title == "Persist Test")

        // cleanup
        manager.deleteRoom(room.id)
    }

    @Test("loadRooms - 빈 디렉토리")
    func loadRoomsEmpty() {
        let manager = makeManager()
        manager.loadRooms()
        // 크래시 없이 완료
    }

    // MARK: - pendingAutoOpenRoomID

    @Test("pendingAutoOpenRoomID - 초기값 nil")
    func pendingAutoOpenInitial() {
        let manager = makeManager()
        #expect(manager.pendingAutoOpenRoomID == nil)
    }

    // MARK: - completedRooms 정렬

    @Test("completedRooms - completedAt 기준 정렬")
    func completedRoomsSorting() {
        let manager = makeManager()
        let room1 = createInProgressRoom(manager, title: "First")
        let room2 = createInProgressRoom(manager, title: "Second")
        manager.completeRoom(room1.id)
        manager.completeRoom(room2.id)

        let completed = manager.completedRooms
        #expect(completed.count == 2)
        // 최근 완료가 먼저 나와야 함
        #expect(completed.first?.title == "Second")
    }

    // MARK: - parsePlan: workingDirectory

    @Test("parsePlan - working_directory 추출")
    func parsePlan_extractsWorkingDirectory() {
        let mgr = makeManager()
        let json = """
        ```json
        {"plan": {"summary": "멀티 프로젝트 작업", "estimated_minutes": 10, "steps": [
            {"text": "백엔드 API 추가", "agent": "백엔드 개발자", "working_directory": "/Users/test/backend"},
            {"text": "프론트엔드 UI 구현", "agent": "프론트엔드 개발자", "working_directory": "/Users/test/frontend"}
        ]}}
        ```
        """
        let plan = mgr.parsePlan(from: json)
        #expect(plan != nil)
        #expect(plan?.steps.count == 2)
        #expect(plan?.steps[0].workingDirectory == "/Users/test/backend")
        #expect(plan?.steps[1].workingDirectory == "/Users/test/frontend")
    }

    @Test("parsePlan - working_directory 없으면 nil")
    func parsePlan_workingDirectoryNilWhenAbsent() {
        let mgr = makeManager()
        let json = """
        ```json
        {"plan": {"summary": "단일 프로젝트", "estimated_minutes": 5, "steps": [
            {"text": "코드 작성", "agent": "개발자"}
        ]}}
        ```
        """
        let plan = mgr.parsePlan(from: json)
        #expect(plan != nil)
        #expect(plan?.steps[0].workingDirectory == nil)
    }
}
