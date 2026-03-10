import Foundation
import os.log

private let errorLogger = Logger(subsystem: "com.douglas.app", category: "ErrorClassify")

protocol AIProvider {
    var config: ProviderConfig { get }
    func fetchModels() async throws -> [String]
    func sendMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)]
    ) async throws -> String

    /// 도구 사용을 지원하는 메시지 전송
    func sendMessageWithTools(
        model: String,
        systemPrompt: String,
        messages: [ConversationMessage],
        tools: [AgentTool]
    ) async throws -> AIResponseContent

    /// 이 프로바이더가 네이티브 도구 호출을 지원하는지
    var supportsToolCalling: Bool { get }

    /// 스트리밍 지원 여부
    var supportsStreaming: Bool { get }

    /// 텍스트를 청크 단위로 스트리밍 전송. 완성된 전체 텍스트를 반환.
    func sendMessageStreaming(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String

    /// 라우터 전용: 내장 도구 없이 메시지 전송 (Claude Code CLI에서 URL 직접 접근 방지)
    func sendRouterMessage(
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

/// 기본 구현: 도구/스트리밍 미지원 프로바이더용 폴백
extension AIProvider {
    var supportsToolCalling: Bool { false }
    var supportsStreaming: Bool { false }

    func sendMessageStreaming(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let result = try await sendMessage(model: model, systemPrompt: systemPrompt, messages: messages)
        onChunk(result)
        return result
    }

    func sendRouterMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)]
    ) async throws -> String {
        // 기본: sendMessage와 동일 (OpenAI/Google/Anthropic은 도구 문제 없음)
        try await sendMessage(model: model, systemPrompt: systemPrompt, messages: messages)
    }

    func sendMessageWithTools(
        model: String,
        systemPrompt: String,
        messages: [ConversationMessage],
        tools: [AgentTool]
    ) async throws -> AIResponseContent {
        // 도구 메시지를 제외하고 기존 sendMessage로 폴백
        let simpleMsgs = messages
            .filter { $0.role != "tool" }
            .compactMap { msg -> (role: String, content: String)? in
                guard let content = msg.content else { return nil }
                return (role: msg.role, content: content)
            }
        let result = try await sendMessage(
            model: model, systemPrompt: systemPrompt, messages: simpleMsgs
        )
        return .text(result)
    }
}

// MARK: - 사용자 친화적 오류 메시지

extension Error {
    /// API 오류를 정형화된 사용자 메시지로 변환
    var userFacingMessage: String {
        if let providerError = self as? AIProviderError {
            switch providerError {
            case .noAPIKey:
                return "API 키가 설정되지 않았습니다. 설정에서 확인해 주세요."
            case .invalidURL:
                return "API 연결 설정을 확인해 주세요."
            case .invalidResponse:
                return "모델 응답을 처리할 수 없습니다. 다시 시도해 주세요."
            case .httpError(let code, let body):
                return classifyHTTPError(code: code, body: body)
            case .apiError(let msg):
                return classifyRawMessage(msg)
            case .networkError:
                return "네트워크 연결을 확인해 주세요."
            }
        }
        return classifyRawMessage(localizedDescription)
    }
}

private func classifyHTTPError(code: Int, body: String) -> String {
    // 429 = Too Many Requests → 항상 rate limit (Google의 token-per-minute quota도 429)
    // body에 "token"이 있어도 429면 rate limit이 맞음 (context window 초과는 400)
    if code == 429 {
        return "API 요청 한도에 도달했습니다. 잠시 후 다시 시도해 주세요."
    }

    // body에 세부 정보가 있으면 먼저 분류 시도
    let bodyClassified = classifyRawMessage(body)
    let fallback = "일시적인 오류가 발생했습니다. 다시 시도해 주세요."
    if bodyClassified != fallback { return bodyClassified }

    switch code {
    case 401, 403:
        return "API 인증에 실패했습니다. 키를 확인해 주세요."
    case 500...599:
        return "서버에 일시적인 문제가 발생했습니다. 잠시 후 다시 시도해 주세요."
    default:
        return "서버 통신 오류가 발생했습니다 (코드: \(code))."
    }
}

private func classifyRawMessage(_ message: String) -> String {
    let lower = message.lowercased()

    // [DEBUG] 원본 에러 메시지 로깅
    let preview = message.count > 500 ? String(message.prefix(500)) + "…" : message
    errorLogger.error("[DEBUG] classifyRawMessage 원본: \(preview, privacy: .public)")

    // Rate limit (token 체크보다 먼저 — Google의 token-per-minute quota가 "token"+"exceed" 포함)
    if (lower.contains("rate") && lower.contains("limit")) ||
       lower.contains("quota") || lower.contains("too many requests") ||
       lower.contains("resource_exhausted") || lower.contains("resource has been exhausted") {
        return "API 요청 한도에 도달했습니다. 잠시 후 다시 시도해 주세요."
    }

    // Token / context length limit
    if lower.contains("context_length") || lower.contains("context window") ||
       lower.contains("too long") || lower.contains("too many input tokens") ||
       (lower.contains("token") && (lower.contains("limit") || lower.contains("maximum") || lower.contains("exceed"))) {
        errorLogger.error("[DEBUG] → 토큰 한도 초과로 분류됨")
        return "모델의 토큰 한도를 초과했습니다. 대화를 정리하거나 다른 모델을 사용해 보세요."
    }

    // Auth
    if lower.contains("unauthorized") || lower.contains("authentication") ||
       (lower.contains("invalid") && lower.contains("key")) {
        return "API 인증에 실패했습니다. 키를 확인해 주세요."
    }

    // Server overload
    if lower.contains("overloaded") || lower.contains("capacity") {
        return "서버가 과부하 상태입니다. 잠시 후 다시 시도해 주세요."
    }

    // Timeout
    if lower.contains("timeout") || lower.contains("timed out") || lower.contains("시간 초과") {
        return "응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요."
    }

    // Network
    if lower.contains("network") || lower.contains("connection") ||
       lower.contains("internet") || lower.contains("네트워크") {
        return "네트워크 연결을 확인해 주세요."
    }

    // 원본 메시지가 있으면 포함하여 디버깅 용이하게
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return "일시적인 오류가 발생했습니다. 다시 시도해 주세요."
    }
    let fallbackPreview = trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    return "오류: \(fallbackPreview)"
}

// MARK: - SSE 스트리밍 유틸리티

/// SSE 라인 파서 (프로바이더 공용)
enum SSEParser {
    /// URLSession.AsyncBytes를 SSE 라인 단위로 파싱하여 청크 콜백 호출
    static func consume(
        bytes: URLSession.AsyncBytes,
        extractChunk: @escaping (String) -> String?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        var accumulated = ""
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }
                if let chunk = extractChunk(payload) {
                    accumulated += chunk
                    onChunk(chunk)
                }
            }
        }
        return accumulated
    }
}

// MARK: - HTTP 재시도 유틸리티

/// 429/503 등 일시적 HTTP 에러에 대한 지수 백오프 재시도
enum HTTPRetry {
    private static let retryableStatusCodes: Set<Int> = [429, 503]

    /// HTTP 요청을 실행하고, 일시적 에러(429/503)에 대해 자동 재시도
    /// - Parameters:
    ///   - request: 실행할 URLRequest
    ///   - session: URLSession
    ///   - maxRetries: 최대 재시도 횟수 (기본 3회, 총 시도 = 1 + maxRetries)
    ///   - baseDelay: 백오프 기본 지연 시간(초). 테스트 시 작은 값 사용
    /// - Returns: (응답 데이터, HTTP 응답)
    static func data(
        for request: URLRequest,
        session: URLSession,
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0
    ) async throws -> (Data, HTTPURLResponse) {
        var lastResponse: HTTPURLResponse?
        var lastError: AIProviderError?

        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = retryDelay(attempt: attempt, response: lastResponse, baseDelay: baseDelay)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIProviderError.invalidResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                return (data, httpResponse)
            }

            let bodyString = String(data: data, encoding: .utf8)
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? "서버가 \(httpResponse.statusCode) 상태를 반환했습니다."
            let error = AIProviderError.httpError(
                statusCode: httpResponse.statusCode,
                body: bodyString
            )

            if retryableStatusCodes.contains(httpResponse.statusCode), attempt < maxRetries {
                lastResponse = httpResponse
                lastError = error
                continue
            }

            throw error
        }

        throw lastError ?? AIProviderError.networkError("재시도 횟수를 초과했습니다.")
    }

    /// 스트리밍 HTTP 요청 + 429/503 자동 재시도
    /// 에러 시 바이트 스트림을 소비하여 응답 body를 에러에 포함
    static func bytes(
        for request: URLRequest,
        session: URLSession,
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var lastResponse: HTTPURLResponse?
        var lastError: AIProviderError?

        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = retryDelay(attempt: attempt, response: lastResponse, baseDelay: baseDelay)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIProviderError.invalidResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                return (bytes, httpResponse)
            }

            // 에러 응답: 바이트 스트림에서 body 읽기
            var errorLines: [String] = []
            for try await line in bytes.lines {
                errorLines.append(line)
            }
            let bodyString = errorLines.isEmpty
                ? "서버가 \(httpResponse.statusCode) 상태를 반환했습니다."
                : errorLines.joined(separator: "\n")
            let error = AIProviderError.httpError(
                statusCode: httpResponse.statusCode,
                body: bodyString
            )

            if retryableStatusCodes.contains(httpResponse.statusCode), attempt < maxRetries {
                lastResponse = httpResponse
                lastError = error
                continue
            }

            throw error
        }

        throw lastError ?? AIProviderError.networkError("재시도 횟수를 초과했습니다.")
    }

    /// Retry-After 헤더 우선, 없으면 지수 백오프 (baseDelay × 2^(attempt-1), 최대 30초)
    private static func retryDelay(
        attempt: Int,
        response: HTTPURLResponse?,
        baseDelay: TimeInterval
    ) -> TimeInterval {
        if let response,
           let retryAfterStr = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryAfterStr) {
            return min(seconds, 60.0)
        }
        return min(baseDelay * pow(2.0, Double(attempt - 1)), 30.0)
    }
}

/// 공통 유틸리티 함수
extension AIProvider {
    /// HTTP 응답 상태 코드 검증
    /// - Parameters:
    ///   - response: HTTP 응답
    ///   - data: 응답 body (제공 시 에러 메시지에 포함)
    func validateHTTPResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyString: String
            if let data, let str = String(data: data, encoding: .utf8), !str.isEmpty {
                bodyString = str
            } else {
                bodyString = "서버가 \(httpResponse.statusCode) 상태를 반환했습니다."
            }
            throw AIProviderError.httpError(
                statusCode: httpResponse.statusCode,
                body: bodyString
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
