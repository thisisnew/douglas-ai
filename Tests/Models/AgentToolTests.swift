import Testing
import Foundation
@testable import AgentManagerLib

// MARK: - AgentTool 테스트

@Suite("AgentTool Model Tests")
struct AgentToolTests {

    // MARK: - AgentTool Codable

    @Test("AgentTool Codable 라운드트립")
    func agentToolCodable() throws {
        let tool = AgentTool(
            id: "test_tool",
            name: "테스트 도구",
            description: "A test tool",
            parameters: [
                .init(name: "input", type: .string, description: "Input text", required: true, enumValues: nil),
                .init(name: "count", type: .integer, description: "Count", required: false, enumValues: nil)
            ]
        )
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(AgentTool.self, from: data)
        #expect(decoded.id == "test_tool")
        #expect(decoded.name == "테스트 도구")
        #expect(decoded.parameters.count == 2)
        #expect(decoded.parameters[0].type == .string)
        #expect(decoded.parameters[0].required == true)
        #expect(decoded.parameters[1].type == .integer)
        #expect(decoded.parameters[1].required == false)
    }

    @Test("AgentTool.ParameterType 모든 케이스")
    func parameterTypes() {
        #expect(AgentTool.ParameterType.string.rawValue == "string")
        #expect(AgentTool.ParameterType.integer.rawValue == "integer")
        #expect(AgentTool.ParameterType.boolean.rawValue == "boolean")
        #expect(AgentTool.ParameterType.array.rawValue == "array")
    }

    @Test("AgentTool enum 파라미터")
    func enumParameter() throws {
        let tool = AgentTool(
            id: "format",
            name: "포맷터",
            description: "Format text",
            parameters: [
                .init(name: "style", type: .string, description: "Style", required: true, enumValues: ["bold", "italic", "plain"])
            ]
        )
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(AgentTool.self, from: data)
        #expect(decoded.parameters[0].enumValues == ["bold", "italic", "plain"])
    }

    // MARK: - ToolCall Codable

    @Test("ToolCall Codable 라운드트립")
    func toolCallCodable() throws {
        let call = ToolCall(
            id: "call_123",
            toolName: "file_read",
            arguments: ["path": .string("/tmp/test.txt")]
        )
        let data = try JSONEncoder().encode(call)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        #expect(decoded.id == "call_123")
        #expect(decoded.toolName == "file_read")
        #expect(decoded.arguments["path"]?.stringValue == "/tmp/test.txt")
    }

    // MARK: - ToolArgumentValue

    @Test("ToolArgumentValue 문자열")
    func argumentString() throws {
        let val = ToolArgumentValue.string("hello")
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(ToolArgumentValue.self, from: data)
        #expect(decoded == .string("hello"))
        #expect(decoded.stringValue == "hello")
    }

    @Test("ToolArgumentValue 정수")
    func argumentInteger() throws {
        let val = ToolArgumentValue.integer(42)
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(ToolArgumentValue.self, from: data)
        #expect(decoded == .integer(42))
        #expect(decoded.stringValue == nil)
    }

    @Test("ToolArgumentValue 불리언")
    func argumentBoolean() throws {
        let val = ToolArgumentValue.boolean(true)
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(ToolArgumentValue.self, from: data)
        #expect(decoded == .boolean(true))
    }

    @Test("ToolArgumentValue 배열")
    func argumentArray() throws {
        let val = ToolArgumentValue.array(["a", "b", "c"])
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(ToolArgumentValue.self, from: data)
        #expect(decoded == .array(["a", "b", "c"]))
    }

    // MARK: - ToolResult

    @Test("ToolResult Codable")
    func toolResultCodable() throws {
        let result = ToolResult(callID: "call_abc", content: "file contents here", isError: false)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ToolResult.self, from: data)
        #expect(decoded.callID == "call_abc")
        #expect(decoded.content == "file contents here")
        #expect(decoded.isError == false)
    }

    @Test("ToolResult 오류 상태")
    func toolResultError() throws {
        let result = ToolResult(callID: "call_err", content: "file not found", isError: true)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ToolResult.self, from: data)
        #expect(decoded.isError == true)
    }

    // MARK: - CapabilityPreset

    @Test("CapabilityPreset allCases 존재")
    func presetAllCases() {
        #expect(CapabilityPreset.allCases.count == 6)
    }

    @Test("CapabilityPreset.none은 빈 도구 목록")
    func presetNone() {
        #expect(CapabilityPreset.none.includedToolIDs.isEmpty)
    }

    @Test("CapabilityPreset.developer는 파일+셸 도구")
    func presetDeveloper() {
        let ids = CapabilityPreset.developer.includedToolIDs
        #expect(ids.contains("file_read"))
        #expect(ids.contains("file_write"))
        #expect(ids.contains("shell_exec"))
        #expect(!ids.contains("web_search"))
    }

    @Test("CapabilityPreset.researcher는 웹 검색")
    func presetResearcher() {
        let ids = CapabilityPreset.researcher.includedToolIDs
        #expect(ids == ["web_search"])
    }

    @Test("CapabilityPreset.fullAccess는 전체 도구")
    func presetFullAccess() {
        let ids = CapabilityPreset.fullAccess.includedToolIDs
        #expect(ids == ToolRegistry.allToolIDs)
    }

    @Test("CapabilityPreset.custom은 빈 도구 (enabledToolIDs로 결정)")
    func presetCustom() {
        #expect(CapabilityPreset.custom.includedToolIDs.isEmpty)
    }

    @Test("CapabilityPreset Codable")
    func presetCodable() throws {
        let preset = CapabilityPreset.developer
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(CapabilityPreset.self, from: data)
        #expect(decoded == .developer)
    }

    // MARK: - ToolRegistry

    @Test("ToolRegistry 모든 도구 존재")
    func registryAllTools() {
        #expect(ToolRegistry.allTools.count == 4)
        #expect(ToolRegistry.allToolIDs.count == 4)
    }

    @Test("ToolRegistry 필터링")
    func registryFilter() {
        let tools = ToolRegistry.tools(for: ["file_read", "shell_exec"])
        #expect(tools.count == 2)
        #expect(tools.map { $0.id }.contains("file_read"))
        #expect(tools.map { $0.id }.contains("shell_exec"))
    }

    @Test("ToolRegistry 빈 필터")
    func registryEmptyFilter() {
        let tools = ToolRegistry.tools(for: [])
        #expect(tools.isEmpty)
    }

    @Test("ToolRegistry 존재하지 않는 ID 필터")
    func registryNonexistentFilter() {
        let tools = ToolRegistry.tools(for: ["nonexistent"])
        #expect(tools.isEmpty)
    }

    // MARK: - ConversationMessage 팩토리

    @Test("ConversationMessage.user")
    func convMsgUser() {
        let msg = ConversationMessage.user("hello")
        #expect(msg.role == "user")
        #expect(msg.content == "hello")
        #expect(msg.toolCalls == nil)
        #expect(msg.toolCallID == nil)
    }

    @Test("ConversationMessage.assistant")
    func convMsgAssistant() {
        let msg = ConversationMessage.assistant("response")
        #expect(msg.role == "assistant")
        #expect(msg.content == "response")
    }

    @Test("ConversationMessage.system")
    func convMsgSystem() {
        let msg = ConversationMessage.system("instruction")
        #expect(msg.role == "system")
        #expect(msg.content == "instruction")
    }

    @Test("ConversationMessage.assistantToolCalls")
    func convMsgToolCalls() {
        let calls = [ToolCall(id: "c1", toolName: "file_read", arguments: ["path": .string("/tmp")])]
        let msg = ConversationMessage.assistantToolCalls(calls, text: "let me read")
        #expect(msg.role == "assistant")
        #expect(msg.content == "let me read")
        #expect(msg.toolCalls?.count == 1)
    }

    @Test("ConversationMessage.toolResult")
    func convMsgToolResult() {
        let msg = ConversationMessage.toolResult(callID: "c1", content: "file data")
        #expect(msg.role == "tool")
        #expect(msg.content == "file data")
        #expect(msg.toolCallID == "c1")
    }

    @Test("ConversationMessage.toolResult 오류")
    func convMsgToolResultError() {
        let msg = ConversationMessage.toolResult(callID: "c1", content: "not found", isError: true)
        #expect(msg.content?.contains("[오류]") == true)
    }

    // MARK: - Agent Tool 필드 테스트

    @Test("Agent resolvedToolIDs - 프리셋 없으면 빈 배열")
    func agentNoPreset() {
        let agent = Agent(name: "test", persona: "test", providerName: "Test", modelName: "test-model")
        #expect(agent.resolvedToolIDs.isEmpty)
        #expect(agent.hasToolsEnabled == false)
    }

    @Test("Agent resolvedToolIDs - developer 프리셋")
    func agentDeveloperPreset() {
        let agent = Agent(name: "dev", persona: "dev", providerName: "Test", modelName: "test", capabilityPreset: .developer)
        #expect(agent.resolvedToolIDs.contains("file_read"))
        #expect(agent.hasToolsEnabled == true)
    }

    @Test("Agent resolvedToolIDs - custom 프리셋 + enabledToolIDs")
    func agentCustomPreset() {
        let agent = Agent(
            name: "custom", persona: "custom", providerName: "Test", modelName: "test",
            capabilityPreset: .custom, enabledToolIDs: ["shell_exec"]
        )
        #expect(agent.resolvedToolIDs == ["shell_exec"])
    }

    @Test("Agent 하위 호환 디코딩 (도구 필드 없는 JSON)")
    func agentBackwardCompat() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"old","persona":"old agent","providerName":"Test","modelName":"model","status":"idle","isMaster":false,"isDevAgent":false,"hasImage":false}
        """
        let data = json.data(using: .utf8)!
        let agent = try JSONDecoder().decode(Agent.self, from: data)
        #expect(agent.capabilityPreset == nil)
        #expect(agent.enabledToolIDs == nil)
        #expect(agent.resolvedToolIDs.isEmpty)
    }

    @Test("Agent 도구 필드 Codable 라운드트립")
    func agentToolFieldsCodable() throws {
        let agent = Agent(
            name: "tooled", persona: "agent with tools", providerName: "OpenAI", modelName: "gpt-4o",
            capabilityPreset: .developer, enabledToolIDs: nil
        )
        let data = try JSONEncoder().encode(agent)
        let decoded = try JSONDecoder().decode(Agent.self, from: data)
        #expect(decoded.capabilityPreset == .developer)
        #expect(decoded.enabledToolIDs == nil)
        #expect(decoded.resolvedToolIDs == CapabilityPreset.developer.includedToolIDs)
    }
}
