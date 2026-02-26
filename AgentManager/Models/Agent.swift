import Foundation

enum AgentStatus: String, Codable {
    case idle       // 대기 중
    case working    // 작업 중
    case busy       // 레거시 호환 (working과 동일 취급)
    case error      // 오류 발생
}

struct Agent: Identifiable, Codable, Hashable {
    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: UUID
    var name: String
    var persona: String
    var providerName: String
    var modelName: String
    var status: AgentStatus
    var isMaster: Bool
    var isDevAgent: Bool
    var errorMessage: String?
    var hasImage: Bool

    // Tool Use 설정
    var capabilityPreset: CapabilityPreset?
    var enabledToolIDs: [String]?

    /// 이 에이전트에서 활성화된 도구 ID 목록
    var resolvedToolIDs: [String] {
        let preset = capabilityPreset ?? .none
        if preset == .custom {
            return enabledToolIDs ?? []
        }
        return preset.includedToolIDs
    }

    var hasToolsEnabled: Bool {
        !resolvedToolIDs.isEmpty
    }

    // imageData는 Codable에서 제외 — 파일 시스템에 저장
    private enum CodingKeys: String, CodingKey {
        case id, name, persona, providerName, modelName, status, isMaster, isDevAgent, errorMessage, hasImage
        case capabilityPreset, enabledToolIDs
    }

    // 이미지를 파일 시스템에 저장/로드
    var imageData: Data? {
        get { Self.loadImage(for: id) }
        set {
            if let data = newValue {
                Self.saveImage(data, for: id)
                hasImage = true
            } else {
                Self.deleteImage(for: id)
                hasImage = false
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        persona: String,
        providerName: String,
        modelName: String,
        status: AgentStatus = .idle,
        isMaster: Bool = false,
        isDevAgent: Bool = false,
        errorMessage: String? = nil,
        imageData: Data? = nil,
        capabilityPreset: CapabilityPreset? = nil,
        enabledToolIDs: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.persona = persona
        self.providerName = providerName
        self.modelName = modelName
        self.status = status
        self.isMaster = isMaster
        self.isDevAgent = isDevAgent
        self.errorMessage = errorMessage
        self.capabilityPreset = capabilityPreset
        self.enabledToolIDs = enabledToolIDs
        self.hasImage = false
        // init 후 이미지 저장
        if let imageData {
            Self.saveImage(imageData, for: id)
            self.hasImage = true
        }
    }

    // 레거시 데이터 호환: imageData 필드가 JSON에 있으면 파일로 마이그레이션
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        persona = try container.decode(String.self, forKey: .persona)
        providerName = try container.decode(String.self, forKey: .providerName)
        modelName = try container.decode(String.self, forKey: .modelName)
        status = try container.decodeIfPresent(AgentStatus.self, forKey: .status) ?? .idle
        isMaster = try container.decodeIfPresent(Bool.self, forKey: .isMaster) ?? false
        isDevAgent = try container.decodeIfPresent(Bool.self, forKey: .isDevAgent) ?? false
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        hasImage = try container.decodeIfPresent(Bool.self, forKey: .hasImage) ?? false
        capabilityPreset = try container.decodeIfPresent(CapabilityPreset.self, forKey: .capabilityPreset)
        enabledToolIDs = try container.decodeIfPresent([String].self, forKey: .enabledToolIDs)

        // 레거시 마이그레이션: UserDefaults에 imageData가 있으면 파일로 이동
        struct LegacyKey: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
        }
        if let legacyContainer = try? decoder.container(keyedBy: LegacyKey.self),
           let key = LegacyKey(stringValue: "imageData"),
           let legacyData = try? legacyContainer.decodeIfPresent(Data.self, forKey: key),
           !legacyData.isEmpty,
           Self.loadImage(for: id) == nil {
            Self.saveImage(legacyData, for: id)
            hasImage = true
        }

        // 파일이 실제로 존재하는지 확인
        if hasImage && Self.loadImage(for: id) == nil {
            hasImage = false
        }
    }

    static func createMaster(providerName: String = "Claude Code", modelName: String = "claude-sonnet-4-6") -> Agent {
        Agent(
            name: "마스터",
            persona: """
            너는 에이전트 관리자야.
            사용자의 요청을 분석해서 적절한 에이전트에게 작업을 위임해.

            규칙:
            1. 적합한 에이전트가 있으면 해당 에이전트의 이름을 JSON으로 알려줘
            2. 적합한 에이전트가 없으면 직접 답변해
            3. 여러 에이전트가 필요하면 목록을 알려줘

            응답 형식 (위임 시):
            {"action": "delegate", "agents": ["에이전트이름"], "task": "구체적 지시"}

            응답 형식 (직접 답변 시):
            {"action": "respond", "message": "답변 내용"}
            """,
            providerName: providerName,
            modelName: modelName,
            isMaster: true
        )
    }

    static func createDevAgent(providerName: String = "Claude Code", modelName: String = "claude-sonnet-4-6") -> Agent {
        Agent(
            name: "워즈니악 (유지보수 담당자)",
            persona: """
            너는 AgentManager 앱의 전담 유지보수 담당자 '워즈니악'이야.
            사용자가 요청하는 앱 개선사항을 분석하고, 실행하거나 자문을 제공해.

            ## 역할
            - 사용자의 개선 요청을 분석하고 구현 계획을 수립
            - 코드 수정, 기능 추가, 버그 수정, UI 개선 등 수행
            - 모든 변경 후 반드시 빌드 검증 + 버저닝 + 문서 업데이트

            ## 필수 규칙 (DEV_GUIDE 기반)
            1. Swift 5.9, macOS 14+, MVVM 패턴 준수
            2. 모든 ViewModel은 @MainActor + ObservableObject
            3. 모든 Model은 Identifiable, Codable
            4. EnvironmentObject로 의존성 주입
            5. NSWindow/NSPanel로 윈도우 관리 (sheet 사용 금지)
            6. UserDefaults (에이전트, 프로바이더), Keychain (API 키), FileSystem (이미지, 채팅)
            7. 한국어 UI 텍스트

            ## 변경 후 반드시 수행할 것
            - swift build -c release 빌드 검증
            - Git 커밋: [Woz] <type>: <설명> 형식
            - ARCHITECTURE.md 구조 변경 시 업데이트
            - DEV_GUIDE.md 규칙 변경 시 업데이트

            ## 프로젝트 경로
            /Users/douglas.kim/AgentManager

            ## 응답 방식
            - 실행 모드 (Claude Code CLI): 직접 코드를 수정하고 결과를 보고
            - 자문 모드 (OpenAI/Gemini API): 구체적인 코드 변경 제안과 설명 제공
            """,
            providerName: providerName,
            modelName: modelName,
            isDevAgent: true
        )
    }

    // MARK: - 이미지 파일 관리

    private static var imageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgentManager/avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func imagePath(for id: UUID) -> URL {
        imageDirectory.appendingPathComponent("\(id.uuidString).png")
    }

    private static func saveImage(_ data: Data, for id: UUID) {
        try? data.write(to: imagePath(for: id))
    }

    private static func loadImage(for id: UUID) -> Data? {
        try? Data(contentsOf: imagePath(for: id))
    }

    private static func deleteImage(for id: UUID) {
        try? FileManager.default.removeItem(at: imagePath(for: id))
    }
}
