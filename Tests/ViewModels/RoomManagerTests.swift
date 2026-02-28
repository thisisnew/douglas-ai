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

    @Test("sendUserMessage - 메시지 추가 + 에이전트 응답")
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
        #expect(msgs.contains(where: { $0.role == .assistant && $0.content == "에이전트 응답" }))
    }

    @Test("sendUserMessage - 에이전트 오류 시 에러 메시지")
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
        #expect(msgs.contains(where: { $0.messageType == .error }))
    }

    @Test("sendUserMessage - 존재하지 않는 방 → 무시")
    func sendUserMessageNoRoom() async {
        let (manager, _, _) = makeConfiguredManager()
        await manager.sendUserMessage("hello", to: UUID())
        // 크래시 없이 완료
    }

    // MARK: - startRoomWorkflow (단일 에이전트)

    @Test("startRoomWorkflow - 1인 → 토론 건너뛰기 → 계획 실패 → 폴백 실행")
    func startWorkflowSingleAgent() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Solo", providerName: "MockProvider")
        store.addAgent(agent)

        let mock = MockAIProvider()
        // 계획 수립: 유효하지 않은 JSON → 폴백
        // 실행: 일반 응답
        mock.sendMessageResult = .success("작업 완료했습니다")
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(title: "Solo Work", agentIDs: [agent.id], createdBy: .user)
        await manager.startRoomWorkflow(roomID: room.id, task: "테스트 작업")

        let updated = manager.rooms.first(where: { $0.id == room.id })
        #expect(updated?.status == .completed)
        #expect(updated?.completedAt != nil)
        #expect(updated?.plan != nil) // 폴백 계획이 설정됨
    }

    @Test("startRoomWorkflow - 1인 + 유효한 계획 → 정상 실행")
    func startWorkflowWithValidPlan() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Planner", providerName: "MockProvider")
        store.addAgent(agent)

        let mock = MockAIProvider()
        let planJSON = """
        {"plan": {"summary": "테스트 계획", "estimated_minutes": 2, "steps": ["1단계: 분석", "2단계: 실행"]}}
        """
        mock.sendMessageResults = [
            .success(planJSON),       // requestPlan 응답
            .success("1단계 완료"),   // executeStep (step 1)
            .success("2단계 완료"),   // executeStep (step 2)
            .success("일지 내용"),    // generateWorkLog
        ]
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(title: "Planned", agentIDs: [agent.id], createdBy: .user)
        await manager.startRoomWorkflow(roomID: room.id, task: "계획 실행")

        let updated = manager.rooms.first(where: { $0.id == room.id })
        #expect(updated?.status == .completed)
        #expect(updated?.plan?.summary == "테스트 계획")
        #expect(updated?.plan?.steps.count == 2)
        #expect(updated?.workLog != nil)
    }

    // MARK: - startRoomWorkflow (복수 에이전트 → 토론)

    @Test("startRoomWorkflow - 2인 → 토론 + 계획 + 실행")
    func startWorkflowMultiAgent() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent1 = makeTestAgent(name: "토론자A", providerName: "MockProvider")
        let agent2 = makeTestAgent(name: "토론자B", providerName: "MockProvider")
        store.addAgent(agent1)
        store.addAgent(agent2)

        let mock = MockAIProvider()
        // 토론: 첫 라운드부터 전원 합의
        let planJSON = """
        {"plan": {"summary": "합의 계획", "estimated_minutes": 1, "steps": ["실행"]}}
        """
        mock.sendMessageResults = [
            .success("좋은 방향이네요 [합의]"),  // 토론자A 1라운드
            .success("동의합니다 [합의]"),        // 토론자B 1라운드
            .success("토론 요약"),                 // generateDiscussionSummary
            .success(planJSON),                   // requestPlan
            .success("실행 완료"),                 // executeStep (agent1)
            .success("실행 완료"),                 // executeStep (agent2)
            .success("일지"),                      // generateWorkLog
        ]
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(
            title: "Team Work",
            agentIDs: [agent1.id, agent2.id],
            createdBy: .user
        )
        await manager.startRoomWorkflow(roomID: room.id, task: "팀 작업")

        let updated = manager.rooms.first(where: { $0.id == room.id })
        #expect(updated?.status == .completed)
    }

    // MARK: - launchWorkflow

    @Test("launchWorkflow - 비동기 시작 후 완료")
    func launchWorkflow() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent = makeTestAgent(name: "LaunchBot", providerName: "MockProvider")
        store.addAgent(agent)

        let mock = MockAIProvider()
        mock.sendMessageResult = .success("done")
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(title: "Launch", agentIDs: [agent.id], createdBy: .user)
        manager.launchWorkflow(roomID: room.id, task: "launch test")

        // 워크플로우 완료 대기
        try? await Task.sleep(for: .seconds(3))
        let updated = manager.rooms.first(where: { $0.id == room.id })
        #expect(updated?.status != .planning) // planning 아닌 다른 상태
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
    func saveLoadRooms() async {
        let manager = makeManager()
        let room = manager.createRoom(title: "Persist Test", agentIDs: [], createdBy: .user)
        manager.appendMessage(ChatMessage(role: .user, content: "saved"), to: room.id)

        // scheduleSave 디바운스 대기
        try? await Task.sleep(for: .seconds(1.5))

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

    // MARK: - startRoomWorkflow 에러 경로

    @Test("startRoomWorkflow - 존재하지 않는 방 → 무시")
    func startWorkflowNonExistent() async {
        let (manager, _, _) = makeConfiguredManager()
        await manager.startRoomWorkflow(roomID: UUID(), task: "test")
        // 크래시 없이 완료
    }

    @Test("startRoomWorkflow - 에이전트 없는 방 → 폴백 실행")
    func startWorkflowNoAgents() async {
        let (manager, _, _) = makeConfiguredManager()
        let room = manager.createRoom(title: "Empty", agentIDs: [], createdBy: .user)
        await manager.startRoomWorkflow(roomID: room.id, task: "작업")
        let updated = manager.rooms.first(where: { $0.id == room.id })
        // 에이전트가 없으면 계획 수립 실패 → 폴백 → 완료
        #expect(updated?.status == .completed)
    }

    // MARK: - requestPlan 에러 경로

    @Test("requestPlan 프로바이더 오류 → nil 반환")
    func requestPlanProviderError() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Planner", providerName: "MockProvider")
        store.addAgent(agent)

        let mock = MockAIProvider()
        mock.sendMessageResult = .failure(AIProviderError.apiError("오류"))
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(title: "Plan Fail", agentIDs: [agent.id], createdBy: .user)
        await manager.startRoomWorkflow(roomID: room.id, task: "테스트")

        // 계획 실패 → 폴백 계획으로 실행
        let updated = manager.rooms.first(where: { $0.id == room.id })
        #expect(updated?.status == .completed)
    }

    // MARK: - extractJSON 다양한 포맷

    @Test("parsePlan - JSON 코드 블록 포맷")
    func parsePlanCodeBlock() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent = makeTestAgent(name: "Planner", providerName: "MockProvider")
        store.addAgent(agent)

        let mock = MockAIProvider()
        let response = """
        여기에 계획이 있습니다:
        ```json
        {"plan": {"summary": "코드블록 계획", "estimated_minutes": 3, "steps": ["단계1"]}}
        ```
        이것이 제 계획입니다.
        """
        mock.sendMessageResults = [
            .success(response),      // requestPlan 응답
            .success("단계1 완료"),   // executeStep
            .success("일지"),         // generateWorkLog
        ]
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(title: "CodeBlock", agentIDs: [agent.id], createdBy: .user)
        await manager.startRoomWorkflow(roomID: room.id, task: "계획 실행")

        let updated = manager.rooms.first(where: { $0.id == room.id })
        #expect(updated?.plan?.summary == "코드블록 계획")
        #expect(updated?.status == .completed)
    }

    // MARK: - executeStep 에러

    @Test("executeStep 프로바이더 오류 → 에러 메시지 추가")
    func executeStepError() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let agent = makeTestAgent(name: "FailBot", providerName: "MockProvider")
        store.addAgent(agent)

        let mock = MockAIProvider()
        let planJSON = """
        {"plan": {"summary": "실패 계획", "estimated_minutes": 1, "steps": ["실패 단계"]}}
        """
        mock.sendMessageResults = [
            .success(planJSON),
            .failure(AIProviderError.apiError("실행 오류")),  // executeStep 실패
            .success("일지"),  // generateWorkLog
        ]
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(title: "Fail", agentIDs: [agent.id], createdBy: .user)
        await manager.startRoomWorkflow(roomID: room.id, task: "실패 테스트")

        let msgs = manager.rooms.first(where: { $0.id == room.id })?.messages ?? []
        #expect(msgs.contains(where: { $0.messageType == .error && $0.content.contains("오류") }))
    }

    // MARK: - executeDiscussion 과반 합의

    @Test("토론 - 3인 중 과반 합의 → 종료")
    func discussionMajority() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let a1 = makeTestAgent(name: "A", providerName: "MockProvider")
        let a2 = makeTestAgent(name: "B", providerName: "MockProvider")
        let a3 = makeTestAgent(name: "C", providerName: "MockProvider")
        store.addAgent(a1)
        store.addAgent(a2)
        store.addAgent(a3)

        let mock = MockAIProvider()
        let planJSON = """
        {"plan": {"summary": "합의 계획", "estimated_minutes": 1, "steps": ["실행"]}}
        """
        mock.sendMessageResults = [
            // 토론 1라운드 (전원 합의 아님)
            .success("좋은 의견이네요"),          // A
            .success("동의합니다 [합의]"),         // B
            .success("더 논의가 필요합니다"),       // C
            // 토론 2라운드 (과반 합의: B + C)
            .success("좋은 방향이에요 [합의]"),    // A
            .success("동의합니다 [합의]"),         // B
            .success("저도 합의합니다 [합의]"),    // C
            // 토론 요약
            .success("토론 요약"),
            // 계획 + 실행 + 일지
            .success(planJSON),
            .success("실행 완료"), .success("실행 완료"), .success("실행 완료"),
            .success("일지"),
        ]
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(
            title: "Majority",
            agentIDs: [a1.id, a2.id, a3.id],
            createdBy: .user
        )
        await manager.startRoomWorkflow(roomID: room.id, task: "토론 주제")

        let msgs = manager.rooms.first(where: { $0.id == room.id })?.messages ?? []
        // 합의 메시지가 있어야 함
        #expect(msgs.contains(where: { $0.content.contains("합의") && $0.role == .system }))
        let updated = manager.rooms.first(where: { $0.id == room.id })
        #expect(updated?.status == .completed)
    }

    // MARK: - generateBriefing 오류

    @Test("토론 브리핑 생성 실패 → 에러 메시지")
    func discussionSummaryError() async {
        let (manager, store, providerManager) = makeConfiguredManager()
        let a1 = makeTestAgent(name: "토론A", providerName: "MockProvider")
        let a2 = makeTestAgent(name: "토론B", providerName: "MockProvider")
        store.addAgent(a1)
        store.addAgent(a2)

        let mock = MockAIProvider()
        let planJSON = """
        {"plan": {"summary": "계획", "estimated_minutes": 1, "steps": ["실행"]}}
        """
        mock.sendMessageResults = [
            // 토론 1라운드 (전원 합의)
            .success("동의합니다 [합의]"),
            .success("저도 합의 [합의]"),
            // 토론 요약 실패
            .failure(AIProviderError.apiError("요약 오류")),
            // 계획 + 실행 + 일지 (요약 실패해도 계속 진행)
            .success(planJSON),
            .success("실행 완료"), .success("실행 완료"),
            .success("일지"),
        ]
        providerManager.testProviderOverrides["MockProvider"] = mock

        let room = manager.createRoom(
            title: "SummaryFail",
            agentIDs: [a1.id, a2.id],
            createdBy: .user
        )
        await manager.startRoomWorkflow(roomID: room.id, task: "토론")

        let msgs = manager.rooms.first(where: { $0.id == room.id })?.messages ?? []
        #expect(msgs.contains(where: { $0.messageType == .error && $0.content.contains("브리핑 생성 실패") }))
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
}
