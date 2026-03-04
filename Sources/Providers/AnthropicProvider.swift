import Foundation
import os.log

class AnthropicProvider: AIProvider {
    private static let logger = Logger(subsystem: "com.agentmanager.app", category: "Anthropic")
    let config: ProviderConfig
    let session: URLSession

    init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetchModels() async throws -> [String] {
        return ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"]
    }

    func sendMessage(model: String, systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/v1/messages") else {
            throw AIProviderError.invalidURL
        }
        let apiMessages = messages.map { ["role": $0.role, "content": $0.content] }
        var body: [String: Any] = ["model": model, "max_tokens": 4096, "messages": apiMessages]
        if !systemPrompt.isEmpty { body["system"] = systemPrompt }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        struct Resp: Decodable {
            struct Content: Decodable { let text: String? }
            let content: [Content]?
            let error: ErrBody?
            struct ErrBody: Decodable { let message: String }
        }
        let result = try JSONDecoder().decode(Resp.self, from: data)
        if let error = result.error { throw AIProviderError.apiError(error.message) }
        let textContent = result.content?.compactMap { $0.text }.joined()
        if textContent == nil || textContent?.isEmpty == true {
            Self.logger.warning("Anthropic returned empty content for model \(model)")
        }
        return textContent ?? ""
    }

    // MARK: - 스트리밍

    var supportsStreaming: Bool { true }

    func sendMessageStreaming(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/v1/messages") else {
            throw AIProviderError.invalidURL
        }
        let apiMessages = messages.map { ["role": $0.role, "content": $0.content] }
        var body: [String: Any] = [
            "model": model, "max_tokens": 4096,
            "messages": apiMessages, "stream": true
        ]
        if !systemPrompt.isEmpty { body["system"] = systemPrompt }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        applyAuth(to: &request)

        let (bytes, response) = try await session.bytes(for: request)
        try validateHTTPResponse(response)

        return try await SSEParser.consume(bytes: bytes, extractChunk: { payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String else { return nil }
            return text
        }, onChunk: onChunk)
    }

    // MARK: - Tool Use 지원

    var supportsToolCalling: Bool { true }

    func sendMessageWithTools(
        model: String,
        systemPrompt: String,
        messages: [ConversationMessage],
        tools: [AgentTool]
    ) async throws -> AIResponseContent {
        guard let url = URL(string: "\(config.baseURL)/v1/messages") else {
            throw AIProviderError.invalidURL
        }

        // Anthropic 메시지 빌드
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                // assistant의 tool_use 블록
                var contentBlocks: [[String: Any]] = []
                if let text = msg.content, !text.isEmpty {
                    contentBlocks.append(["type": "text", "text": text])
                }
                for call in toolCalls {
                    var inputDict: [String: Any] = [:]
                    for (k, v) in call.arguments {
                        switch v {
                        case .string(let s):  inputDict[k] = s
                        case .integer(let i): inputDict[k] = i
                        case .boolean(let b): inputDict[k] = b
                        case .array(let a):   inputDict[k] = a
                        }
                    }
                    contentBlocks.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.toolName,
                        "input": inputDict
                    ] as [String: Any])
                }
                apiMessages.append(["role": "assistant", "content": contentBlocks])
            } else if msg.role == "tool", let callID = msg.toolCallID {
                // tool_result는 user role로 전송 (Anthropic 규칙)
                let content = msg.content ?? ""
                let isError = msg.isError
                let resultBlock = ToolFormatConverter.anthropicToolResultBlock(
                    callID: callID, content: content, isError: isError
                )
                apiMessages.append(["role": "user", "content": [resultBlock]])
            } else if let attachments = msg.attachments, !attachments.isEmpty {
                // 이미지 첨부 메시지 → content blocks
                let blocks = ToolFormatConverter.anthropicContentBlocks(text: msg.content, attachments: attachments)
                apiMessages.append(["role": msg.role, "content": blocks])
            } else if let content = msg.content {
                apiMessages.append(["role": msg.role, "content": content])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": apiMessages
        ]
        if !systemPrompt.isEmpty { body["system"] = systemPrompt }
        if !tools.isEmpty {
            body["tools"] = ToolFormatConverter.toAnthropic(tools)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        if let error = (json["error"] as? [String: Any])?["message"] as? String {
            throw AIProviderError.apiError(error)
        }

        guard let contentBlocks = json["content"] as? [[String: Any]] else {
            throw AIProviderError.invalidResponse
        }

        let (text, toolCalls) = ToolFormatConverter.parseAnthropicToolUse(contentBlocks)

        if !toolCalls.isEmpty {
            if let text = text, !text.isEmpty {
                return .mixed(text: text, toolCalls: toolCalls)
            }
            return .toolCalls(toolCalls)
        }

        return .text(text ?? "")
    }
}
