import Testing
import Foundation
@testable import DOUGLAS

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

    // MARK: - ToolRegistry

    @Test("ToolRegistry 모든 도구 존재 (코드 인텔리전스 포함)")
    func registryAllTools() {
        #expect(ToolRegistry.allTools.count == 15)
        #expect(ToolRegistry.allToolIDs.count == 15)
    }

    @Test("ToolRegistry 코드 인텔리전스 도구 등록 확인")
    func registryCodeIntelligenceTools() {
        let codeToolIDs = ["code_search", "code_symbols", "code_diagnostics", "code_outline"]
        for id in codeToolIDs {
            let tool = ToolRegistry.allTools.first { $0.id == id }
            #expect(tool != nil, "도구 \(id)가 등록되어 있어야 함")
        }
        // code_search는 pattern 필수
        let search = ToolRegistry.allTools.first { $0.id == "code_search" }
        #expect(search?.parameters.first { $0.name == "pattern" }?.required == true)
        // code_outline은 path 필수
        let outline = ToolRegistry.allTools.first { $0.id == "code_outline" }
        #expect(outline?.parameters.first { $0.name == "path" }?.required == true)
    }

    @Test("ToolRegistry invite_agent 등록 확인")
    func registryInviteAgent() {
        let tool = ToolRegistry.allTools.first { $0.id == "invite_agent" }
        #expect(tool != nil)
        #expect(tool?.parameters.first { $0.name == "agent_name" }?.required == true)
        #expect(tool?.parameters.first { $0.name == "reason" }?.required == false)
    }

    @Test("ToolRegistry list_agents 등록 확인")
    func registryListAgents() {
        let tool = ToolRegistry.allTools.first { $0.id == "list_agents" }
        #expect(tool != nil)
        #expect(tool?.parameters.isEmpty == true)
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

    // MARK: - Agent 도구 접근 테스트

    @Test("Agent resolvedToolIDs — 항상 전체 도구")
    func agentAlwaysHasAllTools() {
        let agent = Agent(name: "test", persona: "test", providerName: "Test", modelName: "test-model")
        #expect(agent.resolvedToolIDs == ToolRegistry.allToolIDs)
        #expect(agent.hasToolsEnabled == true)
    }

    @Test("Agent 하위 호환 디코딩 (레거시 JSON)")
    func agentBackwardCompat() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"old","persona":"old agent","providerName":"Test","modelName":"model","status":"idle","isMaster":false,"hasImage":false}
        """
        let data = json.data(using: .utf8)!
        let agent = try JSONDecoder().decode(Agent.self, from: data)
        #expect(agent.resolvedToolIDs == ToolRegistry.allToolIDs)
    }

    @Test("Agent Codable 라운드트립")
    func agentCodable() throws {
        let agent = Agent(name: "tooled", persona: "agent with tools", providerName: "OpenAI", modelName: "gpt-4o")
        let data = try JSONEncoder().encode(agent)
        let decoded = try JSONDecoder().decode(Agent.self, from: data)
        #expect(decoded.name == "tooled")
        #expect(decoded.resolvedToolIDs == ToolRegistry.allToolIDs)
    }

    // MARK: - Jira 도구

    @Test("Jira 도구 ID 목록에 포함")
    func jiraToolsInRegistry() {
        let ids = ToolRegistry.allToolIDs
        #expect(ids.contains("jira_create_subtask"))
        #expect(ids.contains("jira_update_status"))
        #expect(ids.contains("jira_add_comment"))
    }

    @Test("suggest_agent_creation 도구 등록 확인")
    func registrySuggestAgentCreation() {
        let tool = ToolRegistry.allTools.first { $0.id == "suggest_agent_creation" }
        #expect(tool != nil)
        #expect(tool?.parameters.first { $0.name == "name" }?.required == true)
        #expect(tool?.parameters.first { $0.name == "persona" }?.required == true)
        #expect(tool?.parameters.first { $0.name == "reason" }?.required == false)
    }

    @Test("jira_create_subtask 파라미터 정의")
    func jiraCreateSubtaskParams() {
        let tool = ToolRegistry.allTools.first { $0.id == "jira_create_subtask" }
        #expect(tool != nil)
        #expect(tool?.parameters.count == 3)
        #expect(tool?.parameters[0].name == "parent_key")
        #expect(tool?.parameters[0].required == true)
        #expect(tool?.parameters[1].name == "summary")
        #expect(tool?.parameters[1].required == true)
        #expect(tool?.parameters[2].name == "project_key")
        #expect(tool?.parameters[2].required == false)
    }

    @Test("jira_update_status 파라미터 정의")
    func jiraUpdateStatusParams() {
        let tool = ToolRegistry.allTools.first { $0.id == "jira_update_status" }
        #expect(tool != nil)
        #expect(tool?.parameters.count == 2)
        #expect(tool?.parameters[0].name == "issue_key")
        #expect(tool?.parameters[1].name == "status_name")
        #expect(tool?.parameters.allSatisfy { $0.required } == true)
    }

    @Test("jira_add_comment 파라미터 정의")
    func jiraAddCommentParams() {
        let tool = ToolRegistry.allTools.first { $0.id == "jira_add_comment" }
        #expect(tool != nil)
        #expect(tool?.parameters.count == 2)
        #expect(tool?.parameters[0].name == "issue_key")
        #expect(tool?.parameters[1].name == "comment")
        #expect(tool?.parameters.allSatisfy { $0.required } == true)
    }
}
