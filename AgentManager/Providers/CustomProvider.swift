import Foundation

/// OpenAI 호환 API 형식을 사용하는 커스텀 프로바이더
/// LM Studio, vLLM, text-generation-webui 등에서 사용 가능
class CustomProvider: AIProvider {
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
            struct Model: Decodable {
                let id: String
            }
            let data: [Model]?
        }

        let result = try JSONDecoder().decode(ModelList.self, from: data)
        return result.data?.map { $0.id }.sorted() ?? []
    }

    func sendMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)]
    ) async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/v1/chat/completions") else {
            throw AIProviderError.invalidURL
        }

        var allMessages: [[String: String]] = []
        if !systemPrompt.isEmpty {
            allMessages.append(["role": "system", "content": systemPrompt])
        }
        for msg in messages {
            allMessages.append(["role": msg.role, "content": msg.content])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": allMessages
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]?
        }

        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        return result.choices?.first?.message.content ?? ""
    }
}
