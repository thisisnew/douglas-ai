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
        let roomManager = makeTestRoomManager()

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

    // MARK: - extractRoomTitle

    @Test("extractRoomTitle — 빈 텍스트")
    func roomTitleEmpty() {
        #expect(ChatViewModel.extractRoomTitle(from: "") == "새 작업")
        #expect(ChatViewModel.extractRoomTitle(from: "", hasAttachments: true) == "이미지 분석")
    }

    @Test("extractRoomTitle — 일반 텍스트")
    func roomTitlePlainText() {
        #expect(ChatViewModel.extractRoomTitle(from: "로그인 기능 구현") == "로그인 기능 구현")
    }

    @Test("extractRoomTitle — 긴 텍스트 축약")
    func roomTitleLongText() {
        let long = String(repeating: "가", count: 40)
        let title = ChatViewModel.extractRoomTitle(from: long)
        #expect(title.count < 35)
        #expect(title.hasSuffix("…"))
    }

    @Test("extractRoomTitle — 단일 Jira URL")
    func roomTitleSingleJiraURL() {
        let title = ChatViewModel.extractRoomTitle(from: "https://company.atlassian.net/browse/IBS-100")
        #expect(title == "IBS-100")
    }

    @Test("extractRoomTitle — Jira URL + 텍스트")
    func roomTitleJiraWithText() {
        let title = ChatViewModel.extractRoomTitle(from: "https://company.atlassian.net/browse/IBS-100 분석해줘")
        #expect(title.contains("IBS-100"))
        #expect(title.contains("분석해줘"))
    }

    @Test("extractRoomTitle — 여러 Jira URL")
    func roomTitleMultipleJira() {
        let input = """
        https://company.atlassian.net/browse/IBS-100
        https://company.atlassian.net/browse/IBS-200
        https://company.atlassian.net/browse/IBS-300
        """
        let title = ChatViewModel.extractRoomTitle(from: input)
        #expect(title.contains("IBS"))
        #expect(title.contains("3건"))
    }

    @Test("extractRoomTitle — 여러 Jira URL + 텍스트")
    func roomTitleMultipleJiraWithText() {
        let input = """
        https://company.atlassian.net/browse/IBS-100
        https://company.atlassian.net/browse/IBS-200
        pr 링크 취합해줘
        """
        let title = ChatViewModel.extractRoomTitle(from: input)
        #expect(title.contains("IBS"))
        #expect(title.contains("2건"))
        #expect(title.contains("pr 링크 취합해줘"))
    }
}
