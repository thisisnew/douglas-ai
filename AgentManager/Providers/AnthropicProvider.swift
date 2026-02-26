import Foundation

class AnthropicProvider: AIProvider {
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
        return result.content?.compactMap { $0.text }.joined() ?? ""
    }
}
