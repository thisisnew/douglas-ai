import Testing
import Foundation
@testable import DOUGLAS

@Suite("ProviderConfig Model Tests")
struct ProviderConfigTests {

    @Test("기본 초기화 (apiKey 없이)")
    func initWithoutApiKey() {
        let config = makeTestProviderConfig(name: "Test", type: .openAI, baseURL: "https://api.openai.com")
        #expect(config.name == "Test")
        #expect(config.type == .openAI)
        #expect(config.baseURL == "https://api.openai.com")
        #expect(config.authMethod == .none)
        #expect(config.isBuiltIn == false)
    }

    @Test("Codable 라운드트립 (apiKey 없이)")
    func codableRoundTripNoApiKey() throws {
        let original = makeTestProviderConfig(name: "Google", type: .google, baseURL: "https://generativelanguage.googleapis.com")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: data)
        #expect(decoded.name == original.name)
        #expect(decoded.type == original.type)
        #expect(decoded.baseURL == original.baseURL)
        #expect(decoded.authMethod == original.authMethod)
    }

    @Test("Codable - apiKey는 JSON에 포함되지 않음")
    func codableExcludesApiKey() throws {
        let config = makeTestProviderConfig()
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["apiKey"] == nil)
    }

    @Test("Decodable - authMethod 없는 레거시 JSON")
    func decodeLegacyWithoutAuthMethod() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "OpenAI",
            "type": "OpenAI",
            "baseURL": "https://api.openai.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let config = try JSONDecoder().decode(ProviderConfig.self, from: data)
        #expect(config.authMethod == ProviderType.openAI.defaultAuthMethod)
    }

    @Test("Decodable - isBuiltIn 없는 레거시 JSON")
    func decodeLegacyWithoutIsBuiltIn() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Custom",
            "type": "Custom",
            "baseURL": "https://example.com",
            "authMethod": "없음 (로컬)"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let config = try JSONDecoder().decode(ProviderConfig.self, from: data)
        #expect(config.isBuiltIn == false)
    }

    @Test("ProviderType 기본 baseURL")
    func providerTypeDefaultBaseURL() {
        #expect(ProviderType.openAI.defaultBaseURL == "https://api.openai.com")
        #expect(ProviderType.anthropic.defaultBaseURL == "https://api.anthropic.com")
        #expect(ProviderType.google.defaultBaseURL == "https://generativelanguage.googleapis.com")
    }

    @Test("ProviderType 기본 인증 방식")
    func providerTypeDefaultAuthMethod() {
        #expect(ProviderType.claudeCode.defaultAuthMethod == .none)
        #expect(ProviderType.openAI.defaultAuthMethod == .apiKey)
        #expect(ProviderType.anthropic.defaultAuthMethod == .apiKey)
        #expect(ProviderType.google.defaultAuthMethod == .apiKey)
    }

    @Test("AuthMethod CaseIterable")
    func authMethodAllCases() {
        let cases = AuthMethod.allCases
        #expect(cases.count == 4)
        #expect(cases.contains(.none))
        #expect(cases.contains(.apiKey))
        #expect(cases.contains(.bearerToken))
        #expect(cases.contains(.customHeader))
    }

    @Test("AuthMethod description 비어있지 않음")
    func authMethodDescriptions() {
        for method in AuthMethod.allCases {
            #expect(!method.description.isEmpty)
        }
    }

    // MARK: - isConnected

    @Test("isConnected - OpenAI (apiKey 없으면 false)")
    func isConnectedOpenAINoKey() {
        let config = makeTestProviderConfig(type: .openAI, baseURL: "https://api.openai.com", authMethod: .apiKey)
        #expect(config.isConnected == false)
    }

    @Test("isConnected - Claude Code (존재하지 않는 경로)")
    func isConnectedClaudeCodeNotFound() {
        let config = makeTestProviderConfig(type: .claudeCode, baseURL: "/nonexistent/path/claude")
        #expect(config.isConnected == false)
    }

    // MARK: - apiKey (Keychain 통합)

    @Test("apiKey - init에서 설정 → get으로 조회")
    func apiKeyInitAndGet() {
        let config = ProviderConfig(
            name: "TestProvider",
            type: .openAI,
            baseURL: "https://api.openai.com",
            authMethod: .apiKey,
            apiKey: "sk-test-key-\(UUID().uuidString)"
        )
        let loaded = config.apiKey
        #expect(loaded != nil)
        #expect(loaded?.contains("sk-test-key-") == true)
        // cleanup
        var mutable = config
        mutable.apiKey = nil
    }

    @Test("apiKey - set으로 변경")
    func apiKeySet() {
        var config = ProviderConfig(
            name: "TestProvider",
            type: .openAI,
            baseURL: "https://api.openai.com"
        )
        let key = "new-key-\(UUID().uuidString)"
        config.apiKey = key
        #expect(config.apiKey == key)
        // cleanup
        config.apiKey = nil
    }

    @Test("apiKey - nil로 설정하면 삭제")
    func apiKeyDelete() {
        var config = ProviderConfig(
            name: "TestProvider",
            type: .openAI,
            baseURL: "https://api.openai.com",
            apiKey: "temp-key"
        )
        config.apiKey = nil
        #expect(config.apiKey == nil)
    }

    @Test("isConnected - OpenAI (apiKey 있으면 true)")
    func isConnectedOpenAIWithKey() {
        let config = ProviderConfig(
            name: "OpenAI",
            type: .openAI,
            baseURL: "https://api.openai.com",
            authMethod: .apiKey,
            apiKey: "sk-connected-\(UUID().uuidString)"
        )
        #expect(config.isConnected == true)
        // cleanup
        var mutable = config
        mutable.apiKey = nil
    }

    // MARK: - 레거시 apiKey 마이그레이션

    @Test("Decodable - 레거시 apiKey JSON에서 마이그레이션")
    func decodeLegacyApiKey() throws {
        let id = UUID()
        let legacyKey = "legacy-api-key-\(UUID().uuidString)"
        let json: [String: Any] = [
            "id": id.uuidString,
            "name": "OpenAI",
            "type": "OpenAI",
            "baseURL": "https://api.openai.com",
            "authMethod": "API Key",
            "apiKey": legacyKey  // 레거시 필드
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // 기존 Keychain에 해당 키가 없어야 마이그레이션 발생
        _ = try? KeychainHelper.delete(key: "provider-apikey-\(id.uuidString)")

        let config = try JSONDecoder().decode(ProviderConfig.self, from: data)
        #expect(config.apiKey == legacyKey)
        // cleanup
        var mutable = config
        mutable.apiKey = nil
    }

    // MARK: - ProviderType 추가

    @Test("ProviderType - claudeCode defaultBaseURL")
    func claudeCodeDefaultBaseURL() {
        // findClaudePath()의 반환값 (환경에 따라 다름)
        let url = ProviderType.claudeCode.defaultBaseURL
        #expect(!url.isEmpty)
    }

    @Test("ProviderType - label 비어있지 않음")
    func providerTypeLabels() {
        for type in ProviderType.allCases {
            #expect(!type.label.isEmpty)
        }
    }

    @Test("ProviderType - CaseIterable")
    func providerTypeCaseIterable() {
        #expect(ProviderType.allCases.count == 7)
    }
}
