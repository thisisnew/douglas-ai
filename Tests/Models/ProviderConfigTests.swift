import Testing
import Foundation
@testable import AgentManagerLib

@Suite("ProviderConfig Model Tests")
struct ProviderConfigTests {

    @Test("기본 초기화 (apiKey 없이)")
    func initWithoutApiKey() {
        let config = makeTestProviderConfig(name: "Test", type: .ollama, baseURL: "http://localhost:11434")
        #expect(config.name == "Test")
        #expect(config.type == .ollama)
        #expect(config.baseURL == "http://localhost:11434")
        #expect(config.authMethod == .none)
        #expect(config.isBuiltIn == false)
    }

    @Test("Codable 라운드트립 (apiKey 없이)")
    func codableRoundTripNoApiKey() throws {
        let original = makeTestProviderConfig(name: "Ollama", type: .ollama, baseURL: "http://localhost:11434")
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
        #expect(ProviderType.ollama.defaultBaseURL == "http://localhost:11434")
        #expect(ProviderType.lmStudio.defaultBaseURL == "http://localhost:1234")
        #expect(ProviderType.openAI.defaultBaseURL == "https://api.openai.com")
        #expect(ProviderType.anthropic.defaultBaseURL == "https://api.anthropic.com")
        #expect(ProviderType.google.defaultBaseURL == "https://generativelanguage.googleapis.com")
        #expect(ProviderType.custom.defaultBaseURL == "")
    }

    @Test("ProviderType 기본 인증 방식")
    func providerTypeDefaultAuthMethod() {
        #expect(ProviderType.claudeCode.defaultAuthMethod == .none)
        #expect(ProviderType.ollama.defaultAuthMethod == .none)
        #expect(ProviderType.lmStudio.defaultAuthMethod == .none)
        #expect(ProviderType.openAI.defaultAuthMethod == .apiKey)
        #expect(ProviderType.anthropic.defaultAuthMethod == .apiKey)
        #expect(ProviderType.google.defaultAuthMethod == .apiKey)
        #expect(ProviderType.custom.defaultAuthMethod == .none)
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

    @Test("isConnected - Ollama는 항상 true")
    func isConnectedOllama() {
        let config = makeTestProviderConfig(type: .ollama, baseURL: "http://localhost:11434")
        #expect(config.isConnected == true)
    }

    @Test("isConnected - LM Studio는 항상 true")
    func isConnectedLMStudio() {
        let config = makeTestProviderConfig(type: .lmStudio, baseURL: "http://localhost:1234")
        #expect(config.isConnected == true)
    }

    @Test("isConnected - OpenAI (apiKey 없으면 false)")
    func isConnectedOpenAINoKey() {
        let config = makeTestProviderConfig(type: .openAI, baseURL: "https://api.openai.com", authMethod: .apiKey)
        #expect(config.isConnected == false)
    }

    @Test("isConnected - Custom (baseURL 비어있으면 false)")
    func isConnectedCustomEmpty() {
        let config = makeTestProviderConfig(type: .custom, baseURL: "")
        #expect(config.isConnected == false)
    }

    @Test("isConnected - Custom (baseURL 있으면 true)")
    func isConnectedCustomWithURL() {
        let config = makeTestProviderConfig(type: .custom, baseURL: "https://example.com")
        #expect(config.isConnected == true)
    }
}
