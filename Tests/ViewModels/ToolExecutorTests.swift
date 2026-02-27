import Testing
import Foundation
@testable import DOUGLAS

@Suite("ToolExecutor Tests")
struct ToolExecutorTests {

    // MARK: - 도우미

    private func makeAgent(
        preset: CapabilityPreset? = nil,
        enabledToolIDs: [String]? = nil
    ) -> Agent {
        Agent(
            name: "test-agent",
            persona: "test",
            providerName: "MockProvider",
            modelName: "mock-model",
            capabilityPreset: preset,
            enabledToolIDs: enabledToolIDs
        )
    }

    private func makeMockProvider(supportsTools: Bool = false) -> MockAIProvider {
        let p = MockAIProvider()
        p._supportsToolCalling = supportsTools
        return p
    }

    // MARK: - smartSend 분기

    @Test("smartSend — 도구 없는 에이전트는 기존 sendMessage 사용")
    func smartSendNoTools() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageResult = .success("plain response")
        let agent = makeAgent(preset: nil)

        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "sys", messages: [("user", "hello")]
        )
        #expect(result == "plain response")
        #expect(provider.sendMessageCallCount == 1)
        #expect(provider.sendMessageWithToolsCallCount == 0)
    }

    @Test("smartSend — 프로바이더가 도구 미지원이면 기존 sendMessage 사용")
    func smartSendProviderNoToolSupport() async throws {
        let provider = makeMockProvider(supportsTools: false)
        provider.sendMessageResult = .success("fallback response")
        let agent = makeAgent(preset: .developer)

        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "sys", messages: [("user", "hello")]
        )
        #expect(result == "fallback response")
        #expect(provider.sendMessageCallCount == 1)
        #expect(provider.sendMessageWithToolsCallCount == 0)
    }

    @Test("smartSend — 도구 있고 프로바이더 지원 시 sendMessageWithTools 사용")
    func smartSendWithTools() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [.success(.text("tool response"))]
        let agent = makeAgent(preset: .developer)

        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "sys", messages: [("user", "read file")]
        )
        #expect(result == "tool response")
        #expect(provider.sendMessageWithToolsCallCount == 1)
        #expect(provider.sendMessageCallCount == 0)
    }

    // MARK: - executeWithTools 루프

    @Test("executeWithTools — 텍스트 응답 즉시 반환")
    func singleTextResponse() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [.success(.text("done"))]
        let tools = ToolRegistry.tools(for: ["file_read"])
        let messages = [ConversationMessage.user("hello")]

        let result = try await ToolExecutor.executeWithTools(
            provider: provider, model: "m", systemPrompt: "s",
            initialMessages: messages, tools: tools
        )
        #expect(result == "done")
        #expect(provider.sendMessageWithToolsCallCount == 1)
    }

    @Test("executeWithTools — 도구 호출 후 텍스트 응답 (2라운드)")
    func toolCallThenText() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "web_search", arguments: ["query": .string("test")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("search complete"))
        ]
        let messages = [ConversationMessage.user("search for test")]

        let result = try await ToolExecutor.executeWithTools(
            provider: provider, model: "m", systemPrompt: "s",
            initialMessages: messages, tools: ToolRegistry.allTools
        )
        #expect(result == "search complete")
        #expect(provider.sendMessageWithToolsCallCount == 2)
    }

    @Test("executeWithTools — mixed 응답 처리")
    func mixedResponse() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "web_search", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.mixed(text: "thinking...", toolCalls: [call])),
            .success(.text("final"))
        ]
        let messages = [ConversationMessage.user("go")]

        let result = try await ToolExecutor.executeWithTools(
            provider: provider, model: "m", systemPrompt: "s",
            initialMessages: messages, tools: ToolRegistry.allTools
        )
        #expect(result == "final")
        #expect(provider.sendMessageWithToolsCallCount == 2)
    }

    @Test("executeWithTools — 최대 반복 초과 시 오류")
    func maxIterationsExceeded() async throws {
        let provider = makeMockProvider(supportsTools: true)
        // 모든 응답을 도구 호출로 설정 → 무한 루프 시도
        let call = ToolCall(id: "c1", toolName: "web_search", arguments: [:])
        provider.sendMessageWithToolsResults = [.success(.toolCalls([call]))]
        // MockAIProvider는 마지막 결과를 반복하므로 항상 toolCalls 반환

        let messages = [ConversationMessage.user("loop")]
        await #expect(throws: AIProviderError.self) {
            _ = try await ToolExecutor.executeWithTools(
                provider: provider, model: "m", systemPrompt: "s",
                initialMessages: messages, tools: ToolRegistry.allTools
            )
        }
        #expect(provider.sendMessageWithToolsCallCount == ToolExecutor.maxIterations)
    }

    @Test("executeWithTools — onToolActivity 콜백 호출")
    func toolActivityCallback() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "web_search", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("done"))
        ]
        var activities: [String] = []
        let messages = [ConversationMessage.user("go")]

        _ = try await ToolExecutor.executeWithTools(
            provider: provider, model: "m", systemPrompt: "s",
            initialMessages: messages, tools: ToolRegistry.allTools,
            onToolActivity: { activities.append($0) }
        )
        #expect(activities.count == 2)
        #expect(activities[0].contains("도구 호출"))
        #expect(activities[1].contains("도구 결과"))
    }

    @Test("executeWithTools — 여러 도구 동시 호출")
    func multipleToolCalls() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let calls = [
            ToolCall(id: "c1", toolName: "web_search", arguments: [:]),
            ToolCall(id: "c2", toolName: "web_search", arguments: [:])
        ]
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls(calls)),
            .success(.text("all done"))
        ]
        var activityCount = 0
        let messages = [ConversationMessage.user("go")]

        let result = try await ToolExecutor.executeWithTools(
            provider: provider, model: "m", systemPrompt: "s",
            initialMessages: messages, tools: ToolRegistry.allTools,
            onToolActivity: { _ in activityCount += 1 }
        )
        #expect(result == "all done")
        // 2 calls × 2 activities (호출 + 결과) = 4
        #expect(activityCount == 4)
    }

    @Test("executeWithTools — 프로바이더 오류 전파")
    func providerErrorPropagation() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [.failure(AIProviderError.apiError("test error"))]
        let messages = [ConversationMessage.user("fail")]

        await #expect(throws: AIProviderError.self) {
            _ = try await ToolExecutor.executeWithTools(
                provider: provider, model: "m", systemPrompt: "s",
                initialMessages: messages, tools: ToolRegistry.allTools
            )
        }
    }

    // MARK: - 개별 도구 실행 (file_read, file_write, shell_exec)

    @Test("file_read — 실제 파일 읽기")
    func fileReadSuccess() async throws {
        let tmpDir = NSTemporaryDirectory()
        let filePath = (tmpDir as NSString).appendingPathComponent("toolexec_test_\(UUID().uuidString).txt")
        try "hello tool".write(toFile: filePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: filePath) }

        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "file_read", arguments: ["path": .string(filePath)])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("read done"))
        ]

        // smartSend로 실행하면 실제 파일 읽기가 동작하는지 확인
        let agent = makeAgent(preset: .developer)
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "read it")]
        )
        #expect(result == "read done")

        // 두 번째 호출 시 messages에 파일 내용이 포함되어야 함
        let lastArgs = provider.lastSendMessageWithToolsArgs
        let lastMessages = lastArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("hello tool") == true)
    }

    @Test("file_read — 존재하지 않는 파일")
    func fileReadNotFound() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "file_read", arguments: ["path": .string("/nonexistent/file.txt")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent(preset: .developer)
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "read")]
        )
        #expect(result == "handled")

        // 도구 결과가 오류여야 함
        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("실패") == true || toolResultMsg?.content?.contains("오류") == true)
    }

    @Test("file_read — path 파라미터 없음")
    func fileReadMissingPath() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "file_read", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent(preset: .developer)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "read")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("path") == true)
    }

    @Test("file_write — 실제 파일 쓰기")
    func fileWriteSuccess() async throws {
        let tmpDir = NSTemporaryDirectory()
        let filePath = (tmpDir as NSString).appendingPathComponent("toolexec_write_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(atPath: filePath) }

        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "file_write", arguments: [
            "path": .string(filePath),
            "content": .string("written by tool")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("write done"))
        ]

        let agent = makeAgent(preset: .developer)
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "write")]
        )
        #expect(result == "write done")

        // 실제 파일이 생성되었는지 확인
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(content == "written by tool")
    }

    @Test("file_write — content 파라미터 없음")
    func fileWriteMissingContent() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "file_write", arguments: ["path": .string("/tmp/x")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent(preset: .developer)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "write")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("content") == true)
    }

    @Test("shell_exec — 간단한 명령 실행")
    func shellExecSuccess() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "shell_exec", arguments: ["command": .string("echo hello_tool_test")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("exec done"))
        ]

        let agent = makeAgent(preset: .developer)
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "run")]
        )
        #expect(result == "exec done")

        // 도구 결과에 echo 출력이 포함되어야 함
        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("hello_tool_test") == true)
    }

    @Test("shell_exec — command 파라미터 없음")
    func shellExecMissingCommand() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "shell_exec", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent(preset: .developer)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "run")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("command") == true)
    }

    @Test("shell_exec — 실패하는 명령어")
    func shellExecFailure() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "shell_exec", arguments: ["command": .string("false")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent(preset: .developer)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "run")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        // 실패한 명령은 종료 코드가 0이 아니므로 오류 표시
        #expect(toolResultMsg?.content?.contains("종료 코드") == true)
    }

    @Test("알 수 없는 도구 — 오류 반환")
    func unknownTool() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "nonexistent_tool", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent(preset: .fullAccess)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "go")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("알 수 없는 도구") == true)
    }

    // MARK: - invite_agent / list_agents

    @Test("invite_agent — roomID 없으면 오류")
    func inviteAgentNoRoom() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "invite_agent", arguments: ["agent_name": .string("helper")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent(preset: .fullAccess)
        // context 없이 (기본 .empty → roomID nil)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "invite")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("방 안에서만") == true)
    }

    @Test("invite_agent — 에이전트명 미매칭 오류")
    func inviteAgentNotFound() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "invite_agent", arguments: ["agent_name": .string("nonexistent")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: ["helper": UUID()],
            agentListString: "- helper",
            inviteAgent: { _ in true }
        )

        let agent = makeAgent(preset: .fullAccess)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "invite")],
            context: context
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("찾을 수 없습니다") == true)
        #expect(toolResultMsg?.content?.contains("helper") == true)
    }

    @Test("invite_agent — agent_name 파라미터 없음")
    func inviteAgentMissingName() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "invite_agent", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: [:],
            agentListString: "",
            inviteAgent: { _ in true }
        )

        let agent = makeAgent(preset: .fullAccess)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "invite")],
            context: context
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("agent_name") == true)
    }

    @Test("invite_agent — 성공 시 inviteAgent 클로저 호출")
    func inviteAgentSuccess() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "invite_agent", arguments: [
            "agent_name": .string("helper"),
            "reason": .string("도움 필요")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("done"))
        ]

        let helperID = UUID()
        var invitedID: UUID?
        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: ["helper": helperID],
            agentListString: "- helper",
            inviteAgent: { id in
                invitedID = id
                return true
            }
        )

        let agent = makeAgent(preset: .fullAccess)
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "invite helper")],
            context: context
        )
        #expect(result == "done")
        #expect(invitedID == helperID)

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("초대했습니다") == true)
        #expect(toolResultMsg?.content?.contains("도움 필요") == true)
    }

    @Test("invite_agent — 초대 실패")
    func inviteAgentFailure() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "invite_agent", arguments: ["agent_name": .string("helper")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: ["helper": UUID()],
            agentListString: "- helper",
            inviteAgent: { _ in false }
        )

        let agent = makeAgent(preset: .fullAccess)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "invite")],
            context: context
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("실패") == true)
    }

    @Test("list_agents — 에이전트 목록 반환")
    func listAgentsWithAgents() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "list_agents", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("done"))
        ]

        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: ["agent1": UUID(), "agent2": UUID()],
            agentListString: "- agent1 [OpenAI/gpt-4o]\n- agent2 [Anthropic/claude]",
            inviteAgent: { _ in true }
        )

        let agent = makeAgent(preset: .fullAccess)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "list")],
            context: context
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("agent1") == true)
        #expect(toolResultMsg?.content?.contains("agent2") == true)
    }

    @Test("list_agents — 빈 목록")
    func listAgentsEmpty() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "list_agents", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("done"))
        ]

        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: [:],
            agentListString: "",
            inviteAgent: { _ in true }
        )

        let agent = makeAgent(preset: .fullAccess)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "list")],
            context: context
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("없습니다") == true)
    }

    // MARK: - maxIterations 상수

    @Test("maxIterations는 10")
    func maxIterationsValue() {
        #expect(ToolExecutor.maxIterations == 10)
    }

    // MARK: - smartSend 메시지 변환

    @Test("smartSend — messages가 ConversationMessage로 올바르게 변환")
    func smartSendMessageConversion() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [.success(.text("ok"))]
        let agent = makeAgent(preset: .developer)

        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "sys prompt",
            messages: [("user", "msg1"), ("assistant", "msg2"), ("user", "msg3")]
        )

        let args = provider.lastSendMessageWithToolsArgs
        #expect(args?.systemPrompt == "sys prompt")
        #expect(args?.model == "mock-model")
        #expect(args?.messages.count == 3)
        #expect(args?.messages[0].role == "user")
        #expect(args?.messages[0].content == "msg1")
        #expect(args?.messages[1].role == "assistant")
        #expect(args?.messages[2].role == "user")
    }

    @Test("smartSend — 도구 프리셋에 맞는 도구만 전달")
    func smartSendToolFiltering() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [.success(.text("ok"))]
        let agent = makeAgent(preset: .researcher) // web_search + web_fetch

        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "go")]
        )

        let tools = provider.lastSendMessageWithToolsArgs?.tools ?? []
        #expect(tools.count == 2)
        #expect(tools.contains(where: { $0.id == "web_search" }))
        #expect(tools.contains(where: { $0.id == "web_fetch" }))
    }

    // MARK: - 경로 검증 테스트

    @Test("isPathAllowed — 홈 디렉토리 허용")
    func pathAllowedHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ToolExecutor.isPathAllowed("\(home)/Documents/test.txt") == true)
        #expect(ToolExecutor.isPathAllowed("\(home)/Desktop/project/file.swift") == true)
    }

    @Test("isPathAllowed — /tmp 허용")
    func pathAllowedTmp() {
        #expect(ToolExecutor.isPathAllowed("/tmp/test.txt") == true)
        #expect(ToolExecutor.isPathAllowed("/private/tmp/test.txt") == true)
    }

    @Test("isPathAllowed — 시스템 경로 차단")
    func pathBlockedSystem() {
        #expect(ToolExecutor.isPathAllowed("/etc/passwd") == false)
        #expect(ToolExecutor.isPathAllowed("/usr/bin/ls") == false)
        #expect(ToolExecutor.isPathAllowed("/System/Library/test") == false)
    }

    @Test("isPathAllowed — 민감 디렉토리 차단")
    func pathBlockedSensitive() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ToolExecutor.isPathAllowed("\(home)/.ssh/id_rsa") == false)
        #expect(ToolExecutor.isPathAllowed("\(home)/.gnupg/private-keys-v1.d/key") == false)
        #expect(ToolExecutor.isPathAllowed("\(home)/Library/Keychains/login.keychain") == false)
    }

    @Test("isPathAllowed — 상대 경로 ../로 탈출 시도 차단")
    func pathBlockedTraversal() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // ../를 이용한 탈출은 URL.standardized가 해석하므로 결과 경로가 허용 범위 내인지 확인
        #expect(ToolExecutor.isPathAllowed("\(home)/Documents/../../etc/passwd") == false)
    }

    @Test("isPathAllowed — NSTemporaryDirectory 허용")
    func pathAllowedNSTemp() {
        let tmpDir = NSTemporaryDirectory()
        let testPath = (tmpDir as NSString).appendingPathComponent("test_file.txt")
        #expect(ToolExecutor.isPathAllowed(testPath) == true)
    }

    @Test("file_read — 차단된 경로 접근 시 오류")
    func fileReadBlockedPath() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "file_read", arguments: ["path": .string("/etc/passwd")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent(preset: .developer)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "read")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("허용되지 않은") == true)
    }

    @Test("file_write — 차단된 경로 쓰기 시 오류")
    func fileWriteBlockedPath() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "file_write", arguments: [
            "path": .string("/etc/evil.txt"),
            "content": .string("malicious")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent(preset: .developer)
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "write")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("허용되지 않은") == true)
    }
}
