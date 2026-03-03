import Testing
import Foundation
@testable import DOUGLAS

@Suite("ChatViewModel Integration Tests", .serialized)
@MainActor
struct ChatViewModelIntegrationTests {

    // MARK: - Helper

    private func makeConfiguredVM(
        mockProvider: MockAIProvider = MockAIProvider(),
        providerName: String = "MockProvider"
    ) -> (ChatViewModel, AgentStore, ProviderManager, MockAIProvider) {
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let providerManager = ProviderManager(defaults: defaults)

        // testProviderOverrides로 MockAIProvider 주입
        providerManager.testProviderOverrides[providerName] = mockProvider

        let vm = ChatViewModel()
        vm.configure(agentStore: store, providerManager: providerManager)
        return (vm, store, providerManager, mockProvider)
    }

    /// 에이전트 로딩이 끝날 때까지 대기
    private func waitForIdle(_ vm: ChatViewModel, agentID: UUID, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !vm.loadingAgentIDs.contains(agentID) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - sendMessage 기본 분기

    @Test("sendMessage - configure 안 하면 무시")
    func sendMessageNoConfig() async {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.sendMessage("hello", agentID: agentID)
        // agentStore가 nil이므로 아무것도 안 함
        #expect(vm.messages(for: agentID).isEmpty)
        #expect(vm.loadingAgentIDs.isEmpty)
    }

    @Test("sendMessage - 존재하지 않는 에이전트 → 무시")
    func sendMessageUnknownAgent() async {
        let (vm, _, _, _) = makeConfiguredVM()

        vm.sendMessage("hello", agentID: UUID()) // 랜덤 ID
        #expect(vm.loadingAgentIDs.isEmpty)
    }

    @Test("sendMessage - 마스터에게 전송 → 방 생성 (RoomManager 있을 때)")
    func sendMessageToMasterCreatesRoom() async {
        let mock = MockAIProvider()
        let (vm, store, providerManager, _) = makeConfiguredVM(mockProvider: mock)

        let roomManager = makeTestRoomManager()
        roomManager.configure(agentStore: store, providerManager: providerManager)
        vm.configure(agentStore: store, providerManager: providerManager, roomManager: roomManager)

        guard let master = store.masterAgent else {
            Issue.record("마스터 에이전트 없음")
            return
        }

        vm.sendMessage("작업해줘", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        let msgs = vm.messages(for: master.id)
        // user 메시지 + toolActivity(방 생성 중) + delegation(작업 시작)
        #expect(msgs.contains(where: { $0.role == .user && $0.content == "작업해줘" }))
        #expect(msgs.contains(where: { $0.messageType == .delegation }))
        // 방이 생성되었는지 확인
        #expect(roomManager.rooms.count >= 1)
        #expect(roomManager.pendingAutoOpenRoomID != nil)
    }

    @Test("sendMessage - 마스터에게 전송 (RoomManager 없을 때) → 에러")
    func sendMessageToMasterNoRoomManager() async {
        let mock = MockAIProvider()
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)
        // roomManager 미설정

        guard let master = store.masterAgent else { return }
        vm.sendMessage("작업해줘", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .error }))
    }

    @Test("sendMessage - 서브 에이전트에게 전송 → handleAgentMessage")
    func sendMessageToSubAgent() async {
        let mock = MockAIProvider()
        mock.sendMessageResult = .success("서브 에이전트 응답입니다")
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)

        let subAgent = Agent(
            name: "테스터",
            persona: "테스트",
            providerName: "MockProvider",
            modelName: "mock-model"
        )
        store.addAgent(subAgent)

        vm.sendMessage("작업해줘", agentID: subAgent.id)
        await waitForIdle(vm, agentID: subAgent.id)

        let msgs = vm.messages(for: subAgent.id)
        #expect(msgs.contains(where: { $0.role == .user && $0.content == "작업해줘" }))
        #expect(msgs.contains(where: { $0.role == .assistant && $0.content == "서브 에이전트 응답입니다" }))
    }

    // MARK: - 서브 에이전트 오류

    @Test("서브 에이전트 프로바이더 오류 → 에러 메시지")
    func subAgentError() async {
        let mock = MockAIProvider()
        mock.sendMessageResult = .failure(AIProviderError.apiError("서버 오류"))
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)

        let sub = Agent(name: "에러봇", persona: "테스트", providerName: "MockProvider", modelName: "m")
        store.addAgent(sub)

        vm.sendMessage("요청", agentID: sub.id)
        await waitForIdle(vm, agentID: sub.id)

        let msgs = vm.messages(for: sub.id)
        #expect(msgs.contains(where: { $0.messageType == .error }))
        #expect(vm.showToast == true)
    }

    // MARK: - saveMessages / loadMessages

    @Test("saveMessages / loadMessages 라운드트립")
    func saveLoadMessages() async {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.appendMessagePublic(makeTestMessage(role: .user, content: "saved msg"), for: agentID)

        // scheduleSave 디바운스 대기 (1초 디바운스 + 여유)
        try? await Task.sleep(for: .milliseconds(1500))

        let vm2 = ChatViewModel()
        vm2.loadMessages()
        let loaded = vm2.messages(for: agentID)
        #expect(loaded.contains(where: { $0.content == "saved msg" }))

        // cleanup
        vm2.clearMessages(for: agentID)
    }

    @Test("loadMessages - 빈 디렉토리")
    func loadMessagesEmpty() {
        let vm = ChatViewModel()
        vm.loadMessages()
        // 크래시 없이 완료되면 성공
    }

    // MARK: - 알림

    @Test("알림 - CLI 빌드에서는 건너뜀")
    func notificationSkippedInCLI() async {
        let mock = MockAIProvider()
        mock.sendMessageResult = .success("응답")
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)

        let sub = Agent(name: "알림봇", persona: "테스트", providerName: "MockProvider", modelName: "m")
        store.addAgent(sub)

        vm.sendMessage("알림 테스트", agentID: sub.id)
        await waitForIdle(vm, agentID: sub.id)
        // 크래시 없이 완료되면 성공
    }

    // MARK: - cancelTask

    @Test("cancelTask - 로딩 상태 해제 + agentStore 상태 업데이트")
    func cancelTaskUpdatesState() {
        let (vm, store, _, _) = makeConfiguredVM()

        let sub = Agent(name: "워커", persona: "일꾼", providerName: "MockProvider", modelName: "m")
        store.addAgent(sub)
        store.updateStatus(agentID: sub.id, status: .working)

        vm.loadingAgentIDs.insert(sub.id)
        vm.cancelTask(for: sub.id)

        #expect(!vm.loadingAgentIDs.contains(sub.id))
        let updated = store.agents.first(where: { $0.id == sub.id })
        #expect(updated?.status == .idle)
    }

    // MARK: - 다중 에이전트 동시 요청

    @Test("여러 서브 에이전트 동시 메시지")
    func multipleAgentsConcurrent() async {
        let mock = MockAIProvider()
        mock.sendMessageResult = .success("응답")
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)

        let agent1 = Agent(name: "A", persona: "a", providerName: "MockProvider", modelName: "m")
        let agent2 = Agent(name: "B", persona: "b", providerName: "MockProvider", modelName: "m")
        store.addAgent(agent1)
        store.addAgent(agent2)

        vm.sendMessage("요청1", agentID: agent1.id)
        vm.sendMessage("요청2", agentID: agent2.id)

        await waitForIdle(vm, agentID: agent1.id)
        await waitForIdle(vm, agentID: agent2.id)

        #expect(vm.messages(for: agent1.id).count >= 2)
        #expect(vm.messages(for: agent2.id).count >= 2)
    }

    // MARK: - showToastMessage

    @Test("showToastMessage - 이전 타이머 취소 후 새 메시지")
    func showToastMessageOverwrite() async {
        let vm = ChatViewModel()
        vm.showToastMessage("첫번째")
        vm.showToastMessage("두번째")
        #expect(vm.toastMessage == "두번째")
        #expect(vm.showToast == true)
    }

    // MARK: - clearMessages

    @Test("clearMessages - 에이전트 메시지 전체 삭제")
    func clearMessagesTest() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.appendMessagePublic(makeTestMessage(role: .user, content: "1"), for: agentID)
        vm.appendMessagePublic(makeTestMessage(role: .assistant, content: "2"), for: agentID)
        #expect(vm.messages(for: agentID).count == 2)

        vm.clearMessages(for: agentID)
        #expect(vm.messages(for: agentID).isEmpty)
    }
}
