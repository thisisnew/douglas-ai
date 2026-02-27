import Testing
import Foundation
@testable import DOUGLASLib

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

    @Test("needsAPIKey - 불필요 (Ollama)")
    func needsAPIKeyOllama() {
        let provider = DetectedProvider(
            type: .ollama, displayName: "", detail: "",
            prefilledAPIKey: nil, isConfirmed: true
        )
        #expect(provider.needsAPIKey == false)
    }

    @Test("needsAPIKey - 불필요 (LM Studio)")
    func needsAPIKeyLMStudio() {
        let provider = DetectedProvider(
            type: .lmStudio, displayName: "", detail: "",
            prefilledAPIKey: nil, isConfirmed: true
        )
        #expect(provider.needsAPIKey == false)
    }

}
