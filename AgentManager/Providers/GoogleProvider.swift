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
}
