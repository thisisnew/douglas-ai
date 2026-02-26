import Foundation

class OpenAIProvider: AIProvider {
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
        return result.choices?.first?.message.content ?? ""
    }
}
