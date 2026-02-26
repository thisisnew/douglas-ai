import Foundation

protocol AIProvider {
    var config: ProviderConfig { get }
    func fetchModels() async throws -> [String]
    func sendMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)]
    ) async throws -> String
}

enum AIProviderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case networkError(String)
    case noAPIKey
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "잘못된 URL입니다."
        case .invalidResponse:       return "응답을 해석할 수 없습니다."
        case .apiError(let msg):     return "API 오류: \(msg)"
        case .networkError(let msg): return "네트워크 오류: \(msg)"
        case .noAPIKey:              return "API 키가 필요합니다."
        case .httpError(let code, let body):
            return "HTTP \(code): \(body.prefix(200))"
        }
    }
}

/// 공통 유틸리티 함수
extension AIProvider {
    /// HTTP 응답 상태 코드 검증
    func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIProviderError.httpError(
                statusCode: httpResponse.statusCode,
                body: "서버가 \(httpResponse.statusCode) 상태를 반환했습니다."
            )
        }
    }

    func applyAuth(to request: inout URLRequest) {
        switch config.authMethod {
        case .none:
            break
        case .apiKey:
            if let key = config.apiKey, !key.isEmpty {
                // Anthropic은 x-api-key, 나머지는 Authorization 헤더
                if config.type == .anthropic {
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                } else {
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                }
            }
        case .bearerToken:
            if let token = config.apiKey, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case .customHeader:
            if let name = config.customHeaderName, let value = config.customHeaderValue {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
    }
}
