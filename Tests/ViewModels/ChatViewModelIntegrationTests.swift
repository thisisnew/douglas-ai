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

    @Test("sendMessage - 마스터에게 전송 → handleMasterMessage")
    func sendMessageToMaster() async {
        let mock = MockAIProvider()
        // 마스터 응답: unknown (일반 텍스트) → 바로 표시
        mock.sendMessageResult = .success("안녕하세요, 도움이 필요하시면 말씀해주세요.")
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)


        // 마스터의 providerName을 MockProvider로 설정
        if let masterIdx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[masterIdx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else {
            Issue.record("마스터 에이전트 없음")
            return
        }

        vm.sendMessage("안녕", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        let msgs = vm.messages(for: master.id)
        // user + toolActivity(분석 중) + assistant(응답)
        #expect(msgs.contains(where: { $0.role == .user && $0.content == "안녕" }))
        #expect(msgs.contains(where: { $0.role == .assistant && $0.content.contains("안녕하세요") }))
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

    // MARK: - handleMasterMessage → delegate (RoomManager 있을 때)

    @Test("마스터 delegate → RoomManager로 방 생성")
    func masterDelegateWithRoomManager() async {
        let mock = MockAIProvider()
        let delegateJSON = """
        {"action": "delegate", "agents": ["워커"], "task": "분석해줘"}
        """
        mock.sendMessageResult = .success(delegateJSON)
        let (vm, store, providerManager, _) = makeConfiguredVM(mockProvider: mock)


        // 서브 에이전트 추가
        let worker = Agent(name: "워커", persona: "일꾼", providerName: "MockProvider", modelName: "m")
        store.addAgent(worker)

        // 마스터 providerName 설정
        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        // RoomManager 설정
        let roomManager = RoomManager()
        roomManager.configure(agentStore: store, providerManager: providerManager)
        vm.configure(agentStore: store, providerManager: providerManager, roomManager: roomManager)

        guard let master = store.masterAgent else { return }
        vm.sendMessage("분석해줘", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        // 방이 생성되었는지 확인
        #expect(roomManager.rooms.count >= 1)
        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .delegation }))
    }

    // MARK: - handleMasterMessage → delegate (레거시, RoomManager 없음)

    @Test("마스터 delegate → 레거시 위임 (RoomManager 없음)")
    func masterDelegateLegacy() async {
        let mock = MockAIProvider()
        let delegateJSON = """
        {"action": "delegate", "agents": ["워커"], "task": "처리해줘"}
        """
        mock.sendMessageResults = [
            .success(delegateJSON),    // 마스터 응답
            .success("워커 결과입니다") // 워커 응답 (executeDelegation → smartSend → sendMessage)
        ]
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)


        let worker = Agent(name: "워커", persona: "일꾼", providerName: "MockProvider", modelName: "m")
        store.addAgent(worker)
        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }
        // roomManager 미설정 → 레거시 경로

        guard let master = store.masterAgent else { return }
        vm.sendMessage("처리해줘", agentID: master.id)
        await waitForIdle(vm, agentID: master.id, timeout: 10)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .delegation }))
    }

    // MARK: - handleMasterMessage → suggest_agent

    @Test("마스터 suggest_agent → pendingSuggestion 설정")
    func masterSuggestAgent() async {
        let mock = MockAIProvider()
        let suggestJSON = """
        {"action": "suggest_agent", "name": "번역가", "persona": "번역 전문가", "recommended_provider": "OpenAI", "recommended_model": "gpt-4o"}
        """
        mock.sendMessageResult = .success(suggestJSON)
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)


        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else { return }
        vm.sendMessage("번역해줘", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        #expect(vm.pendingSuggestion != nil)
        #expect(vm.pendingSuggestion?.name == "번역가")
        #expect(vm.pendingSuggestion?.persona == "번역 전문가")
        #expect(vm.pendingSuggestion?.originalTask == "번역해줘")

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .suggestion }))
    }

    // MARK: - handleMasterMessage → chain (RoomManager 있음)

    @Test("마스터 chain → RoomManager 방 생성")
    func masterChainWithRoomManager() async {
        let mock = MockAIProvider()
        let chainJSON = """
        {"action": "chain", "steps": [{"agent": "리서처", "task": "조사"}, {"agent": "작가", "task": "작성"}]}
        """
        mock.sendMessageResult = .success(chainJSON)
        let (vm, store, providerManager, _) = makeConfiguredVM(mockProvider: mock)


        let researcher = Agent(name: "리서처", persona: "연구", providerName: "MockProvider", modelName: "m")
        let writer = Agent(name: "작가", persona: "작성", providerName: "MockProvider", modelName: "m")
        store.addAgent(researcher)
        store.addAgent(writer)
        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        let roomManager = RoomManager()
        roomManager.configure(agentStore: store, providerManager: providerManager)
        vm.configure(agentStore: store, providerManager: providerManager, roomManager: roomManager)

        guard let master = store.masterAgent else { return }
        vm.sendMessage("조사 후 작성해줘", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        #expect(roomManager.rooms.count >= 1)
        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .chainProgress }))
    }

    // MARK: - handleMasterMessage → unknown (일반 텍스트)

    @Test("마스터 unknown 응답 → 원본 텍스트 표시")
    func masterUnknownResponse() async {
        let mock = MockAIProvider()
        mock.sendMessageResult = .success("그냥 일반 텍스트 답변입니다.")
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)


        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else { return }
        vm.sendMessage("안녕", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.content == "그냥 일반 텍스트 답변입니다." }))
    }

    // MARK: - handleMasterMessage → 프로바이더 오류

    @Test("마스터 프로바이더 오류 → 에러 메시지")
    func masterProviderError() async {
        let mock = MockAIProvider()
        mock.sendMessageResult = .failure(AIProviderError.apiError("API 연결 실패"))
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)


        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else { return }
        vm.sendMessage("실패할 요청", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .error }))
        #expect(vm.showToast == true)
    }

    // MARK: - handleMasterMessage → 프로바이더 못 찾음

    @Test("마스터 프로바이더 없음 → 에러")
    func masterProviderNotFound() async {
        let mock = MockAIProvider()
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)


        // providerName을 존재하지 않는 이름으로 설정
        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "NonExistentProvider"
        }

        guard let master = store.masterAgent else { return }
        vm.sendMessage("테스트", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .error }))
    }

    // MARK: - handleAgentMessage → 오류

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

    // MARK: - handleDelegation → 에이전트 없음

    @Test("위임 대상 에이전트 없음 → 에러 메시지")
    func delegateAgentNotFound() async {
        let mock = MockAIProvider()
        let delegateJSON = """
        {"action": "delegate", "agents": ["존재하지않는에이전트"], "task": "작업"}
        """
        mock.sendMessageResult = .success(delegateJSON)
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)


        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else { return }
        vm.sendMessage("작업해줘", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .error && $0.content.contains("찾을 수 없습니다") }))
    }

    // MARK: - saveMessages / loadMessages

    @Test("saveMessages / loadMessages 라운드트립")
    func saveLoadMessages() async {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.appendMessagePublic(makeTestMessage(role: .user, content: "saved msg"), for: agentID)

        // scheduleSave가 디바운스(1초)를 사용하므로 직접 호출
        // saveMessages는 private이므로, 잠시 대기 후 loadMessages로 확인
        try? await Task.sleep(for: .seconds(1.5))

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

    // MARK: - sendNotification / sendErrorNotification (bundleIdentifier 가드)

    @Test("알림 - CLI 빌드에서는 건너뜀")
    func notificationSkippedInCLI() async {
        // Bundle.main.bundleIdentifier가 nil인 테스트 환경에서 크래시 없이 실행
        let mock = MockAIProvider()
        mock.sendMessageResult = .success("응답")
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)


        let sub = Agent(name: "알림봇", persona: "테스트", providerName: "MockProvider", modelName: "m")
        store.addAgent(sub)

        vm.sendMessage("알림 테스트", agentID: sub.id)
        await waitForIdle(vm, agentID: sub.id)
        // 크래시 없이 완료되면 성공
    }

    // MARK: - cancelTask 동작

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

    // MARK: - showToastMessage 덮어쓰기

    @Test("showToastMessage - 이전 타이머 취소 후 새 메시지")
    func showToastMessageOverwrite() async {
        let vm = ChatViewModel()
        vm.showToastMessage("첫번째")
        vm.showToastMessage("두번째")
        #expect(vm.toastMessage == "두번째")
        #expect(vm.showToast == true)
    }

    // MARK: - executeDelegation 재시도 + 최종 실패

    @Test("위임 재시도 후 성공")
    func delegateRetryThenSuccess() async {
        let mock = MockAIProvider()
        // 첫 번째: 실패 → 두 번째: 성공
        mock.sendMessageResults = [
            .failure(AIProviderError.apiError("일시 오류")),
            .success("재시도 후 성공 응답")
        ]
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)

        let worker = Agent(name: "워커", persona: "일꾼", providerName: "MockProvider", modelName: "m")
        store.addAgent(worker)
        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        let delegateJSON = """
        {"action": "delegate", "agents": ["워커"], "task": "작업해줘"}
        """
        // 마스터 응답 뒤에 워커 응답들 설정
        mock.sendMessageResults = [
            .success(delegateJSON),           // 마스터
            .failure(AIProviderError.apiError("일시 오류")), // 워커 1차
            .success("재시도 성공!")            // 워커 2차
        ]

        guard let master = store.masterAgent else { return }
        vm.sendMessage("작업해줘", agentID: master.id)
        await waitForIdle(vm, agentID: master.id, timeout: 15)

        let msgs = vm.messages(for: master.id)
        // 재시도 메시지가 포함되어야 함
        #expect(msgs.contains(where: { $0.messageType == .error && $0.content.contains("재시도") }))
        // 최종 성공 응답도 포함
        #expect(msgs.contains(where: { $0.content == "재시도 성공!" }))
    }

    @Test("위임 최종 실패 → 에러 메시지")
    func delegateFinalFailure() async {
        let mock = MockAIProvider()
        let delegateJSON = """
        {"action": "delegate", "agents": ["워커"], "task": "작업"}
        """
        // 마스터 성공 + 워커 계속 실패 (재시도 소진)
        mock.sendMessageResults = [
            .success(delegateJSON),
            .failure(AIProviderError.apiError("영구 오류")),
            .failure(AIProviderError.apiError("영구 오류")),
            .failure(AIProviderError.apiError("영구 오류")),
        ]
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)

        let worker = Agent(name: "워커", persona: "일꾼", providerName: "MockProvider", modelName: "m")
        store.addAgent(worker)
        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else { return }
        vm.sendMessage("작업", agentID: master.id)
        await waitForIdle(vm, agentID: master.id, timeout: 20)

        let msgs = vm.messages(for: master.id)
        // 최종 실패 메시지가 있어야 함
        #expect(msgs.contains(where: { $0.messageType == .error && $0.content.contains("작업 실패") }))
        // 워커 상태가 error여야 함
        let workerAgent = store.agents.first(where: { $0.name == "워커" })
        #expect(workerAgent?.status == .error)
    }

    // MARK: - generateSummary (다중 위임)

    @Test("다중 위임 → 요약 생성")
    func multiDelegationSummary() async {
        let mock = MockAIProvider()
        let delegateJSON = """
        {"action": "delegate", "agents": ["리서처", "작가"], "task": "조사 후 작성"}
        """
        mock.sendMessageResults = [
            .success(delegateJSON),     // 마스터
            .success("리서처 결과"),     // 리서처
            .success("작가 결과"),       // 작가
            .success("종합 요약입니다"), // 요약 생성
        ]
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)

        let r = Agent(name: "리서처", persona: "연구", providerName: "MockProvider", modelName: "m")
        let w = Agent(name: "작가", persona: "작성", providerName: "MockProvider", modelName: "m")
        store.addAgent(r)
        store.addAgent(w)
        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else { return }
        vm.sendMessage("조사 후 작성", agentID: master.id)
        await waitForIdle(vm, agentID: master.id, timeout: 15)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .summary }))
    }

    // MARK: - legacyChain (RoomManager 없음)

    @Test("레거시 체인 - 순차 실행 성공")
    func legacyChainSuccess() async {
        let mock = MockAIProvider()
        let chainJSON = """
        {"action": "chain", "steps": [{"agent": "A", "task": "1단계"}, {"agent": "B", "task": "2단계"}]}
        """
        mock.sendMessageResults = [
            .success(chainJSON),   // 마스터
            .success("A 결과"),    // A 실행
            .success("B 결과"),    // B 실행
        ]
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)
        // roomManager 미설정 → 레거시 경로

        let a = Agent(name: "A", persona: "a", providerName: "MockProvider", modelName: "m")
        let b = Agent(name: "B", persona: "b", providerName: "MockProvider", modelName: "m")
        store.addAgent(a)
        store.addAgent(b)
        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else { return }
        vm.sendMessage("체인 실행", agentID: master.id)
        await waitForIdle(vm, agentID: master.id, timeout: 15)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .chainProgress && $0.content.contains("A → B") }))
        #expect(msgs.contains(where: { $0.content == "A 결과" }))
        #expect(msgs.contains(where: { $0.content == "B 결과" }))
        #expect(msgs.contains(where: { $0.messageType == .chainProgress && $0.content.contains("체인 완료") }))
    }

    @Test("레거시 체인 - 중간 실패 시 중단")
    func legacyChainMidFailure() async {
        let mock = MockAIProvider()
        let chainJSON = """
        {"action": "chain", "steps": [{"agent": "존재않는봇", "task": "1단계"}]}
        """
        mock.sendMessageResult = .success(chainJSON)
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)
        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else { return }
        vm.sendMessage("체인 실행", agentID: master.id)
        await waitForIdle(vm, agentID: master.id)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.contains(where: { $0.messageType == .error && $0.content.contains("찾을 수 없습니다") }))
    }

    // MARK: - activeTaskCounts (마스터 다중 메시지)

    @Test("마스터 다중 메시지 - loadingAgentIDs 병합")
    func masterMultipleMessages() async {
        let mock = MockAIProvider()
        mock.sendMessageResult = .success("응답")
        let (vm, store, _, _) = makeConfiguredVM(mockProvider: mock)

        if let idx = store.agents.firstIndex(where: { $0.isMaster }) {
            store.agents[idx].providerName = "MockProvider"
        }

        guard let master = store.masterAgent else { return }
        // 마스터에게 빠르게 두 번 전송 (각 질문 독립)
        vm.sendMessage("질문1", agentID: master.id)
        vm.sendMessage("질문2", agentID: master.id)

        // 두 작업 모두 끝날 때까지 대기
        await waitForIdle(vm, agentID: master.id, timeout: 10)

        let msgs = vm.messages(for: master.id)
        #expect(msgs.filter({ $0.role == .user }).count >= 2)
        #expect(!vm.loadingAgentIDs.contains(master.id))
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
