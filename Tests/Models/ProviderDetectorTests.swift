import Testing
import Foundation
@testable import DOUGLAS

@Suite("ProviderDetector Tests")
struct ProviderDetectorTests {

    // MARK: - DetectedProvider 모델

    @Test("DetectedProvider - 기본 초기화")
    func detectedProviderInit() {
        let provider = DetectedProvider(
            type: .openAI,
            displayName: "OpenAI API",
            detail: "환경변수 발견",
            prefilledAPIKey: "sk-abc123",
            isConfirmed: false
        )
        #expect(provider.type == .openAI)
        #expect(provider.displayName == "OpenAI API")
        #expect(provider.detail == "환경변수 발견")
        #expect(provider.prefilledAPIKey == "sk-abc123")
        #expect(provider.isConfirmed == false)
    }

    @Test("DetectedProvider - Identifiable (고유 ID)")
    func detectedProviderIdentifiable() {
        let a = DetectedProvider(type: .openAI, displayName: "A", detail: "", prefilledAPIKey: nil, isConfirmed: true)
        let b = DetectedProvider(type: .openAI, displayName: "A", detail: "", prefilledAPIKey: nil, isConfirmed: true)
        #expect(a.id != b.id) // UUID 기반
    }

    // MARK: - maskedKey

    @Test("maskedKey - 5자 이상 키")
    func maskedKeyNormal() {
        let provider = DetectedProvider(
            type: .openAI, displayName: "", detail: "",
            prefilledAPIKey: "sk-abcdef123456",
            isConfirmed: false
        )
        #expect(provider.maskedKey == "···3456")
    }

    @Test("maskedKey - 정확히 4자")
    func maskedKeyExact4() {
        let provider = DetectedProvider(
            type: .openAI, displayName: "", detail: "",
            prefilledAPIKey: "abcd",
            isConfirmed: false
        )
        // count == 4이므로 guard let 통과 못 함 (count > 4 조건)
        #expect(provider.maskedKey == "abcd")
    }

    @Test("maskedKey - 3자 이하")
    func maskedKeyShort() {
        let provider = DetectedProvider(
            type: .openAI, displayName: "", detail: "",
            prefilledAPIKey: "abc",
            isConfirmed: false
        )
        #expect(provider.maskedKey == "abc")
    }

    @Test("maskedKey - nil 키")
    func maskedKeyNil() {
        let provider = DetectedProvider(
            type: .claudeCode, displayName: "", detail: "",
            prefilledAPIKey: nil,
            isConfirmed: true
        )
        #expect(provider.maskedKey == nil)
    }

    @Test("maskedKey - 빈 문자열")
    func maskedKeyEmpty() {
        let provider = DetectedProvider(
            type: .openAI, displayName: "", detail: "",
            prefilledAPIKey: "",
            isConfirmed: false
        )
        #expect(provider.maskedKey == "")
    }

    // MARK: - needsAPIKey

    @Test("needsAPIKey - API Key 필요 (OpenAI)")
    func needsAPIKeyOpenAI() {
        let provider = DetectedProvider(
            type: .openAI, displayName: "", detail: "",
            prefilledAPIKey: nil, isConfirmed: false
        )
        #expect(provider.needsAPIKey == true)
    }

    @Test("needsAPIKey - API Key 필요 (Google)")
    func needsAPIKeyGoogle() {
        let provider = DetectedProvider(
            type: .google, displayName: "", detail: "",
            prefilledAPIKey: nil, isConfirmed: false
        )
        #expect(provider.needsAPIKey == true)
    }

    @Test("needsAPIKey - API Key 필요 (Anthropic)")
    func needsAPIKeyAnthropic() {
        let provider = DetectedProvider(
            type: .anthropic, displayName: "", detail: "",
            prefilledAPIKey: nil, isConfirmed: false
        )
        #expect(provider.needsAPIKey == true)
    }

    @Test("needsAPIKey - 불필요 (Claude Code)")
    func needsAPIKeyClaudeCode() {
        let provider = DetectedProvider(
            type: .claudeCode, displayName: "", detail: "",
            prefilledAPIKey: nil, isConfirmed: true
        )
        #expect(provider.needsAPIKey == false)
    }

    // MARK: - detectClaudeCode

    @Test("detectClaudeCode - 바이너리 없으면 nil")
    func detectClaudeCodeNotFound() async {
        // findClaudePath가 "claude"를 반환하고 executable이 아닌 경우
        let result = await ProviderDetector.detectClaudeCode()
        // 실제 환경에 따라 다를 수 있음 — 결과가 nil이거나 올바른 DetectedProvider
        if let r = result {
            #expect(r.type == .claudeCode)
            #expect(r.isConfirmed == true)
        }
    }

    // MARK: - detectOpenAIKey

    @Test("detectOpenAIKey - 환경변수 없으면 nil 가능")
    func detectOpenAIKeyMissing() async {
        // OPENAI_API_KEY 환경변수가 없으면 nil
        let result = await ProviderDetector.detectOpenAIKey()
        if ProcessInfo.processInfo.environment["OPENAI_API_KEY"] == nil {
            #expect(result == nil)
        } else {
            #expect(result?.type == .openAI)
            #expect(result?.prefilledAPIKey != nil)
        }
    }

    // MARK: - detectAnthropicKey

    @Test("detectAnthropicKey - 환경변수 없으면 nil 가능")
    func detectAnthropicKeyMissing() async {
        let result = await ProviderDetector.detectAnthropicKey()
        if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] == nil {
            #expect(result == nil)
        } else {
            #expect(result?.type == .anthropic)
            #expect(result?.prefilledAPIKey != nil)
        }
    }

    // MARK: - detectGoogleKey

    @Test("detectGoogleKey - 환경변수 없으면 nil 가능")
    func detectGoogleKeyMissing() async {
        let result = await ProviderDetector.detectGoogleKey()
        let hasKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] != nil
            || ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil
        if !hasKey {
            #expect(result == nil)
        } else {
            #expect(result?.type == .google)
        }
    }

    // MARK: - detectAll

    @Test("detectAll - 결과 배열 반환")
    func detectAllReturnsArray() async {
        let results = await ProviderDetector.detectAll()
        // 모든 결과가 유효한 타입이어야 함
        for r in results {
            #expect(r.displayName.isEmpty == false)
        }
    }

    // MARK: - checkHTTP (urlSession 목 테스트)

    @Test("checkHTTP - 목 URLSession으로 성공 응답")
    func checkHTTPSuccessMock() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        defer { MockURLProtocol.requestHandler = nil }

        // @TaskLocal withSession으로 태스크 격리 mock 주입
        await ProviderDetector.withSession(mockSession) {
            let results = await ProviderDetector.detectAll()
            for r in results {
                #expect(r.displayName.isEmpty == false)
            }
        }
    }
}
