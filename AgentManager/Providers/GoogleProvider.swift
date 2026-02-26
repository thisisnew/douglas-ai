import Foundation

class GoogleProvider: AIProvider {
    let config: ProviderConfig
    let session: URLSession

    init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetchModels() async throws -> [String] {
        return ["gemini-2.0-flash", "gemini-2.0-pro", "gemini-1.5-flash", "gemini-1.5-pro"]
    }

    func sendMessage(model: String, systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        let key = config.apiKey ?? ""
        let urlString = "\(config.baseURL)/v1beta/models/\(model):generateContent?key=\(key)"
        guard let url = URL(string: urlString) else { throw AIProviderError.invalidURL }

        var contents: [[String: Any]] = []
        for msg in messages {
            contents.append(["role": msg.role == "assistant" ? "model" : "user", "parts": [["text": msg.content]]])
        }

        var body: [String: Any] = ["contents": contents]

        // systemInstruction 필드 사용 (가짜 대화 대신 공식 API 방식)
        if !systemPrompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        struct Resp: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
            let error: ErrBody?
            struct ErrBody: Decodable { let message: String }
        }
        let result = try JSONDecoder().decode(Resp.self, from: data)
        if let error = result.error { throw AIProviderError.apiError(error.message) }
        return result.candidates?.first?.content?.parts?.compactMap { $0.text }.joined() ?? ""
    }

    // MARK: - Tool Use 지원

    var supportsToolCalling: Bool { true }

    func sendMessageWithTools(
        model: String,
        systemPrompt: String,
        messages: [ConversationMessage],
        tools: [AgentTool]
    ) async throws -> AIResponseContent {
        let key = config.apiKey ?? ""
        let urlString = "\(config.baseURL)/v1beta/models/\(model):generateContent?key=\(key)"
        guard let url = URL(string: urlString) else { throw AIProviderError.invalidURL }

        // Google 메시지 빌드
        var contents: [[String: Any]] = []
        for msg in messages {
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                // model의 functionCall parts
                var parts: [[String: Any]] = []
                if let text = msg.content, !text.isEmpty {
                    parts.append(["text": text])
                }
                for call in toolCalls {
                    var argsDict: [String: Any] = [:]
                    for (k, v) in call.arguments {
                        switch v {
                        case .string(let s):  argsDict[k] = s
                        case .integer(let i): argsDict[k] = i
                        case .boolean(let b): argsDict[k] = b
                        case .array(let a):   argsDict[k] = a
                        }
                    }
                    parts.append(["functionCall": ["name": call.toolName, "args": argsDict]])
                }
                contents.append(["role": "model", "parts": parts])
            } else if msg.role == "tool" {
                // functionResponse
                let toolName = msg.toolCallID ?? "unknown"
                let part = ToolFormatConverter.googleFunctionResponsePart(name: toolName, content: msg.content ?? "")
                contents.append(["role": "function", "parts": [part]])
            } else if let content = msg.content {
                let role = msg.role == "assistant" ? "model" : "user"
                contents.append(["role": role, "parts": [["text": content]]])
            }
        }

        var body: [String: Any] = ["contents": contents]
        if !systemPrompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }
        if !tools.isEmpty {
            body["tools"] = ToolFormatConverter.toGoogle(tools)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        if let error = (json["error"] as? [String: Any])?["message"] as? String {
            throw AIProviderError.apiError(error)
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let candidateContent = candidates.first?["content"] as? [String: Any],
              let parts = candidateContent["parts"] as? [[String: Any]] else {
            throw AIProviderError.invalidResponse
        }

        let (text, toolCalls) = ToolFormatConverter.parseGoogleFunctionCalls(parts)

        if !toolCalls.isEmpty {
            if let text = text, !text.isEmpty {
                return .mixed(text: text, toolCalls: toolCalls)
            }
            return .toolCalls(toolCalls)
        }

        return .text(text ?? "")
    }
}
