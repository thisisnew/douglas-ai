import Testing
import Foundation
@testable import DOUGLAS

@Suite("ProviderConfig Tests")
struct ProviderConfigTests {

    // MARK: - AuthMethod

    @Test("AuthMethod - allCases 4개")
    func authMethodCaseCount() {
        #expect(AuthMethod.allCases.count == 4)
    }

    @Test("AuthMethod - description 비어있지 않은 한국어 문자열")
    func authMethodDescriptions() {
        for method in AuthMethod.allCases {
            #expect(!method.description.isEmpty)
        }
    }

    @Test("AuthMethod - rawValue 왕복")
    func authMethodRawValueRoundtrip() {
        for method in AuthMethod.allCases {
            let raw = method.rawValue
            #expect(AuthMethod(rawValue: raw) == method)
        }
    }

    @Test("AuthMethod - Codable 왕복")
    func authMethodCodable() throws {
        for method in AuthMethod.allCases {
            let data = try JSONEncoder().encode(method)
            let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
            #expect(decoded == method)
        }
    }

    // MARK: - ProviderType

    @Test("ProviderType - allCases 7개")
    func providerTypeCaseCount() {
        #expect(ProviderType.allCases.count == 7)
    }

    @Test("ProviderType - defaultAuthMethod 매핑")
    func providerTypeDefaultAuthMethod() {
        #expect(ProviderType.claudeCode.defaultAuthMethod == .none)
        #expect(ProviderType.openAI.defaultAuthMethod == .apiKey)
        #expect(ProviderType.anthropic.defaultAuthMethod == .apiKey)
        #expect(ProviderType.google.defaultAuthMethod == .apiKey)
        #expect(ProviderType.ollama.defaultAuthMethod == .none)
        #expect(ProviderType.lmStudio.defaultAuthMethod == .none)
        #expect(ProviderType.custom.defaultAuthMethod == .none)
    }

    @Test("ProviderType - defaultLightModelName 매핑")
    func providerTypeDefaultLightModelName() {
        #expect(ProviderType.openAI.defaultLightModelName == "gpt-4o-mini")
        #expect(ProviderType.google.defaultLightModelName == "gemini-2.0-flash")
        #expect(ProviderType.anthropic.defaultLightModelName == "claude-haiku-4-5")
        #expect(ProviderType.claudeCode.defaultLightModelName == "claude-haiku-4-5")
        #expect(ProviderType.ollama.defaultLightModelName == nil)
        #expect(ProviderType.lmStudio.defaultLightModelName == nil)
        #expect(ProviderType.custom.defaultLightModelName == nil)
    }

    @Test("ProviderType - label 비어있지 않은 문자열")
    func providerTypeLabels() {
        for type in ProviderType.allCases {
            #expect(!type.label.isEmpty)
        }
    }

    // MARK: - ProviderConfig Codable

    @Test("ProviderConfig - Codable 왕복 (apiKey 제외)")
    func providerConfigCodableRoundtrip() throws {
        let id = UUID()
        let config = ProviderConfig(
            id: id,
            name: "테스트 프로바이더",
            type: .openAI,
            baseURL: "https://api.openai.com",
            authMethod: .apiKey,
            customHeaderName: "X-Custom",
            customHeaderValue: "value123",
            isBuiltIn: true
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.name == "테스트 프로바이더")
        #expect(decoded.type == .openAI)
        #expect(decoded.baseURL == "https://api.openai.com")
        #expect(decoded.authMethod == .apiKey)
        #expect(decoded.customHeaderName == "X-Custom")
        #expect(decoded.customHeaderValue == "value123")
        #expect(decoded.isBuiltIn == true)
    }

    @Test("ProviderConfig - 레거시 JSON(authMethod 없음) 디코딩 시 type에서 추론")
    func providerConfigLegacyDecodeInfersAuthMethod() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "name": "Legacy OpenAI",
            "type": "OpenAI",
            "baseURL": "https://api.openai.com",
            "isBuiltIn": false
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.name == "Legacy OpenAI")
        #expect(decoded.type == .openAI)
        #expect(decoded.authMethod == .apiKey) // type.defaultAuthMethod
    }

    @Test("ProviderConfig - 레거시 JSON(.ollama) authMethod 없음 → .none 추론")
    func providerConfigLegacyDecodeOllama() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "name": "Legacy Ollama",
            "type": "Ollama",
            "baseURL": "http://localhost:11434",
            "isBuiltIn": false
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: data)

        #expect(decoded.authMethod == .none) // type.defaultAuthMethod
    }

    @Test("ProviderConfig - 레거시 JSON(isBuiltIn 없음) 디코딩 시 기본값 false")
    func providerConfigLegacyDecodeIsBuiltIn() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "name": "Minimal",
            "type": "Custom",
            "baseURL": ""
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: data)

        #expect(decoded.isBuiltIn == false)
    }

    // MARK: - ProviderType rawValue

    @Test("ProviderType - rawValue 왕복")
    func providerTypeRawValueRoundtrip() {
        for type in ProviderType.allCases {
            let raw = type.rawValue
            #expect(ProviderType(rawValue: raw) == type)
        }
    }

    @Test("ProviderType - Codable 왕복")
    func providerTypeCodable() throws {
        for type in ProviderType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(ProviderType.self, from: data)
            #expect(decoded == type)
        }
    }

    // MARK: - ProviderConfig 기본값

    @Test("ProviderConfig - 기본값 확인 (authMethod=.none, isBuiltIn=false)")
    func providerConfigDefaults() throws {
        let config = ProviderConfig(
            name: "기본값 테스트",
            type: .custom,
            baseURL: ""
        )

        #expect(config.authMethod == .none)
        #expect(config.isBuiltIn == false)
        #expect(config.customHeaderName == nil)
        #expect(config.customHeaderValue == nil)
    }
}
