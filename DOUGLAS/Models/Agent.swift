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
        case id, name, persona, providerName, modelName, status, isMaster, errorMessage, hasImage
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
            persona: "사용자의 요청을 분석하여 적합한 에이전트에게 위임하는 라우터.",
            providerName: providerName,
            modelName: modelName,
            isMaster: true
        )
    }

    // MARK: - 이미지 파일 관리

    private static var imageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentmanager")
        let dir = appSupport.appendingPathComponent("DOUGLAS/avatars", isDirectory: true)
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
