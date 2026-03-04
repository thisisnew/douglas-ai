import Foundation

class GoogleProvider: AIProvider {
    let config: ProviderConfig
    let session: URLSession

    init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// 하드코딩 모델 목록 (API 실패 시 폴백)
    private static let fallbackModels = ["gemini-2.0-flash", "gemini-2.0-pro", "gemini-1.5-flash", "gemini-1.5-pro"]

    func fetchModels() async throws -> [String] {
        guard let key = config.apiKey, !key.isEmpty else { throw AIProviderError.noAPIKey }

        let urlString = "\(config.baseURL)/v1beta/models"
        guard let url = URL(string: urlString) else { throw AIProviderError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        struct ModelList: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]?
        }
        let result = try JSONDecoder().decode(ModelList.self, from: data)
        let models = result.models?
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .filter { $0.contains("gemini") }
            .sorted() ?? []
        return models.isEmpty ? Self.fallbackModels : models
    }

    func sendMessage(model: String, systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        guard let key = config.apiKey, !key.isEmpty else { throw AIProviderError.noAPIKey }
        let urlString = "\(config.baseURL)/v1beta/models/\(model):generateContent"
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
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
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
        guard let key = config.apiKey, !key.isEmpty else { throw AIProviderError.noAPIKey }
        let urlString = "\(config.baseURL)/v1beta/models/\(model):generateContent"
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
                contents.append(["role": "user", "parts": [part]])
            } else if let attachments = msg.attachments, !attachments.isEmpty {
                // 이미지 첨부 메시지 → inlineData parts
                let parts = ToolFormatConverter.googleParts(text: msg.content, attachments: attachments)
                let role = msg.role == "assistant" ? "model" : "user"
                contents.append(["role": role, "parts": parts])
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
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
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
