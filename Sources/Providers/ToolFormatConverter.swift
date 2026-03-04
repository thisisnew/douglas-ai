import Foundation

/// AgentTool을 각 프로바이더의 API 형식으로 변환
enum ToolFormatConverter {

    // MARK: - OpenAI 형식

    /// AgentTool → OpenAI tools 배열
    static func toOpenAI(_ tools: [AgentTool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.id,
                    "description": tool.description,
                    "parameters": buildJSONSchema(tool.parameters)
                ] as [String: Any]
            ] as [String: Any]
        }
    }

    /// OpenAI 응답에서 ToolCall 파싱
    static func parseOpenAIToolCalls(_ toolCallsArray: [[String: Any]]) -> [ToolCall] {
        toolCallsArray.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let function = dict["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let argsString = function["arguments"] as? String else { return nil }
            let arguments = parseArguments(from: argsString)
            return ToolCall(id: id, toolName: name, arguments: arguments)
        }
    }

    /// OpenAI tool result 메시지 빌드
    static func openAIToolResultMessage(callID: String, content: String) -> [String: Any] {
        ["role": "tool", "tool_call_id": callID, "content": content]
    }

    /// OpenAI assistant message with tool_calls 빌드
    static func openAIAssistantToolCallMessage(_ calls: [ToolCall], text: String?) -> [String: Any] {
        var msg: [String: Any] = ["role": "assistant"]
        if let text = text {
            msg["content"] = text
        } else {
            msg["content"] = NSNull()
        }
        msg["tool_calls"] = calls.map { call in
            [
                "id": call.id,
                "type": "function",
                "function": [
                    "name": call.toolName,
                    "arguments": encodeArguments(call.arguments)
                ] as [String: Any]
            ] as [String: Any]
        }
        return msg
    }

    // MARK: - Anthropic 형식

    /// AgentTool → Anthropic tools 배열
    static func toAnthropic(_ tools: [AgentTool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "name": tool.id,
                "description": tool.description,
                "input_schema": buildJSONSchema(tool.parameters)
            ] as [String: Any]
        }
    }

    /// Anthropic content 블록에서 ToolCall 파싱
    static func parseAnthropicToolUse(_ contentBlocks: [[String: Any]]) -> (text: String?, toolCalls: [ToolCall]) {
        var textParts: [String] = []
        var toolCalls: [ToolCall] = []

        for block in contentBlocks {
            guard let type = block["type"] as? String else { continue }
            if type == "text", let text = block["text"] as? String {
                textParts.append(text)
            } else if type == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String {
                let input = block["input"] as? [String: Any] ?? [:]
                let arguments = convertToToolArguments(input)
                toolCalls.append(ToolCall(id: id, toolName: name, arguments: arguments))
            }
        }

        let text = textParts.isEmpty ? nil : textParts.joined()
        return (text: text, toolCalls: toolCalls)
    }

    /// Anthropic tool_result content block 빌드
    static func anthropicToolResultBlock(callID: String, content: String, isError: Bool) -> [String: Any] {
        var block: [String: Any] = [
            "type": "tool_result",
            "tool_use_id": callID,
            "content": content
        ]
        if isError { block["is_error"] = true }
        return block
    }

    // MARK: - Google 형식

    /// AgentTool → Google function_declarations 형식
    static func toGoogle(_ tools: [AgentTool]) -> [[String: Any]] {
        [
            [
                "function_declarations": tools.map { tool in
                    [
                        "name": tool.id,
                        "description": tool.description,
                        "parameters": buildJSONSchema(tool.parameters)
                    ] as [String: Any]
                }
            ]
        ]
    }

    /// Google parts에서 functionCall 파싱
    static func parseGoogleFunctionCalls(_ parts: [[String: Any]]) -> (text: String?, toolCalls: [ToolCall]) {
        var textParts: [String] = []
        var toolCalls: [ToolCall] = []

        for part in parts {
            if let text = part["text"] as? String {
                textParts.append(text)
            } else if let funcCall = part["functionCall"] as? [String: Any],
                      let name = funcCall["name"] as? String {
                let args = funcCall["args"] as? [String: Any] ?? [:]
                let arguments = convertToToolArguments(args)
                // Google은 tool call ID가 없으므로 생성
                let id = "google_\(name)_\(UUID().uuidString.prefix(8))"
                toolCalls.append(ToolCall(id: id, toolName: name, arguments: arguments))
            }
        }

        let text = textParts.isEmpty ? nil : textParts.joined()
        return (text: text, toolCalls: toolCalls)
    }

    /// Google functionResponse part 빌드
    static func googleFunctionResponsePart(name: String, content: String) -> [String: Any] {
        [
            "functionResponse": [
                "name": name,
                "response": ["content": content]
            ]
        ]
    }

    // MARK: - 첨부 파일 메시지 빌드 (이미지 + 문서)

    /// Anthropic 형식: 이미지 → image 블록, PDF → document 블록, 텍스트 → text 블록
    static func anthropicContentBlocks(text: String?, attachments: [FileAttachment]) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        for attachment in attachments {
            if attachment.isImage {
                guard let base64 = try? attachment.loadBase64() else { continue }
                blocks.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": attachment.mimeType,
                        "data": base64
                    ] as [String: Any]
                ])
            } else if attachment.mimeType == "application/pdf" {
                guard let base64 = try? attachment.loadBase64() else { continue }
                blocks.append([
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": "application/pdf",
                        "data": base64
                    ] as [String: Any]
                ])
            } else if let textContent = attachment.loadTextContent() {
                let label = attachment.displayName
                blocks.append(["type": "text", "text": "[\(label)]\n```\n\(textContent)\n```"])
            }
        }
        if let text = text, !text.isEmpty {
            blocks.append(["type": "text", "text": text])
        }
        return blocks
    }

    /// OpenAI 형식: 이미지 → image_url, PDF → data URI, 텍스트 → text 블록
    static func openAIContentArray(text: String?, attachments: [FileAttachment]) -> [[String: Any]] {
        var parts: [[String: Any]] = []
        for attachment in attachments {
            if attachment.isImage {
                guard let base64 = try? attachment.loadBase64() else { continue }
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(attachment.mimeType);base64,\(base64)"]
                ])
            } else if attachment.mimeType == "application/pdf" {
                guard let base64 = try? attachment.loadBase64() else { continue }
                parts.append([
                    "type": "file",
                    "file": [
                        "filename": attachment.displayName,
                        "file_data": "data:application/pdf;base64,\(base64)"
                    ]
                ])
            } else if let textContent = attachment.loadTextContent() {
                let label = attachment.displayName
                parts.append(["type": "text", "text": "[\(label)]\n```\n\(textContent)\n```"])
            }
        }
        if let text = text, !text.isEmpty {
            parts.append(["type": "text", "text": text])
        }
        return parts
    }

    /// Google 형식: 이미지/PDF → inlineData, 텍스트 → text 파트
    static func googleParts(text: String?, attachments: [FileAttachment]) -> [[String: Any]] {
        var parts: [[String: Any]] = []
        for attachment in attachments {
            if attachment.isImage || attachment.mimeType == "application/pdf" {
                guard let base64 = try? attachment.loadBase64() else { continue }
                parts.append([
                    "inlineData": [
                        "mimeType": attachment.mimeType,
                        "data": base64
                    ] as [String: Any]
                ])
            } else if let textContent = attachment.loadTextContent() {
                let label = attachment.displayName
                parts.append(["text": "[\(label)]\n```\n\(textContent)\n```"])
            }
        }
        if let text = text, !text.isEmpty {
            parts.append(["text": text])
        }
        return parts
    }

    // MARK: - 공통 헬퍼

    /// ToolParameter 배열을 JSON Schema로 변환
    static func buildJSONSchema(_ parameters: [AgentTool.ToolParameter]) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for param in parameters {
            var prop: [String: Any] = [
                "type": param.type.rawValue,
                "description": param.description
            ]
            if let enums = param.enumValues {
                prop["enum"] = enums
            }
            properties[param.name] = prop
            if param.required {
                required.append(param.name)
            }
        }

        var schema: [String: Any] = [
            "type": "object",
            "properties": properties
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    /// JSON 문자열에서 arguments 파싱
    static func parseArguments(from jsonString: String) -> [String: ToolArgumentValue] {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return convertToToolArguments(dict)
    }

    /// [String: Any] → [String: ToolArgumentValue] 변환
    static func convertToToolArguments(_ dict: [String: Any]) -> [String: ToolArgumentValue] {
        var result: [String: ToolArgumentValue] = [:]
        for (key, value) in dict {
            if let str = value as? String {
                result[key] = .string(str)
            } else if let num = value as? NSNumber, CFGetTypeID(num) == CFBooleanGetTypeID() {
                // Bool을 Int보다 먼저 판별 — NSNumber 브릿지에서 true/false가 Int 1/0으로 캐스팅되는 것 방지
                result[key] = .boolean(num.boolValue)
            } else if let num = value as? Int {
                result[key] = .integer(num)
            } else if let arr = value as? [String] {
                result[key] = .array(arr)
            } else if let anyStr = value as? CustomStringConvertible {
                result[key] = .string(anyStr.description)
            }
        }
        return result
    }

    /// [String: ToolArgumentValue] → JSON 문자열
    static func encodeArguments(_ arguments: [String: ToolArgumentValue]) -> String {
        var dict: [String: Any] = [:]
        for (key, value) in arguments {
            switch value {
            case .string(let s):  dict[key] = s
            case .integer(let i): dict[key] = i
            case .boolean(let b): dict[key] = b
            case .array(let a):   dict[key] = a
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
