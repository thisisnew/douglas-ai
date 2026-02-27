import Testing
import Foundation
@testable import DOUGLASLib

@Suite("ToolFormatConverter Tests")
struct ToolFormatConverterTests {

    private var sampleTool: AgentTool {
        AgentTool(
            id: "file_read",
            name: "파일 읽기",
            description: "Read file contents",
            parameters: [
                .init(name: "path", type: .string, description: "File path", required: true, enumValues: nil)
            ]
        )
    }

    // MARK: - OpenAI 형식

    @Test("toOpenAI 기본 구조")
    func openAIFormat() {
        let result = ToolFormatConverter.toOpenAI([sampleTool])
        #expect(result.count == 1)
        let tool = result[0]
        #expect(tool["type"] as? String == "function")
        let function = tool["function"] as? [String: Any]
        #expect(function?["name"] as? String == "file_read")
        #expect(function?["description"] as? String == "Read file contents")
    }

    @Test("toOpenAI JSON Schema 구조")
    func openAISchema() {
        let result = ToolFormatConverter.toOpenAI([sampleTool])
        let function = result[0]["function"] as? [String: Any]
        let params = function?["parameters"] as? [String: Any]
        #expect(params?["type"] as? String == "object")
        let properties = params?["properties"] as? [String: Any]
        #expect(properties?["path"] != nil)
        let required = params?["required"] as? [String]
        #expect(required == ["path"])
    }

    @Test("toOpenAI 빈 도구 배열")
    func openAIEmptyTools() {
        let result = ToolFormatConverter.toOpenAI([])
        #expect(result.isEmpty)
    }

    @Test("parseOpenAIToolCalls 파싱")
    func openAIParseToolCalls() {
        let raw: [[String: Any]] = [
            [
                "id": "call_abc",
                "type": "function",
                "function": [
                    "name": "file_read",
                    "arguments": "{\"path\":\"/tmp/test.txt\"}"
                ] as [String: Any]
            ]
        ]
        let calls = ToolFormatConverter.parseOpenAIToolCalls(raw)
        #expect(calls.count == 1)
        #expect(calls[0].id == "call_abc")
        #expect(calls[0].toolName == "file_read")
        #expect(calls[0].arguments["path"]?.stringValue == "/tmp/test.txt")
    }

    @Test("parseOpenAIToolCalls 잘못된 JSON")
    func openAIParseInvalid() {
        let raw: [[String: Any]] = [
            ["id": "call_x", "function": ["name": "test", "arguments": "not json"] as [String: Any]]
        ]
        let calls = ToolFormatConverter.parseOpenAIToolCalls(raw)
        #expect(calls.count == 1)
        #expect(calls[0].arguments.isEmpty) // 파싱 실패 시 빈 arguments
    }

    @Test("openAIAssistantToolCallMessage 빌드")
    func openAIAssistantMsg() {
        let call = ToolCall(id: "c1", toolName: "file_read", arguments: ["path": .string("/tmp")])
        let msg = ToolFormatConverter.openAIAssistantToolCallMessage([call], text: nil)
        #expect(msg["role"] as? String == "assistant")
        let toolCalls = msg["tool_calls"] as? [[String: Any]]
        #expect(toolCalls?.count == 1)
    }

    @Test("openAIToolResultMessage 빌드")
    func openAIResultMsg() {
        let msg = ToolFormatConverter.openAIToolResultMessage(callID: "c1", content: "result data")
        #expect(msg["role"] as? String == "tool")
        #expect(msg["tool_call_id"] as? String == "c1")
        #expect(msg["content"] as? String == "result data")
    }

    // MARK: - Anthropic 형식

    @Test("toAnthropic 기본 구조")
    func anthropicFormat() {
        let result = ToolFormatConverter.toAnthropic([sampleTool])
        #expect(result.count == 1)
        let tool = result[0]
        #expect(tool["name"] as? String == "file_read")
        #expect(tool["description"] as? String == "Read file contents")
        let schema = tool["input_schema"] as? [String: Any]
        #expect(schema?["type"] as? String == "object")
    }

    @Test("parseAnthropicToolUse text + tool_use 혼합")
    func anthropicParseMixed() {
        let blocks: [[String: Any]] = [
            ["type": "text", "text": "Let me read that file."],
            ["type": "tool_use", "id": "toolu_01", "name": "file_read", "input": ["path": "/tmp/test"] as [String: Any]]
        ]
        let (text, calls) = ToolFormatConverter.parseAnthropicToolUse(blocks)
        #expect(text == "Let me read that file.")
        #expect(calls.count == 1)
        #expect(calls[0].id == "toolu_01")
        #expect(calls[0].toolName == "file_read")
    }

    @Test("parseAnthropicToolUse 텍스트만")
    func anthropicParseTextOnly() {
        let blocks: [[String: Any]] = [
            ["type": "text", "text": "Just text."]
        ]
        let (text, calls) = ToolFormatConverter.parseAnthropicToolUse(blocks)
        #expect(text == "Just text.")
        #expect(calls.isEmpty)
    }

    @Test("anthropicToolResultBlock 빌드")
    func anthropicResultBlock() {
        let block = ToolFormatConverter.anthropicToolResultBlock(callID: "toolu_01", content: "data", isError: false)
        #expect(block["type"] as? String == "tool_result")
        #expect(block["tool_use_id"] as? String == "toolu_01")
        #expect(block["is_error"] == nil)
    }

    @Test("anthropicToolResultBlock 오류")
    func anthropicResultBlockError() {
        let block = ToolFormatConverter.anthropicToolResultBlock(callID: "t1", content: "err", isError: true)
        #expect(block["is_error"] as? Bool == true)
    }

    // MARK: - Google 형식

    @Test("toGoogle function_declarations 구조")
    func googleFormat() {
        let result = ToolFormatConverter.toGoogle([sampleTool])
        #expect(result.count == 1)
        let declarations = result[0]["function_declarations"] as? [[String: Any]]
        #expect(declarations?.count == 1)
        #expect(declarations?[0]["name"] as? String == "file_read")
    }

    @Test("parseGoogleFunctionCalls 파싱")
    func googleParseFunctionCalls() {
        let parts: [[String: Any]] = [
            ["functionCall": ["name": "file_read", "args": ["path": "/tmp/test"] as [String: Any]] as [String: Any]]
        ]
        let (text, calls) = ToolFormatConverter.parseGoogleFunctionCalls(parts)
        #expect(text == nil)
        #expect(calls.count == 1)
        #expect(calls[0].toolName == "file_read")
        #expect(calls[0].arguments["path"]?.stringValue == "/tmp/test")
    }

    @Test("parseGoogleFunctionCalls text + functionCall 혼합")
    func googleParseMixed() {
        let parts: [[String: Any]] = [
            ["text": "Reading file..."],
            ["functionCall": ["name": "file_read", "args": ["path": "/x"] as [String: Any]] as [String: Any]]
        ]
        let (text, calls) = ToolFormatConverter.parseGoogleFunctionCalls(parts)
        #expect(text == "Reading file...")
        #expect(calls.count == 1)
    }

    @Test("googleFunctionResponsePart 빌드")
    func googleResponsePart() {
        let part = ToolFormatConverter.googleFunctionResponsePart(name: "file_read", content: "data")
        let response = part["functionResponse"] as? [String: Any]
        #expect(response?["name"] as? String == "file_read")
        let inner = response?["response"] as? [String: Any]
        #expect(inner?["content"] as? String == "data")
    }

    // MARK: - 공통 헬퍼

    @Test("buildJSONSchema 여러 파라미터")
    func jsonSchema() {
        let params: [AgentTool.ToolParameter] = [
            .init(name: "a", type: .string, description: "A", required: true, enumValues: nil),
            .init(name: "b", type: .integer, description: "B", required: false, enumValues: nil)
        ]
        let schema = ToolFormatConverter.buildJSONSchema(params)
        let properties = schema["properties"] as? [String: Any]
        #expect(properties?.count == 2)
        let required = schema["required"] as? [String]
        #expect(required == ["a"])
    }

    @Test("parseArguments JSON 문자열")
    func parseArgs() {
        let args = ToolFormatConverter.parseArguments(from: "{\"key\":\"value\",\"num\":42}")
        #expect(args["key"]?.stringValue == "value")
        #expect(args["num"] == .integer(42))
    }

    @Test("parseArguments 잘못된 JSON")
    func parseArgsInvalid() {
        let args = ToolFormatConverter.parseArguments(from: "not json")
        #expect(args.isEmpty)
    }

    @Test("encodeArguments → JSON 문자열")
    func encodeArgs() {
        let json = ToolFormatConverter.encodeArguments(["path": .string("/tmp")])
        #expect(json.contains("path"))
        #expect(json.contains("/tmp"))
    }

    @Test("convertToToolArguments 다양한 타입")
    func convertArgs() {
        let dict: [String: Any] = [
            "str": "hello",
            "num": 42,
            "arr": ["a", "b"]
        ]
        let result = ToolFormatConverter.convertToToolArguments(dict)
        #expect(result["str"] == .string("hello"))
        #expect(result["num"] == .integer(42))
        #expect(result["arr"] == .array(["a", "b"]))
    }
}
