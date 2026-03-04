import Foundation

@MainActor
class ProviderManager: ObservableObject {
    @Published var configs: [ProviderConfig] = []

    private let saveKey = "providerConfigs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadConfigs()
        ensureDefaultProviders()
    }

    /// 온보딩에서 선택한 프로바이더들로 설정
    func configureFromOnboarding(selectedTypes: [ProviderType], apiKeys: [ProviderType: String]) {
        for type in selectedTypes {
            // 이미 존재하면 스킵
            if configs.contains(where: { $0.type == type }) {
                // API 키만 업데이트
                if let key = apiKeys[type], !key.isEmpty,
                   let idx = configs.firstIndex(where: { $0.type == type }) {
                    var config = configs[idx]
                    config.apiKey = key
                    configs[idx] = config
                }
                continue
            }

            let baseURL: String
            if type == .claudeCode {
                baseURL = ClaudeCodeProvider.findClaudePath()
            } else {
                baseURL = type.defaultBaseURL
            }

            let config = ProviderConfig(
                name: type.rawValue,
                type: type,
                baseURL: baseURL,
                authMethod: type.defaultAuthMethod,
                apiKey: apiKeys[type],
                isBuiltIn: true
            )
            configs.append(config)
        }
        saveConfigs()
    }

    /// 3개 기본 프로바이더 보장: Claude Code, OpenAI, Google
    private func ensureDefaultProviders() {
        // 온보딩 완료 전이면 기본 프로바이더 생성하지 않음
        guard OnboardingViewModel.isCompleted else { return }
        // Claude Code
        if !configs.contains(where: { $0.type == .claudeCode }) {
            let claudePath = ClaudeCodeProvider.findClaudePath()
            if FileManager.default.isExecutableFile(atPath: claudePath) {
                configs.append(ProviderConfig(
                    name: "Claude Code",
                    type: .claudeCode,
                    baseURL: claudePath,
                    authMethod: .none,
                    isBuiltIn: true
                ))
            }
        }

        // OpenAI (GPT)
        if !configs.contains(where: { $0.type == .openAI }) {
            configs.append(ProviderConfig(
                name: "OpenAI",
                type: .openAI,
                baseURL: ProviderType.openAI.defaultBaseURL,
                authMethod: .apiKey,
                isBuiltIn: true
            ))
        }

        // Google (Gemini)
        if !configs.contains(where: { $0.type == .google }) {
            configs.append(ProviderConfig(
                name: "Google",
                type: .google,
                baseURL: ProviderType.google.defaultBaseURL,
                authMethod: .apiKey,
                isBuiltIn: true
            ))
        }

        saveConfigs()
    }

    /// 연결된(사용 가능한) 프로바이더 목록
    var connectedConfigs: [ProviderConfig] {
        configs.filter { $0.isConnected }
    }

    func updateConfig(_ updated: ProviderConfig) {
        if let idx = configs.firstIndex(where: { $0.id == updated.id }) {
            providerCache.removeValue(forKey: configs[idx].name)
            configs[idx] = updated
            saveConfigs()
        }
    }

    /// 테스트에서 MockAIProvider 주입용 (인스턴스별 격리)
    var testProviderOverrides: [String: AIProvider] = [:]

    /// Provider 인스턴스 캐시 (config 변경 시 invalidate)
    private var providerCache: [String: AIProvider] = [:]

    func provider(named name: String) -> AIProvider? {
        if let override = testProviderOverrides[name] {
            return override
        }
        if let cached = providerCache[name] {
            return cached
        }
        guard let config = configs.first(where: { $0.name == name }) else {
            return nil
        }
        let instance = createProvider(from: config)
        providerCache[name] = instance
        return instance
    }

    /// 경량 작업(분류, 라우팅, 브리핑)용 모델 이름 반환
    func lightModelName(for providerName: String) -> String? {
        guard let config = configs.first(where: { $0.name == providerName }) else { return nil }
        return config.type.defaultLightModelName
    }

    func createProvider(from config: ProviderConfig) -> AIProvider {
        switch config.type {
        case .claudeCode:  return ClaudeCodeProvider(config: config)
        case .openAI:      return OpenAIProvider(config: config)
        case .google:      return GoogleProvider(config: config)
        case .anthropic:   return AnthropicProvider(config: config)
        default:           return OpenAIProvider(config: config) // 미지원 타입 폴백
        }
    }

    func fetchModels(for providerName: String) async throws -> [String] {
        guard let p = provider(named: providerName) else {
            return []
        }
        return try await p.fetchModels()
    }

    // MARK: - 저장/불러오기

    private func saveConfigs() {
        if let data = try? JSONEncoder().encode(configs) {
            defaults.set(data, forKey: saveKey)
        }
    }

    /// 지원하는 프로바이더 타입
    private static let supportedTypes: Set<ProviderType> = [.claudeCode, .openAI, .anthropic, .google]

    private func loadConfigs() {
        guard let data = defaults.data(forKey: saveKey),
              let loaded = try? JSONDecoder().decode([ProviderConfig].self, from: data) else {
            return
        }
        // 미지원 타입(ollama, lmStudio, custom) 필터링
        configs = loaded.filter { Self.supportedTypes.contains($0.type) }
    }
}
