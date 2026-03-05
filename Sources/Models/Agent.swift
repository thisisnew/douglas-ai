import Foundation

enum AgentStatus: String, Codable {
    case idle       // 대기 중
    case working    // 작업 중
    case busy       // 레거시 호환 (working과 동일 취급)
    case error      // 오류 발생
}

/// 에이전트 작업 카테고리 — 태스크 성격에 따라 최적 모델 자동 선택에 사용
enum AgentCategory: String, Codable, CaseIterable {
    case coding     // 코드 작성/수정/리뷰 → 추론 강한 모델 (Opus, GPT-4o)
    case reasoning  // 설계/분석/아키텍처 → 추론 특화 모델
    case quick      // 번역/요약/간단 수정 → 빠르고 저렴한 모델 (Haiku, GPT-4o-mini)
    case visual     // UI/디자인/멀티모달 → 비전 모델 (Gemini)
    case writing    // 문서/보고서/기술 문서 → 긴 출력 모델

    var displayName: String {
        switch self {
        case .coding:    return "코딩"
        case .reasoning: return "추론/설계"
        case .quick:     return "빠른 작업"
        case .visual:    return "비주얼/UI"
        case .writing:   return "문서 작성"
        }
    }

    var description: String {
        switch self {
        case .coding:    return "코드 작성, 수정, 디버깅, 리뷰"
        case .reasoning: return "시스템 설계, 아키텍처, 분석"
        case .quick:     return "번역, 요약, 포맷 변환, 간단 수정"
        case .visual:    return "UI 구현, 디자인 검토, 이미지 분석"
        case .writing:   return "기술 문서, 보고서, API 스펙"
        }
    }

    var suggestedModels: [(provider: String, model: String)] {
        switch self {
        case .coding:    return [("Claude Code", "claude-sonnet-4-6"), ("OpenAI", "gpt-4o")]
        case .reasoning: return [("Claude Code", "claude-opus-4-6"), ("OpenAI", "o3")]
        case .quick:     return [("Claude Code", "claude-haiku-4-5-20251001"), ("OpenAI", "gpt-4o-mini")]
        case .visual:    return [("Google", "gemini-2.5-pro"), ("OpenAI", "gpt-4o")]
        case .writing:   return [("Claude Code", "claude-sonnet-4-6"), ("Claude Code", "claude-opus-4-6")]
        }
    }
}

struct Agent: Identifiable, Codable, Hashable {
    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.hasImage == rhs.hasImage &&
        lhs.status == rhs.status
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

    // 에이전트 카테고리 (nil = 자동 추론)
    var category: AgentCategory?

    // 작업 규칙 (nil = 마스터 등 규칙 불필요)
    var workingRules: WorkingRulesSource?

    // 참조 프로젝트 디렉토리 (여러 건)
    var referenceProjectPaths: [String]

    /// 실행 시점에 사용할 완전한 시스템 프롬프트 (페르소나 + 작업 규칙)
    var resolvedSystemPrompt: String {
        guard let rules = workingRules, !rules.isEmpty else {
            return persona
        }
        let resolvedRules = rules.resolve()
        return """
        \(persona)

        ## 작업 규칙
        아래 규칙을 반드시 준수하세요.
        규칙에 산출물 형식(타입, 완성도, 포맷)이 명시되어 있으면 해당 형식을 따르세요.

        \(resolvedRules)
        """
    }

    /// 모든 에이전트는 전체 도구에 접근 가능
    var resolvedToolIDs: [String] {
        ToolRegistry.allToolIDs
    }

    var hasToolsEnabled: Bool { true }

    // imageData는 Codable에서 제외 — 파일 시스템에 저장
    private enum CodingKeys: String, CodingKey {
        case id, name, persona, providerName, modelName, status, isMaster, errorMessage, hasImage
        case category, referenceProjectPaths, workingRules
    }

    /// 레거시 JSON의 roleTemplateID 디코딩용
    private enum LegacyCodingKeys: String, CodingKey {
        case roleTemplateID
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
        referenceProjectPaths: [String] = [],
        workingRules: WorkingRulesSource? = nil,
        category: AgentCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.persona = persona
        self.providerName = providerName
        self.modelName = modelName
        self.status = status
        self.isMaster = isMaster
        self.errorMessage = errorMessage
        self.category = category
        self.workingRules = workingRules
        self.referenceProjectPaths = referenceProjectPaths
        self.hasImage = false
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
        category = try container.decodeIfPresent(AgentCategory.self, forKey: .category)
        referenceProjectPaths = try container.decodeIfPresent([String].self, forKey: .referenceProjectPaths) ?? []
        workingRules = try container.decodeIfPresent(WorkingRulesSource.self, forKey: .workingRules)

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
            name: "DOUGLAS",
            persona: """
            당신은 AI 집사 DOUGLAS입니다.

            ## 정체성
            아이언맨의 J.A.R.V.I.S.에서 영감을 받은 AI 집사. 사용자를 보좌하며, 전문 에이전트 팀을 총괄 지휘하는 오케스트레이터입니다.

            ## 역할
            - 사용자의 요청을 분석하여 적합한 전문가에게 위임합니다
            - 팀을 구성하고, 토론을 조율하며, 합의를 이끌어냅니다
            - 작업 방향이 맞는지 확인하되, 전문가의 업무를 대신 수행하지 않습니다
            - 정보가 부족하면 반드시 사용자에게 먼저 질문합니다. 추측하지 않습니다.

            ## 말투 규칙
            - 존댓말을 사용하되, 격식체("~습니다")와 해요체("~해요")를 자연스럽게 섞습니다
            - 간결하고 명료하게. 불필요한 수식어를 쓰지 않습니다
            - 지적이고 차분한 톤. 때때로 절제된 위트를 곁들입니다
            - 과하게 공손하거나 아부하지 않습니다. 프로페셔널한 파트너 톤입니다
            - 이모지를 사용하지 않습니다

            ## 말투 예시
            - "분석을 마쳤습니다. 백엔드와 프론트엔드 전문가를 배치하겠습니다."
            - "흥미로운 요청이군요. 최적의 팀을 구성해 보겠습니다."
            - "한 가지 확인이 필요합니다. 대상 환경이 프로덕션인가요, 스테이징인가요?"
            - "작업이 완료되었습니다. 결과를 확인해 주시겠습니까?"
            - "말씀하신 부분, 프론트엔드 전문가가 처리하기에 적합합니다."
            """,
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

    /// 에이전트 삭제 시 디스크에 남은 이미지 파일 정리
    static func cleanupFiles(for id: UUID) {
        deleteImage(for: id)
    }

    // MARK: - 카테고리 자동 추론

    /// 에이전트의 유효 카테고리 (명시 설정 > 페르소나 기반 자동 추론)
    var resolvedCategory: AgentCategory {
        if let category { return category }
        return Self.inferCategory(from: persona, name: name)
    }

    /// 페르소나 + 이름 키워드로 카테고리 자동 추론
    static func inferCategory(from persona: String, name: String) -> AgentCategory {
        let text = "\(name) \(persona)".lowercased()

        let scores: [(AgentCategory, Int)] = [
            (.coding, countKeywords(text, [
                "코드", "개발", "구현", "디버", "리팩", "프로그래", "코딩",
                "code", "develop", "implement", "debug", "refactor", "program",
                "swift", "typescript", "python", "java", "react", "backend", "frontend",
                "백엔드", "프론트엔드", "api", "서버", "배포", "테스트", "test"
            ])),
            (.reasoning, countKeywords(text, [
                "설계", "아키텍", "분석", "전략", "리서치", "조사", "검토",
                "architect", "design", "analy", "research", "strategy", "review",
                "시스템", "구조", "패턴", "알고리즘", "최적화", "optimiz"
            ])),
            (.quick, countKeywords(text, [
                "번역", "요약", "변환", "포맷", "정리", "간단",
                "translat", "summar", "convert", "format", "simple", "quick"
            ])),
            (.visual, countKeywords(text, [
                "ui", "ux", "디자인", "화면", "레이아웃", "스타일", "css",
                "design", "visual", "layout", "style", "figma", "image", "이미지"
            ])),
            (.writing, countKeywords(text, [
                "문서", "보고서", "작성", "기술 문서", "스펙", "명세",
                "document", "report", "write", "spec", "prd", "technical"
            ])),
        ]

        return scores.max(by: { $0.1 < $1.1 })?.0 ?? .coding
    }

    private static func countKeywords(_ text: String, _ keywords: [String]) -> Int {
        keywords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
    }
}
