import Foundation
import os.log

class OpenAIProvider: AIProvider {
    private static let logger = Logger(subsystem: "com.agentmanager.app", category: "OpenAI")
    let config: ProviderConfig
    let session: URLSession

    init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetchModels() async throws -> [String] {
        guard let url = URL(string: "\(config.baseURL)/v1/models") else {
            throw AIProviderError.invalidURL
        }
        var request = URLRequest(url: url)
        applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        struct ModelList: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]?
        }
        let result = try JSONDecoder().decode(ModelList.self, from: data)
        return result.data?
            .map { $0.id }
            .filter { $0.contains("gpt") || $0.contains("o1") || $0.contains("o3") || $0.contains("o4") }
            .sorted() ?? []
    }

    func sendMessage(model: String, systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/v1/chat/completions") else {
            throw AIProviderError.invalidURL
        }
        var allMessages: [[String: String]] = []
        if !systemPrompt.isEmpty { allMessages.append(["role": "system", "content": systemPrompt]) }
        for msg in messages { allMessages.append(["role": msg.role, "content": msg.content]) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": allMessages] as [String: Any])
        request.timeoutInterval = 120
        applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]?
            let error: ErrorBody?
            struct ErrorBody: Decodable { let message: String }
        }
        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        if let error = result.error { throw AIProviderError.apiError(error.message) }
        let content = result.choices?.first?.message.content
        if content == nil {
            Self.logger.warning("OpenAI returned nil content for model \(model)")
        }
        return content ?? ""
    }

    // MARK: - 스트리밍

    var supportsStreaming: Bool { true }

    func sendMessageStreaming(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/v1/chat/completions") else {
            throw AIProviderError.invalidURL
        }
        var allMessages: [[String: String]] = []
        if !systemPrompt.isEmpty { allMessages.append(["role": "system", "content": systemPrompt]) }
        for msg in messages { allMessages.append(["role": msg.role, "content": msg.content]) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": allMessages, "stream": true
        ] as [String: Any])
        request.timeoutInterval = 120
        applyAuth(to: &request)

        let (bytes, response) = try await session.bytes(for: request)
        try validateHTTPResponse(response)

        return try await SSEParser.consume(bytes: bytes, extractChunk: { payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { return nil }
            return content
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
        guard let url = URL(string: "\(config.baseURL)/v1/chat/completions") else {
            throw AIProviderError.invalidURL
        }

        // 메시지 빌드
        var allMessages: [[String: Any]] = []
        if !systemPrompt.isEmpty {
            allMessages.append(["role": "system", "content": systemPrompt])
        }
        for msg in messages {
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                // assistant의 tool_calls 메시지
                allMessages.append(ToolFormatConverter.openAIAssistantToolCallMessage(toolCalls, text: msg.content))
            } else if msg.role == "tool", let callID = msg.toolCallID {
                // 도구 실행 결과
                allMessages.append(ToolFormatConverter.openAIToolResultMessage(callID: callID, content: msg.content ?? ""))
            } else if let attachments = msg.attachments, !attachments.isEmpty {
                // 이미지 첨부 메시지 → content array
                let parts = ToolFormatConverter.openAIContentArray(text: msg.content, attachments: attachments)
                allMessages.append(["role": msg.role, "content": parts] as [String: Any])
            } else if let content = msg.content {
                allMessages.append(["role": msg.role, "content": content])
            }
        }

        var body: [String: Any] = ["model": model, "messages": allMessages]
        if !tools.isEmpty {
            body["tools"] = ToolFormatConverter.toOpenAI(tools)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        // JSON 응답 파싱
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        if let error = (json["error"] as? [String: Any])?["message"] as? String {
            throw AIProviderError.apiError(error)
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }

        let textContent = message["content"] as? String
        let toolCallsRaw = message["tool_calls"] as? [[String: Any]]

        if let rawCalls = toolCallsRaw, !rawCalls.isEmpty {
            let calls = ToolFormatConverter.parseOpenAIToolCalls(rawCalls)
            if let text = textContent, !text.isEmpty {
                return .mixed(text: text, toolCalls: calls)
            }
            return .toolCalls(calls)
        }

        return .text(textContent ?? "")
    }
}
