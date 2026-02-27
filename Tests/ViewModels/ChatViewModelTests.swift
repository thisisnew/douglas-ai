import Testing
import Foundation
@testable import DOUGLAS

@Suite("ChatViewModel State Tests")
@MainActor
struct ChatViewModelTests {

    @Test("init - 빈 상태")
    func initEmpty() {
        let vm = ChatViewModel()
        let randomID = UUID()
        #expect(vm.messages(for: randomID).isEmpty)
        #expect(vm.loadingAgentIDs.isEmpty)
    }

    @Test("messages(for:) - 빈 목록")
    func messagesEmpty() {
        let vm = ChatViewModel()
        #expect(vm.messages(for: UUID()).isEmpty)
    }

    @Test("appendMessagePublic")
    func appendMessage() {
        let vm = ChatViewModel()
        let agentID = UUID()
        let msg = makeTestMessage(content: "Hello")
        vm.appendMessagePublic(msg, for: agentID)
        let messages = vm.messages(for: agentID)
        #expect(messages.count == 1)
        #expect(messages.first?.content == "Hello")
    }

    @Test("appendMessagePublic - 여러 메시지")
    func appendMultipleMessages() {
        let vm = ChatViewModel()
        let agentID = UUID()
        for i in 0..<5 {
            let msg = makeTestMessage(content: "Message \(i)")
            vm.appendMessagePublic(msg, for: agentID)
        }
        #expect(vm.messages(for: agentID).count == 5)
    }

    @Test("messages(for:) - 에이전트 간 격리")
    func messagesIsolation() {
        let vm = ChatViewModel()
        let agent1 = UUID()
        let agent2 = UUID()
        vm.appendMessagePublic(makeTestMessage(content: "A"), for: agent1)
        vm.appendMessagePublic(makeTestMessage(content: "B"), for: agent2)
        #expect(vm.messages(for: agent1).count == 1)
        #expect(vm.messages(for: agent2).count == 1)
        #expect(vm.messages(for: agent1).first?.content == "A")
        #expect(vm.messages(for: agent2).first?.content == "B")
    }

    @Test("isLoading - 초기 상태")
    func isLoadingInitial() {
        let vm = ChatViewModel()
        #expect(!vm.loadingAgentIDs.contains(UUID()))
    }

    @Test("cancelTask")
    func cancelTask() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.loadingAgentIDs.insert(agentID)
        vm.cancelTask(for: agentID)
        #expect(!vm.loadingAgentIDs.contains(agentID))
    }

    @Test("buildHistory - 내부 메시지 필터링")
    func buildHistoryFilters() {
        let vm = ChatViewModel()
        let agentID = UUID()
        // 다양한 타입의 메시지 추가
        vm.appendMessagePublic(makeTestMessage(content: "text", messageType: .text), for: agentID)
        vm.appendMessagePublic(makeTestMessage(content: "delegation", messageType: .delegation), for: agentID)
        vm.appendMessagePublic(makeTestMessage(content: "chain", messageType: .chainProgress), for: agentID)
        vm.appendMessagePublic(makeTestMessage(content: "error", messageType: .error), for: agentID)
        vm.appendMessagePublic(makeTestMessage(content: "summary", messageType: .summary), for: agentID)
        vm.appendMessagePublic(makeTestMessage(content: "suggestion", messageType: .suggestion), for: agentID)

        let history = vm.buildHistory(for: agentID)
        // text와 summary만 포함되어야 함
        #expect(history.count == 2)
        let contents = history.map { $0.content }
        #expect(contents.contains("text"))
        #expect(contents.contains("summary"))
        #expect(!contents.contains("delegation"))
        #expect(!contents.contains("chain"))
    }

    @Test("buildHistory - 최대 20개 제한")
    func buildHistoryLimits() {
        let vm = ChatViewModel()
        let agentID = UUID()
        for i in 0..<25 {
            vm.appendMessagePublic(makeTestMessage(content: "msg \(i)"), for: agentID)
        }
        let history = vm.buildHistory(for: agentID)
        #expect(history.count == 20)
        // suffix(20)이므로 마지막 20개
        #expect(history.last?.content == "msg 24")
    }

    @Test("buildHistory - 역할 매핑")
    func buildHistoryRoleMapping() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.appendMessagePublic(makeTestMessage(role: .user, content: "u"), for: agentID)
        vm.appendMessagePublic(makeTestMessage(role: .assistant, content: "a"), for: agentID)
        vm.appendMessagePublic(makeTestMessage(role: .system, content: "s"), for: agentID)

        let history = vm.buildHistory(for: agentID)
        #expect(history[0].role == "user")
        #expect(history[1].role == "assistant")
        #expect(history[2].role == "system")
    }

    @Test("showToastMessage")
    func showToast() {
        let vm = ChatViewModel()
        vm.showToastMessage("Error occurred")
        #expect(vm.toastMessage == "Error occurred")
        #expect(vm.showToast == true)
    }

    @Test("messages(for: nil) - 빈 배열")
    func messagesForNil() {
        let vm = ChatViewModel()
        #expect(vm.messages(for: nil).isEmpty)
    }

    @Test("isLoading(for: nil) - false")
    func isLoadingForNil() {
        let vm = ChatViewModel()
        #expect(vm.isLoading(for: nil) == false)
    }

    @Test("isLoading(for:) - 로딩 중인 에이전트")
    func isLoadingForAgent() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.loadingAgentIDs.insert(agentID)
        #expect(vm.isLoading(for: agentID) == true)
        #expect(vm.isLoading(for: UUID()) == false)
    }

    @Test("configure - 의존성 설정")
    func configure() {
        let vm = ChatViewModel()
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let providerManager = ProviderManager(defaults: defaults)

        vm.configure(agentStore: store, providerManager: providerManager)
        #expect(vm.agentStore != nil)
        #expect(vm.providerManager != nil)
    }

    @Test("clearMessages")
    func clearMessages() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.appendMessagePublic(makeTestMessage(content: "msg1"), for: agentID)
        vm.appendMessagePublic(makeTestMessage(content: "msg2"), for: agentID)
        #expect(vm.messages(for: agentID).count == 2)
        vm.clearMessages(for: agentID)
        #expect(vm.messages(for: agentID).isEmpty)
    }

    @Test("buildHistory - 빈 에이전트")
    func buildHistoryEmpty() {
        let vm = ChatViewModel()
        let history = vm.buildHistory(for: UUID())
        #expect(history.isEmpty)
    }

    @Test("cancelTask - 중복 취소")
    func cancelTaskTwice() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.loadingAgentIDs.insert(agentID)
        vm.cancelTask(for: agentID)
        vm.cancelTask(for: agentID)
        #expect(!vm.loadingAgentIDs.contains(agentID))
    }

    @Test("showToastMessage - 덮어쓰기")
    func showToastOverwrite() {
        let vm = ChatViewModel()
        vm.showToastMessage("First")
        vm.showToastMessage("Second")
        #expect(vm.toastMessage == "Second")
        #expect(vm.showToast == true)
    }

    @Test("pendingSuggestion - 초기값 nil")
    func pendingSuggestionInitial() {
        let vm = ChatViewModel()
        #expect(vm.pendingSuggestion == nil)
    }

    // MARK: - buildConversationHistory

    @Test("buildConversationHistory - 내부 메시지 필터링")
    func buildConversationHistoryFilters() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.appendMessagePublic(makeTestMessage(content: "text", messageType: .text), for: agentID)
        vm.appendMessagePublic(makeTestMessage(content: "delegation", messageType: .delegation), for: agentID)
        vm.appendMessagePublic(makeTestMessage(content: "summary", messageType: .summary), for: agentID)
        vm.appendMessagePublic(makeTestMessage(content: "error", messageType: .error), for: agentID)

        let history = vm.buildConversationHistory(for: agentID)
        #expect(history.count == 2)
        #expect(history[0].content == "text")
        #expect(history[1].content == "summary")
    }

    @Test("buildConversationHistory - 역할 매핑")
    func buildConversationHistoryRoles() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.appendMessagePublic(makeTestMessage(role: .user, content: "u"), for: agentID)
        vm.appendMessagePublic(makeTestMessage(role: .assistant, content: "a"), for: agentID)
        vm.appendMessagePublic(makeTestMessage(role: .system, content: "s"), for: agentID)

        let history = vm.buildConversationHistory(for: agentID)
        #expect(history[0].role == "user")
        #expect(history[1].role == "assistant")
        #expect(history[2].role == "system")
    }

    @Test("buildConversationHistory - 최대 20개 제한")
    func buildConversationHistoryLimit() {
        let vm = ChatViewModel()
        let agentID = UUID()
        for i in 0..<25 {
            vm.appendMessagePublic(makeTestMessage(content: "msg \(i)"), for: agentID)
        }
        let history = vm.buildConversationHistory(for: agentID)
        #expect(history.count == 20)
        #expect(history.last?.content == "msg 24")
    }

    @Test("buildConversationHistory - 빈 에이전트")
    func buildConversationHistoryEmpty() {
        let vm = ChatViewModel()
        let history = vm.buildConversationHistory(for: UUID())
        #expect(history.isEmpty)
    }

    @Test("buildConversationHistory - ConversationMessage 구조 확인")
    func buildConversationHistoryStructure() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.appendMessagePublic(makeTestMessage(role: .user, content: "hello"), for: agentID)

        let history = vm.buildConversationHistory(for: agentID)
        #expect(history.count == 1)
        let msg = history[0]
        #expect(msg.role == "user")
        #expect(msg.content == "hello")
        #expect(msg.toolCalls == nil)
        #expect(msg.toolCallID == nil)
    }

    // MARK: - configure with roomManager

    @Test("configure - roomManager 포함")
    func configureWithRoomManager() {
        let vm = ChatViewModel()
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let providerManager = ProviderManager(defaults: defaults)
        let roomManager = RoomManager()

        vm.configure(agentStore: store, providerManager: providerManager, roomManager: roomManager)
        #expect(vm.agentStore != nil)
        #expect(vm.providerManager != nil)
        #expect(vm.roomManager != nil)
    }

    @Test("configure - roomManager 생략")
    func configureWithoutRoomManager() {
        let vm = ChatViewModel()
        let defaults = makeTestDefaults()
        let store = AgentStore(defaults: defaults)
        let providerManager = ProviderManager(defaults: defaults)

        vm.configure(agentStore: store, providerManager: providerManager)
        #expect(vm.roomManager == nil)
    }
}

// MARK: - AgentSuggestion

@Suite("AgentSuggestion Tests")
struct AgentSuggestionTests {

    @Test("기본 초기화")
    func initBasic() {
        let masterID = UUID()
        let suggestion = AgentSuggestion(
            name: "코더",
            persona: "코드를 작성합니다",
            recommendedProvider: "OpenAI",
            recommendedModel: "gpt-4o",
            recommendedPreset: "developer",
            masterAgentID: masterID,
            originalTask: "코드 작성해줘"
        )
        #expect(suggestion.name == "코더")
        #expect(suggestion.persona == "코드를 작성합니다")
        #expect(suggestion.recommendedProvider == "OpenAI")
        #expect(suggestion.recommendedModel == "gpt-4o")
        #expect(suggestion.recommendedPreset == "developer")
        #expect(suggestion.masterAgentID == masterID)
        #expect(suggestion.originalTask == "코드 작성해줘")
    }

    @Test("Identifiable - 고유 ID")
    func identifiable() {
        let a = AgentSuggestion(
            name: "A", persona: "p", recommendedProvider: "P",
            recommendedModel: "M", recommendedPreset: nil,
            masterAgentID: UUID(), originalTask: "t"
        )
        let b = AgentSuggestion(
            name: "A", persona: "p", recommendedProvider: "P",
            recommendedModel: "M", recommendedPreset: nil,
            masterAgentID: UUID(), originalTask: "t"
        )
        #expect(a.id != b.id)
    }

    @Test("recommendedPreset - nil 허용")
    func presetNil() {
        let suggestion = AgentSuggestion(
            name: "A", persona: "p", recommendedProvider: "P",
            recommendedModel: "M", recommendedPreset: nil,
            masterAgentID: UUID(), originalTask: "t"
        )
        #expect(suggestion.recommendedPreset == nil)
    }
}

// MARK: - MasterAction

@Suite("MasterAction Tests")
struct MasterActionTests {

    @Test("ChainStep - 초기화")
    func chainStepInit() {
        let step = MasterAction.ChainStep(agent: "코더", task: "코드 작성")
        #expect(step.agent == "코더")
        #expect(step.task == "코드 작성")
    }

    @Test("delegate - 연관값 접근")
    func delegateValues() {
        let action = MasterAction.delegate(
            agents: ["A", "B"],
            task: "비교 분석",
            contextFrom: ["C"]
        )
        if case .delegate(let agents, let task, let context) = action {
            #expect(agents == ["A", "B"])
            #expect(task == "비교 분석")
            #expect(context == ["C"])
        } else {
            Issue.record("Expected .delegate")
        }
    }

    @Test("delegate - contextFrom nil")
    func delegateNoContext() {
        let action = MasterAction.delegate(agents: ["A"], task: "t", contextFrom: nil)
        if case .delegate(_, _, let context) = action {
            #expect(context == nil)
        } else {
            Issue.record("Expected .delegate")
        }
    }

    @Test("suggestAgent - 연관값 접근")
    func suggestAgentValues() {
        let action = MasterAction.suggestAgent(
            name: "리서처", persona: "연구", provider: "Google", model: "gemini", preset: "researcher"
        )
        if case .suggestAgent(let name, let persona, let provider, let model, let preset) = action {
            #expect(name == "리서처")
            #expect(persona == "연구")
            #expect(provider == "Google")
            #expect(model == "gemini")
            #expect(preset == "researcher")
        } else {
            Issue.record("Expected .suggestAgent")
        }
    }

    @Test("chain - 연관값 접근")
    func chainValues() {
        let steps = [
            MasterAction.ChainStep(agent: "A", task: "step1"),
            MasterAction.ChainStep(agent: "B", task: "step2")
        ]
        let action = MasterAction.chain(steps: steps)
        if case .chain(let result) = action {
            #expect(result.count == 2)
            #expect(result[0].agent == "A")
            #expect(result[1].task == "step2")
        } else {
            Issue.record("Expected .chain")
        }
    }

    @Test("unknown - rawResponse 보존")
    func unknownRawResponse() {
        let action = MasterAction.unknown(rawResponse: "그냥 텍스트입니다")
        if case .unknown(let raw) = action {
            #expect(raw == "그냥 텍스트입니다")
        } else {
            Issue.record("Expected .unknown")
        }
    }
}
