import Testing
import Foundation
@testable import DOUGLAS

@Suite("ToolExecutor smartSend — CLI 도구 제어 Tests")
struct ToolExecutorSmartSendTests {

    // MARK: - 도우미

    private func makeClaudeProvider() -> ClaudeCodeProvider {
        let config = ProviderConfig(
            id: UUID(),
            name: "claude-test",
            type: .claudeCode,
            baseURL: "/usr/bin/echo",  // 실행 가능한 경로 (mock에서 실행 안 함)
            authMethod: .none,
            isBuiltIn: true
        )
        return ClaudeCodeProvider(config: config)
    }

    private func makeAgent() -> Agent {
        Agent(
            name: "test-agent",
            persona: "test persona",
            providerName: "claude-test",
            modelName: "test-model"
        )
    }

    // MARK: - P0: useTools: false → CLI 도구 비활성화

    @Test("smartSend useTools:false — ClaudeCodeProvider CLI에 --allowedTools 전달 안 함")
    func smartSend_useToolsFalse_disablesCLITools() async throws {
        let provider = makeClaudeProvider()
        let agent = makeAgent()
        var capturedArgs: [String] = []

        try await ProcessRunner.withMock({ _, args, _, _ in
            capturedArgs = args
            let json = #"{"type":"result","subtype":"success","result":"mock response","is_error":false,"session_id":"test"}"#
            return (0, json, "")
        }) {
            _ = try await ToolExecutor.smartSend(
                provider: provider, agent: agent,
                systemPrompt: "sys",
                messages: [("user", "계획을 세워줘")],
                useTools: false
            )
        }

        // useTools: false일 때 --allowedTools가 없어야 함
        #expect(!capturedArgs.contains("--allowedTools"),
                "useTools: false에서는 CLI 도구가 비활성화되어야 함. args: \(capturedArgs)")
    }

    @Test("smartSend useTools:true (기본값) — ClaudeCodeProvider CLI에 --allowedTools 전달")
    func smartSend_useToolsTrue_enablesCLITools() async throws {
        let provider = makeClaudeProvider()
        let agent = makeAgent()
        var capturedArgs: [String] = []

        // useTools: true이지만 provider.supportsToolCalling = false이므로
        // guard에서 sendMessage 경로로 빠짐 (기본 도구 활성화)
        try await ProcessRunner.withMock({ _, args, _, _ in
            capturedArgs = args
            let json = #"{"type":"result","subtype":"success","result":"mock response","is_error":false,"session_id":"test"}"#
            return (0, json, "")
        }) {
            _ = try await ToolExecutor.smartSend(
                provider: provider, agent: agent,
                systemPrompt: "sys",
                messages: [("user", "코드 수정해줘")],
                useTools: true
            )
        }

        // useTools: true일 때 --allowedTools가 있어야 함
        #expect(capturedArgs.contains("--allowedTools"),
                "useTools: true에서는 CLI 도구가 활성화되어야 함. args: \(capturedArgs)")
    }

    @Test("sendMessage disableTools:true — CLI 인자에 --allowedTools 없음")
    func sendMessage_disableTools_noAllowedTools() async throws {
        let provider = makeClaudeProvider()
        var capturedArgs: [String] = []

        try await ProcessRunner.withMock({ _, args, _, _ in
            capturedArgs = args
            let json = #"{"type":"result","subtype":"success","result":"ok","is_error":false,"session_id":"test"}"#
            return (0, json, "")
        }) {
            _ = try await provider.sendMessage(
                model: "test-model",
                systemPrompt: "sys",
                messages: [("user", "분석해줘")],
                workingDirectory: nil,
                disableTools: true
            )
        }

        #expect(!capturedArgs.contains("--allowedTools"),
                "disableTools: true이면 --allowedTools가 없어야 함")
        // --system-prompt 사용 (--append-system-prompt가 아닌)
        #expect(capturedArgs.contains("--system-prompt"),
                "disableTools: true이면 --system-prompt 사용")
    }

    @Test("sendMessage disableTools:false (기본값) — CLI 인자에 --allowedTools 포함")
    func sendMessage_disableToolsFalse_hasAllowedTools() async throws {
        let provider = makeClaudeProvider()
        var capturedArgs: [String] = []

        try await ProcessRunner.withMock({ _, args, _, _ in
            capturedArgs = args
            let json = #"{"type":"result","subtype":"success","result":"ok","is_error":false,"session_id":"test"}"#
            return (0, json, "")
        }) {
            _ = try await provider.sendMessage(
                model: "test-model",
                systemPrompt: "sys",
                messages: [("user", "코드 수정")],
                workingDirectory: nil,
                disableTools: false
            )
        }

        #expect(capturedArgs.contains("--allowedTools"),
                "disableTools: false이면 --allowedTools가 있어야 함")
        #expect(capturedArgs.contains("--append-system-prompt"),
                "disableTools: false이면 --append-system-prompt 사용")
    }
}
