import Foundation

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var detectedProviders: [DetectedProvider] = []
    @Published var allProviderTypes: [ProviderType] = []  // 감지 + 미감지 전체
    @Published var selectedTypes: Set<ProviderType> = []
    @Published var masterProviderType: ProviderType?
    @Published var apiKeys: [ProviderType: String] = [:]   // 사용자 입력 or 환경변수
    @Published var useDetectedKey: [ProviderType: Bool] = [:] // 환경변수 키 사용 여부
    @Published var isDetecting = true
    @Published var currentStep: OnboardingStep = .detecting

    enum OnboardingStep {
        case detecting
        case selection
        case apiKeyInput
        case complete
    }

    // MARK: - 온보딩 완료 플래그

    static var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "onboardingCompleted") }
        set { UserDefaults.standard.set(newValue, forKey: "onboardingCompleted") }
    }

    // MARK: - 마스터 우선순위

    private static let masterPriority: [ProviderType] = [
        .claudeCode, .anthropic, .openAI, .google, .ollama, .lmStudio
    ]

    // MARK: - 감지 시작

    func startDetection() async {
        isDetecting = true
        let detected = await ProviderDetector.detectAll()
        detectedProviders = detected

        // 감지된 것 자동 선택
        selectedTypes = Set(detected.map(\.type))

        // 환경변수로 감지된 API 키 자동 채움
        for provider in detected {
            if let key = provider.prefilledAPIKey {
                apiKeys[provider.type] = key
                useDetectedKey[provider.type] = true
            }
        }

        // 전체 프로바이더 목록 (감지된 것 먼저, 나머지 뒤에)
        let detectedTypes = Set(detected.map(\.type))
        let undetectedTypes: [ProviderType] = [.claudeCode, .openAI, .anthropic, .google, .ollama, .lmStudio]
            .filter { !detectedTypes.contains($0) }
        allProviderTypes = detected.map(\.type) + undetectedTypes

        // 마스터 자동 선택
        masterProviderType = Self.masterPriority.first { selectedTypes.contains($0) }

        isDetecting = false
        currentStep = .selection
    }

    // MARK: - 선택 토글

    func toggleProvider(_ type: ProviderType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
            // 마스터가 해제되면 다음 후보로
            if masterProviderType == type {
                masterProviderType = Self.masterPriority.first { selectedTypes.contains($0) }
            }
        } else {
            selectedTypes.insert(type)
            // 마스터가 없으면 자동 설정
            if masterProviderType == nil {
                masterProviderType = type
            }
        }
    }

    func setMaster(_ type: ProviderType) {
        if !selectedTypes.contains(type) {
            selectedTypes.insert(type)
        }
        masterProviderType = type
    }

    // MARK: - API 키가 필요한 선택된 프로바이더

    var selectedProvidersNeedingKey: [ProviderType] {
        selectedTypes.filter { type in
            type.defaultAuthMethod == .apiKey
        }.sorted { a, b in
            allProviderTypes.firstIndex(of: a) ?? 0 < allProviderTypes.firstIndex(of: b) ?? 0
        }
    }

    /// 키 불필요한 선택된 프로바이더
    var selectedProvidersNoKey: [ProviderType] {
        selectedTypes.filter { $0.defaultAuthMethod == .none }
    }

    // MARK: - 다음 단계

    func goToNext() {
        switch currentStep {
        case .detecting:
            currentStep = .selection
        case .selection:
            if selectedProvidersNeedingKey.isEmpty {
                currentStep = .complete
            } else {
                currentStep = .apiKeyInput
            }
        case .apiKeyInput:
            currentStep = .complete
        case .complete:
            break
        }
    }

    func goBack() {
        switch currentStep {
        case .apiKeyInput:
            currentStep = .selection
        default:
            break
        }
    }

    // MARK: - 최종 적용

    func apply(providerManager: ProviderManager, agentStore: AgentStore) {
        // 1. 선택된 프로바이더 설정
        providerManager.configureFromOnboarding(
            selectedTypes: Array(selectedTypes),
            apiKeys: apiKeys
        )

        // 2. 마스터/DevAgent 프로바이더 업데이트
        if let masterType = masterProviderType,
           let config = providerManager.configs.first(where: { $0.type == masterType }) {
            let defaultModel = defaultModelName(for: masterType)
            agentStore.updateMasterProvider(providerName: config.name, modelName: defaultModel)
        }

        // 3. 온보딩 완료 플래그
        Self.isCompleted = true
    }

    /// 프로바이더 타입별 기본 모델명
    private func defaultModelName(for type: ProviderType) -> String {
        switch type {
        case .claudeCode: return "claude-sonnet-4-6"
        case .anthropic:  return "claude-sonnet-4-6"
        case .openAI:     return "gpt-4o"
        case .google:     return "gemini-2.0-flash"
        case .ollama:     return "llama3"
        case .lmStudio:   return "default"
        case .custom:     return "default"
        }
    }

    // MARK: - "나중에 설정" (스킵)

    func skipOnboarding() {
        Self.isCompleted = true
    }
}
