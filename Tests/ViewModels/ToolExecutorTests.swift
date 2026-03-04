import Testing
import Foundation
@testable import DOUGLAS

@Suite("ToolExecutor Tests")
struct ToolExecutorTests {

    // MARK: - 도우미

    private func makeAgent() -> Agent {
        Agent(
            name: "test-agent",
            persona: "test",
            providerName: "MockProvider",
            modelName: "mock-model"
        )
    }

    private func makeMockProvider(supportsTools: Bool = false) -> MockAIProvider {
        let p = MockAIProvider()
        p._supportsToolCalling = supportsTools
        return p
    }

    // MARK: - smartSend 분기

    @Test("smartSend — 프로바이더 도구 미지원이면 sendMessage 폴백")
    func smartSendNoTools() async throws {
        let provider = makeMockProvider(supportsTools: false)
        provider.sendMessageResult = .success("plain response")
        let agent = makeAgent()

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
        let agent = makeAgent()

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
        let agent = makeAgent()

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
            onToolActivity: { msg, _ in activities.append(msg) }
        )
        // 병렬 실행: 결과 콜백만 호출됨
        #expect(activities.count == 1)
        #expect(activities[0].contains("도구 결과"))
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
            onToolActivity: { _, _ in activityCount += 1 }
        )
        #expect(result == "all done")
        // 병렬 실행: 결과 콜백만 (도구 2개 × 1 결과)
        #expect(activityCount == 2)
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
        let agent = makeAgent()
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

        let agent = makeAgent()
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

        let agent = makeAgent()
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

        let agent = makeAgent()
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

        let agent = makeAgent()
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
        try await ProcessRunner.withMock({ _, args, _, _ in
            if args.contains(where: { $0.contains("echo hello_tool_test") }) {
                return (exitCode: 0, stdout: "hello_tool_test\n", stderr: "")
            }
            return (exitCode: 0, stdout: "", stderr: "")
        }) {
            let provider = makeMockProvider(supportsTools: true)
            let call = ToolCall(id: "c1", toolName: "shell_exec", arguments: ["command": .string("echo hello_tool_test")])
            provider.sendMessageWithToolsResults = [
                .success(.toolCalls([call])),
                .success(.text("exec done"))
            ]

            let agent = makeAgent()
            let result = try await ToolExecutor.smartSend(
                provider: provider, agent: agent,
                systemPrompt: "s", messages: [("user", "run")]
            )
            #expect(result == "exec done")

            let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
            let toolResultMsg = lastMessages.first { $0.role == "tool" }
            #expect(toolResultMsg?.content?.contains("hello_tool_test") == true)
        }
    }

    @Test("shell_exec — command 파라미터 없음")
    func shellExecMissingCommand() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "shell_exec", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
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
        try await ProcessRunner.withMock({ _, args, _, _ in
            if args.contains(where: { $0.contains("false") }) {
                return (exitCode: 1, stdout: "", stderr: "")
            }
            return (exitCode: 0, stdout: "", stderr: "")
        }) {
            let provider = makeMockProvider(supportsTools: true)
            let call = ToolCall(id: "c1", toolName: "shell_exec", arguments: ["command": .string("false")])
            provider.sendMessageWithToolsResults = [
                .success(.toolCalls([call])),
                .success(.text("handled"))
            ]

            let agent = makeAgent()
            _ = try await ToolExecutor.smartSend(
                provider: provider, agent: agent,
                systemPrompt: "s", messages: [("user", "run")]
            )

            let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
            let toolResultMsg = lastMessages.first { $0.role == "tool" }
            #expect(toolResultMsg?.content?.contains("종료 코드") == true)
        }
    }

    @Test("알 수 없는 도구 — 오류 반환")
    func unknownTool() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "nonexistent_tool", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
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

        let agent = makeAgent()
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

        let agent = makeAgent()
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

        let agent = makeAgent()
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

        let agent = makeAgent()
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

        let agent = makeAgent()
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

        let agent = makeAgent()
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

        let agent = makeAgent()
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
        let agent = makeAgent()

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

    @Test("smartSend — 모든 에이전트에 전체 도구 전달")
    func smartSendAllTools() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [.success(.text("ok"))]
        let agent = makeAgent()

        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "go")]
        )

        let tools = provider.lastSendMessageWithToolsArgs?.tools ?? []
        #expect(tools.count == ToolRegistry.allTools.count)
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

        let agent = makeAgent()
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

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "write")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResultMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolResultMsg?.content?.contains("허용되지 않은") == true)
    }

    // MARK: - smartSend (ConversationMessage 오버로드)

    @Test("smartSend ConversationMessage — 도구·이미지 없으면 sendMessage 폴백")
    func smartSendConvMessageFallback() async throws {
        let provider = makeMockProvider(supportsTools: false)
        provider.sendMessageResult = .success("simple response")
        let agent = makeAgent() // 도구 없음

        let messages = [ConversationMessage.user("hello"), ConversationMessage.assistant("hi")]
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "sys",
            conversationMessages: messages
        )
        #expect(result == "simple response")
        #expect(provider.sendMessageCallCount == 1)
        #expect(provider.sendMessageWithToolsCallCount == 0)
    }

    @Test("smartSend ConversationMessage — 이미지 있으면 sendMessageWithTools 사용")
    func smartSendConvMessageWithImage() async throws {
        let provider = makeMockProvider(supportsTools: false) // 도구 미지원이어도 이미지가 있으면 WithTools 경로
        provider.sendMessageWithToolsResults = [.success(.text("image analyzed"))]
        let agent = makeAgent() // 도구 없음

        let attachment = try FileAttachment.save(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), mimeType: "image/png")
        defer { attachment.delete() }
        let messages = [ConversationMessage.user("이미지 분석해줘", attachments: [attachment])]
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "sys",
            conversationMessages: messages
        )
        #expect(result == "image analyzed")
        #expect(provider.sendMessageWithToolsCallCount == 1)
    }

    @Test("smartSend ConversationMessage — 도구 있으면 sendMessageWithTools 사용")
    func smartSendConvMessageWithTools() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [.success(.text("tool result"))]
        let agent = makeAgent()

        let messages = [ConversationMessage.user("read file")]
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "sys",
            conversationMessages: messages
        )
        #expect(result == "tool result")
        #expect(provider.sendMessageWithToolsCallCount == 1)
    }

    // MARK: - web_fetch

    @Test("web_fetch — 유효하지 않은 URL")
    func webFetchInvalidURL() async throws {
        let provider = makeMockProvider(supportsTools: true)
        // 탭/개행이 포함된 문자열은 URL(string:)이 nil을 반환
        let call = ToolCall(id: "c1", toolName: "web_fetch", arguments: ["url": .string("ht\tp://bad")])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "fetch")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        #expect(toolResult?.content?.contains("url") == true)
    }

    @Test("web_fetch — url 파라미터 없음")
    func webFetchMissingURL() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "web_fetch", arguments: [:])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "fetch")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        #expect(toolResult?.content?.contains("url") == true)
    }

    // MARK: - file_read 큰 파일 truncation

    @Test("file_read — 큰 파일 잘림 (50,000자 제한)")
    func fileReadTruncation() async throws {
        let tmpDir = NSTemporaryDirectory()
        let filePath = (tmpDir as NSString).appendingPathComponent("toolexec_large_\(UUID().uuidString).txt")
        let bigContent = String(repeating: "A", count: 60_000)
        try bigContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: filePath) }

        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "file_read", arguments: ["path": .string(filePath)])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("read done"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "read big file")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        #expect(toolResult?.content?.contains("잘렸습니다") == true)
    }

    // MARK: - file_write 디렉토리 자동 생성

    @Test("file_write — 존재하지 않는 디렉토리 자동 생성")
    func fileWriteAutoCreateDir() async throws {
        let tmpDir = NSTemporaryDirectory()
        let nestedDir = (tmpDir as NSString).appendingPathComponent("toolexec_nested_\(UUID().uuidString)")
        let filePath = (nestedDir as NSString).appendingPathComponent("deep/file.txt")
        defer { try? FileManager.default.removeItem(atPath: nestedDir) }

        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "file_write", arguments: [
            "path": .string(filePath),
            "content": .string("nested content")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("write done"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "write")]
        )

        // 파일이 생성되었는지 확인
        let content = try? String(contentsOfFile: filePath, encoding: .utf8)
        #expect(content == "nested content")
    }

    // MARK: - shell_exec with working_directory

    @Test("shell_exec — working_directory 지정")
    func shellExecWithWorkDir() async throws {
        try await ProcessRunner.withMock({ _, args, _, workDir in
            if args.contains(where: { $0.contains("pwd") }) {
                let dir = workDir ?? "/tmp"
                return (exitCode: 0, stdout: dir + "\n", stderr: "")
            }
            return (exitCode: 0, stdout: "", stderr: "")
        }) {
            let provider = makeMockProvider(supportsTools: true)
            let call = ToolCall(id: "c1", toolName: "shell_exec", arguments: [
                "command": .string("pwd"),
                "working_directory": .string("/tmp")
            ])
            provider.sendMessageWithToolsResults = [
                .success(.toolCalls([call])),
                .success(.text("done"))
            ]

            let agent = makeAgent()
            _ = try await ToolExecutor.smartSend(
                provider: provider, agent: agent,
                systemPrompt: "s", messages: [("user", "pwd")]
            )

            let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
            let toolResult = lastMessages.first { $0.role == "tool" }
            #expect(toolResult?.content?.contains("tmp") == true)
        }
    }

    // MARK: - shell_exec 큰 출력 truncation

    @Test("shell_exec — 큰 출력 잘림 (30,000자 제한)")
    func shellExecTruncation() async throws {
        try await ProcessRunner.withMock({ _, args, _, _ in
            if args.contains(where: { $0.contains("python3") }) {
                // 40000자 'A' 출력 시뮬레이션
                return (exitCode: 0, stdout: String(repeating: "A", count: 40000) + "\n", stderr: "")
            }
            return (exitCode: 0, stdout: "", stderr: "")
        }) {
            let provider = makeMockProvider(supportsTools: true)
            let call = ToolCall(id: "c1", toolName: "shell_exec", arguments: [
                "command": .string("python3 -c \"print('A' * 40000)\"")
            ])
            provider.sendMessageWithToolsResults = [
                .success(.toolCalls([call])),
                .success(.text("done"))
            ]

            let agent = makeAgent()
            _ = try await ToolExecutor.smartSend(
                provider: provider, agent: agent,
                systemPrompt: "s", messages: [("user", "big output")]
            )

            let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
            let toolResult = lastMessages.first { $0.role == "tool" }
            #expect(toolResult?.content?.contains("잘렸습니다") == true)
        }
    }

    // MARK: - smartSend system 역할 변환

    @Test("smartSend — system 역할이 ConversationMessage.system으로 변환")
    func smartSendSystemRoleConversion() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [.success(.text("ok"))]
        let agent = makeAgent()

        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "sys",
            messages: [("system", "context"), ("user", "hello")]
        )

        let args = provider.lastSendMessageWithToolsArgs
        #expect(args?.messages[0].role == "system")
        #expect(args?.messages[1].role == "user")
    }

    // MARK: - isPathAllowed 추가 케이스

    @Test("isPathAllowed — 틸드 경로 확장")
    func pathAllowedTildeExpansion() {
        #expect(ToolExecutor.isPathAllowed("~/Documents/test.txt") == true)
        #expect(ToolExecutor.isPathAllowed("~/Desktop") == true)
    }

    @Test("isPathAllowed — /var/folders 허용")
    func pathAllowedVarFolders() {
        #expect(ToolExecutor.isPathAllowed("/var/folders/xx/test") == true)
    }

    // MARK: - smartSend ConversationMessage — nil content 메시지

    @Test("smartSend ConversationMessage — nil content 메시지 필터링")
    func smartSendConvMessageNilContent() async throws {
        let provider = makeMockProvider(supportsTools: false)
        provider.sendMessageResult = .success("ok")
        let agent = makeAgent()

        let msg1 = ConversationMessage.user("hello")
        let msg2 = ConversationMessage.assistant("response")
        // tool role message에는 content가 nil일 수 있음
        let msg3 = ConversationMessage(role: "tool", content: nil, toolCalls: nil, toolCallID: "tc1", attachments: nil, isError: false)
        let messages = [msg1, msg2, msg3]

        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "sys",
            conversationMessages: messages
        )
        #expect(result == "ok")
        // nil content 메시지는 필터링되어 sendMessage에 전달되지 않아야 함
        let sentMessages = provider.lastSendMessageArgs?.messages ?? []
        #expect(sentMessages.count == 2)
    }

    // MARK: - Phase B: 경로 해석 + projectPath 허용

    @Test("resolvePath — 절대 경로는 그대로")
    func resolvePathAbsolute() {
        let result = ToolExecutor.resolvePath("/usr/local/bin/test", projectPaths: ["/tmp/project"])
        #expect(result == "/usr/local/bin/test")
    }

    @Test("resolvePath — 상대 경로를 첫 번째 projectPath 기준으로 해석")
    func resolvePathRelative() {
        let result = ToolExecutor.resolvePath("src/main.swift", projectPaths: ["/tmp/project", "/tmp/other"])
        #expect(result == "/tmp/project/src/main.swift")
    }

    @Test("resolvePath — projectPaths 비어있으면 상대 경로 그대로")
    func resolvePathNoProject() {
        let result = ToolExecutor.resolvePath("src/main.swift", projectPaths: [])
        #expect(result == "src/main.swift")
    }

    @Test("resolvePath — 틸드 경로는 그대로")
    func resolvePathTilde() {
        let result = ToolExecutor.resolvePath("~/Documents/test.txt", projectPaths: ["/tmp/project"])
        #expect(result == "~/Documents/test.txt")
    }

    @Test("isPathAllowed — projectPaths 경로 허용")
    func pathAllowedProjectPath() {
        let paths = ["/opt/my-project"]
        #expect(ToolExecutor.isPathAllowed("/opt/my-project/src/main.swift", projectPaths: paths) == true)
        #expect(ToolExecutor.isPathAllowed("/opt/my-project/Package.swift", projectPaths: paths) == true)
    }

    @Test("isPathAllowed — 복수 projectPaths 모두 허용")
    func pathAllowedMultipleProjects() {
        let paths = ["/opt/frontend", "/opt/backend"]
        #expect(ToolExecutor.isPathAllowed("/opt/frontend/src/app.ts", projectPaths: paths) == true)
        #expect(ToolExecutor.isPathAllowed("/opt/backend/src/main.swift", projectPaths: paths) == true)
        #expect(ToolExecutor.isPathAllowed("/opt/other/file.txt", projectPaths: paths) == false)
    }

    @Test("isPathAllowed — projectPaths 외부는 기존 규칙 적용")
    func pathBlockedOutsideProject() {
        let paths = ["/opt/my-project"]
        #expect(ToolExecutor.isPathAllowed("/etc/passwd", projectPaths: paths) == false)
        #expect(ToolExecutor.isPathAllowed("/opt/other-project/file.txt", projectPaths: paths) == false)
    }

    @Test("isPathAllowed — projectPaths 비어있으면 기존 동작")
    func pathAllowedNoProjectPath() {
        #expect(ToolExecutor.isPathAllowed("/tmp/test.txt", projectPaths: []) == true)
        #expect(ToolExecutor.isPathAllowed("/etc/passwd", projectPaths: []) == false)
    }

    // MARK: - Phase C-1: Jira 도구 테스트

    @Test("jira_create_subtask — Jira 미설정 시 오류")
    func jiraCreateSubtaskNotConfigured() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "jira_create_subtask", arguments: [
            "parent_key": .string("PROJ-123"),
            "summary": .string("서브태스크")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "create subtask")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        // Jira 미설정이면 에러 또는 실패 메시지
        #expect(toolResult?.content != nil)
    }

    @Test("jira_create_subtask — parent_key 누락 시 오류")
    func jiraCreateSubtaskMissingParentKey() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "jira_create_subtask", arguments: [
            "summary": .string("서브태스크")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "create")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        #expect(toolResult?.content?.contains("parent_key") == true)
    }

    @Test("jira_create_subtask — summary 누락 시 오류")
    func jiraCreateSubtaskMissingSummary() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "jira_create_subtask", arguments: [
            "parent_key": .string("PROJ-123")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "create")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        #expect(toolResult?.content?.contains("summary") == true)
    }

    @Test("jira_update_status — Jira 미설정 시 오류")
    func jiraUpdateStatusNotConfigured() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "jira_update_status", arguments: [
            "issue_key": .string("PROJ-123"),
            "status_name": .string("Done")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "update status")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        #expect(toolResult?.content != nil)
    }

    @Test("jira_update_status — issue_key 누락 시 오류")
    func jiraUpdateStatusMissingKey() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "jira_update_status", arguments: [
            "status_name": .string("Done")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "update")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        #expect(toolResult?.content?.contains("issue_key") == true)
    }

    @Test("jira_add_comment — Jira 미설정 시 오류")
    func jiraAddCommentNotConfigured() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "jira_add_comment", arguments: [
            "issue_key": .string("PROJ-123"),
            "comment": .string("테스트 코멘트")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "add comment")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        #expect(toolResult?.content != nil)
    }

    @Test("jira_add_comment — comment 누락 시 오류")
    func jiraAddCommentMissingComment() async throws {
        let provider = makeMockProvider(supportsTools: true)
        let call = ToolCall(id: "c1", toolName: "jira_add_comment", arguments: [
            "issue_key": .string("PROJ-123")
        ])
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([call])),
            .success(.text("handled"))
        ]

        let agent = makeAgent()
        _ = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "comment")]
        )

        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolResult = lastMessages.first { $0.role == "tool" }
        #expect(toolResult?.content?.contains("comment") == true)
    }

    // MARK: - suggest_agent_creation (Phase D)

    @Test("suggest_agent_creation: 방 밖 에러")
    func suggestAgentCreationNoRoom() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([ToolCall(id: "s1", toolName: "suggest_agent_creation", arguments: [
                "name": .string("Dev"), "persona": .string("개발자")
            ])])),
            .success(.text("done"))
        ]

        let agent = makeAgent()
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "create agent")],
            context: .empty
        )
        // 방 밖이므로 에러 → 다음 루프에서 텍스트 반환
        #expect(result == "done")
        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolMsg?.content?.contains("방 안에서만") == true)
    }

    @Test("suggest_agent_creation: name 누락 에러")
    func suggestAgentCreationMissingName() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([ToolCall(id: "s1", toolName: "suggest_agent_creation", arguments: [
                "persona": .string("개발자")
            ])])),
            .success(.text("done"))
        ]

        let agent = makeAgent()
        let context = ToolExecutionContext(
            roomID: UUID(), agentsByName: [:], agentListString: "",
            inviteAgent: { _ in false }
        )
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "create")],
            context: context
        )
        #expect(result == "done")
        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolMsg?.content?.contains("name") == true)
    }

    @Test("suggest_agent_creation: 이미 존재하는 이름 에러")
    func suggestAgentCreationDuplicateName() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([ToolCall(id: "s1", toolName: "suggest_agent_creation", arguments: [
                "name": .string("기존에이전트"), "persona": .string("역할")
            ])])),
            .success(.text("done"))
        ]

        let agent = makeAgent()
        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: ["기존에이전트": UUID()],
            agentListString: "- 기존에이전트",
            inviteAgent: { _ in false }
        )
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "create")],
            context: context
        )
        #expect(result == "done")
        let lastMessages = provider.lastSendMessageWithToolsArgs?.messages ?? []
        let toolMsg = lastMessages.first { $0.role == "tool" }
        #expect(toolMsg?.content?.contains("이미 존재") == true)
    }

    @Test("suggest_agent_creation: 정상 실행 성공")
    func suggestAgentCreationSuccess() async throws {
        let provider = makeMockProvider(supportsTools: true)
        provider.sendMessageWithToolsResults = [
            .success(.toolCalls([ToolCall(id: "s1", toolName: "suggest_agent_creation", arguments: [
                "name": .string("QA"), "persona": .string("QA 전문가"),
                "recommended_preset": .string("개발자"), "reason": .string("테스트 필요")
            ])])),
            .success(.text("done"))
        ]

        var receivedSuggestion: RoomAgentSuggestion?
        let agent = makeAgent()
        let context = ToolExecutionContext(
            roomID: UUID(),
            agentsByName: [:],
            agentListString: "",
            inviteAgent: { _ in false },
            suggestAgentCreation: { suggestion in
                receivedSuggestion = suggestion
                return true
            },
            currentAgentName: "분석가"
        )
        let result = try await ToolExecutor.smartSend(
            provider: provider, agent: agent,
            systemPrompt: "s", messages: [("user", "need QA")],
            context: context
        )
        #expect(result == "done")
        #expect(receivedSuggestion?.name == "QA")
        #expect(receivedSuggestion?.persona == "QA 전문가")
        #expect(receivedSuggestion?.recommendedPreset == "개발자")
        #expect(receivedSuggestion?.reason == "테스트 필요")
        #expect(receivedSuggestion?.suggestedBy == "분석가")
    }
}
