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
    // body에 세부 정보가 있으면 먼저 분류 시도
    let bodyClassified = classifyRawMessage(body)
    let fallback = "일시적인 오류가 발생했습니다. 다시 시도해 주세요."
    if bodyClassified != fallback { return bodyClassified }

    switch code {
    case 401, 403:
        return "API 인증에 실패했습니다. 키를 확인해 주세요."
    case 429:
        return "API 요청 한도에 도달했습니다. 잠시 후 다시 시도해 주세요."
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

    // Token / context length limit
    if lower.contains("context_length") || lower.contains("context window") ||
       lower.contains("too long") || lower.contains("too many input tokens") ||
       (lower.contains("token") && (lower.contains("limit") || lower.contains("maximum") || lower.contains("exceed"))) {
        errorLogger.error("[DEBUG] → 토큰 한도 초과로 분류됨")
        return "모델의 토큰 한도를 초과했습니다. 대화를 정리하거나 다른 모델을 사용해 보세요."
    }

    // Rate limit
    if (lower.contains("rate") && lower.contains("limit")) ||
       lower.contains("quota") || lower.contains("too many requests") {
        return "API 요청 한도에 도달했습니다. 잠시 후 다시 시도해 주세요."
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
    let preview = trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    return "오류: \(preview)"
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
