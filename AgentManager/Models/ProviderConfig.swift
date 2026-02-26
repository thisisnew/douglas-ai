import Foundation

/// 인증 방식
enum AuthMethod: String, Codable, CaseIterable {
    case none           = "없음 (로컬)"
    case apiKey         = "API Key"
    case bearerToken    = "Bearer Token"
    case customHeader   = "커스텀 헤더"

    var description: String {
        switch self {
        case .none:         return "인증 없이 접속 (Ollama, LM Studio 등 로컬 모델)"
        case .apiKey:       return "API Key 사용 (OpenAI, Anthropic, Google 등)"
        case .bearerToken:  return "Bearer Token 사용 (OAuth, JWT 등)"
        case .customHeader: return "커스텀 HTTP 헤더로 인증"
        }
    }
}

struct ProviderConfig: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: ProviderType
    var baseURL: String
    var authMethod: AuthMethod
    var customHeaderName: String?
    var customHeaderValue: String?
    var isBuiltIn: Bool

    // apiKey는 Keychain에 저장 (Codable에서 제외)
    var apiKey: String? {
        get { try? KeychainHelper.load(key: keychainKey) }
        set {
            if let value = newValue, !value.isEmpty {
                _ = try? KeychainHelper.save(key: keychainKey, value: value)
            } else {
                _ = try? KeychainHelper.delete(key: keychainKey)
            }
        }
    }

    private var keychainKey: String {
        "provider-apikey-\(id.uuidString)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, baseURL, authMethod
        case customHeaderName, customHeaderValue, isBuiltIn
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: ProviderType,
        baseURL: String,
        authMethod: AuthMethod = .none,
        apiKey: String? = nil,
        customHeaderName: String? = nil,
        customHeaderValue: String? = nil,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.baseURL = baseURL
        self.authMethod = authMethod
        self.customHeaderName = customHeaderName
        self.customHeaderValue = customHeaderValue
        self.isBuiltIn = isBuiltIn
        // apiKey는 init 후 Keychain에 저장
        if let apiKey, !apiKey.isEmpty {
            _ = try? KeychainHelper.save(key: "provider-apikey-\(id.uuidString)", value: apiKey)
        }
    }

    // 이전 버전 데이터와 호환: authMethod가 없으면 type에서 추론
    // UserDefaults에 저장된 레거시 apiKey가 있으면 Keychain으로 마이그레이션
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(ProviderType.self, forKey: .type)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        authMethod = try container.decodeIfPresent(AuthMethod.self, forKey: .authMethod) ?? type.defaultAuthMethod
        customHeaderName = try container.decodeIfPresent(String.self, forKey: .customHeaderName)
        customHeaderValue = try container.decodeIfPresent(String.self, forKey: .customHeaderValue)
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false

        // 레거시: UserDefaults에 apiKey가 남아 있으면 Keychain으로 마이그레이션
        // CodingKeys에 apiKey가 없으므로 별도 컨테이너로 시도
        struct LegacyKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
        }
        if let legacyContainer = try? decoder.container(keyedBy: LegacyKeys.self),
           let legacyKey = LegacyKeys(stringValue: "apiKey"),
           let legacyApiKey = try? legacyContainer.decodeIfPresent(String.self, forKey: legacyKey),
           !legacyApiKey.isEmpty,
           (try? KeychainHelper.load(key: "provider-apikey-\(id.uuidString)")) == nil {
            _ = try? KeychainHelper.save(key: "provider-apikey-\(id.uuidString)", value: legacyApiKey)
        }
    }
}

enum ProviderType: String, Codable, CaseIterable {
    case claudeCode = "Claude Code"
    case ollama     = "Ollama"
    case lmStudio   = "LM Studio"
    case openAI     = "OpenAI"
    case anthropic  = "Anthropic"
    case google     = "Google"
    case custom     = "Custom"

    var defaultBaseURL: String {
        switch self {
        case .claudeCode: return ClaudeCodeProvider.findClaudePath()
        case .ollama:     return "http://localhost:11434"
        case .lmStudio:   return "http://localhost:1234"
        case .openAI:     return "https://api.openai.com"
        case .anthropic:  return "https://api.anthropic.com"
        case .google:     return "https://generativelanguage.googleapis.com"
        case .custom:     return ""
        }
    }

    var defaultAuthMethod: AuthMethod {
        switch self {
        case .claudeCode:        return .none   // 키 불필요!
        case .ollama, .lmStudio: return .none
        case .openAI, .google:   return .apiKey
        case .anthropic:         return .apiKey
        case .custom:            return .none
        }
    }

    var label: String {
        switch self {
        case .claudeCode: return "Claude Code (설치됨, 키 불필요)"
        case .ollama:     return "Ollama (로컬, 무료)"
        case .lmStudio:   return "LM Studio (로컬, 무료)"
        case .openAI:     return "OpenAI (API Key)"
        case .anthropic:  return "Anthropic (API Key)"
        case .google:     return "Google Gemini (API Key)"
        case .custom:     return "커스텀 URL"
        }
    }
}

// MARK: - 연결 상태 확인

extension ProviderConfig {
    /// 이 프로바이더가 실제 사용 가능한 상태인지
    var isConnected: Bool {
        switch type {
        case .claudeCode:
            return FileManager.default.isExecutableFile(atPath: baseURL)
        case .ollama, .lmStudio:
            return true
        case .openAI, .anthropic, .google:
            return apiKey != nil && !(apiKey?.isEmpty ?? true)
        case .custom:
            return !baseURL.isEmpty
        }
    }
}
