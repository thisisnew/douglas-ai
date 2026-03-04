import Foundation

/// 감지된 프로바이더 정보
struct DetectedProvider: Identifiable {
    let id = UUID()
    let type: ProviderType
    let displayName: String
    let detail: String
    let prefilledAPIKey: String?
    let isConfirmed: Bool  // 실행파일/서버 확인 vs 환경변수만

    /// API 키 마스킹 표시 (마지막 4자만)
    var maskedKey: String? {
        guard let key = prefilledAPIKey, key.count > 4 else { return prefilledAPIKey }
        return "···" + key.suffix(4)
    }

    /// 이 타입이 API 키가 필요한지
    var needsAPIKey: Bool {
        type.defaultAuthMethod == .apiKey
    }
}

/// 시스템에서 AI 프로바이더를 자동 감지
enum ProviderDetector {

    /// 테스트에서 교체 가능한 URLSession (프로덕션: .shared)
    /// @TaskLocal로 병렬 테스트 간 세션 충돌 방지.
    @TaskLocal static var urlSession: URLSession = .shared

    /// 테스트에서 mock URLSession을 태스크 격리 방식으로 주입
    static func withSession(
        _ session: URLSession,
        body: () async throws -> Void
    ) async rethrows {
        try await $urlSession.withValue(session, operation: body)
    }

    /// 모든 감지를 병렬 실행
    static func detectAll() async -> [DetectedProvider] {
        async let claude = detectClaudeCode()
        async let openAI = detectOpenAIKey()
        async let anthropic = detectAnthropicKey()
        async let google = detectGoogleKey()

        let results = await [claude, openAI, anthropic, google]
        return results.compactMap { $0 }
    }

    // MARK: - Claude Code CLI

    static func detectClaudeCode() async -> DetectedProvider? {
        let path = ClaudeCodeProvider.findClaudePath()
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return DetectedProvider(
            type: .claudeCode,
            displayName: "Claude Code CLI",
            detail: path,
            prefilledAPIKey: nil,
            isConfirmed: true
        )
    }

    // MARK: - OpenAI

    static func detectOpenAIKey() async -> DetectedProvider? {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !key.isEmpty else { return nil }
        return DetectedProvider(
            type: .openAI,
            displayName: "OpenAI API",
            detail: "환경변수 OPENAI_API_KEY 발견",
            prefilledAPIKey: key,
            isConfirmed: false
        )
    }

    // MARK: - Anthropic

    static func detectAnthropicKey() async -> DetectedProvider? {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !key.isEmpty else { return nil }
        return DetectedProvider(
            type: .anthropic,
            displayName: "Anthropic API",
            detail: "환경변수 ANTHROPIC_API_KEY 발견",
            prefilledAPIKey: key,
            isConfirmed: false
        )
    }

    // MARK: - Google

    static func detectGoogleKey() async -> DetectedProvider? {
        let key = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        guard let key, !key.isEmpty else { return nil }
        return DetectedProvider(
            type: .google,
            displayName: "Google Gemini API",
            detail: "환경변수에서 API 키 발견",
            prefilledAPIKey: key,
            isConfirmed: false
        )
    }

    // MARK: - HTTP 체크 유틸리티

    private static func checkHTTP(url: String, timeout: TimeInterval) async -> Bool {
        guard let url = URL(string: url) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        do {
            let (_, response) = try await urlSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
