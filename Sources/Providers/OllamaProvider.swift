import Foundation

/// Ollama & LM Studio 공용 (OpenAI 호환 로컬 모델)
class OllamaProvider: AIProvider {
    let config: ProviderConfig
    let session: URLSession

    init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetchModels() async throws -> [String] {
        // Ollama: /api/tags, LM Studio: /v1/models
        let isLMStudio = config.type == .lmStudio
        let endpoint = isLMStudio ? "\(config.baseURL)/v1/models" : "\(config.baseURL)/api/tags"

        guard let url = URL(string: endpoint) else {
            throw AIProviderError.invalidURL
        }

        var request = URLRequest(url: url)
        applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        if isLMStudio {
            struct ModelList: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]?
            }
            let result = try JSONDecoder().decode(ModelList.self, from: data)
            return result.data?.map { $0.id }.sorted() ?? []
        } else {
            struct OllamaModels: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]?
            }
            let result = try JSONDecoder().decode(OllamaModels.self, from: data)
            return result.models?.map { $0.name } ?? []
        }
    }

    func sendMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)]
    ) async throws -> String {
        let isLMStudio = config.type == .lmStudio
        let endpoint = isLMStudio
            ? "\(config.baseURL)/v1/chat/completions"
            : "\(config.baseURL)/api/chat"

        guard let url = URL(string: endpoint) else {
            throw AIProviderError.invalidURL
        }

        var allMessages: [[String: String]] = []
        if !systemPrompt.isEmpty {
            allMessages.append(["role": "system", "content": systemPrompt])
        }
        for msg in messages {
            allMessages.append(["role": msg.role, "content": msg.content])
        }

        var body: [String: Any] = [
            "model": model,
            "messages": allMessages
        ]
        if !isLMStudio { body["stream"] = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        if isLMStudio {
            struct ChatResponse: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String? }
                    let message: Message
                }
                let choices: [Choice]?
            }
            let result = try JSONDecoder().decode(ChatResponse.self, from: data)
            return result.choices?.first?.message.content ?? ""
        } else {
            struct OllamaResponse: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message?
                let error: String?
            }
            let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
            if let error = result.error { throw AIProviderError.apiError(error) }
            return result.message?.content ?? ""
        }
    }
}
