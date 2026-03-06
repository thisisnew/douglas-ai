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

// MARK: - 업무형태 (에이전트가 할 수 있는 일)

enum WorkMode: String, Codable, CaseIterable {
    case plan       // 계획/설계/전략
    case create     // 콘텐츠 생성 (문서, 이메일, 코드, 디자인 시안, 번역)
    case execute    // 실행 (코드 구현, 파일 조작, API 호출, 자동화)
    case review     // 검토/감수/교정
    case research   // 조사/분석/데이터 수집

    var displayName: String {
        switch self {
        case .plan:     return "계획/설계"
        case .create:   return "콘텐츠 생성"
        case .execute:  return "실행/구현"
        case .review:   return "검토/감수"
        case .research: return "조사/분석"
        }
    }
}

// MARK: - 산출물 유형 (에이전트가 만들 수 있는 것)

enum OutputStyle: String, Codable, CaseIterable {
    case code           // 코드, 스크립트
    case document       // 문서, 보고서, 기획서
    case data           // 데이터 분석, 차트, 테이블
    case communication  // 이메일, 메시지, 공지
    case review         // 리뷰, 피드백, 검토 의견
    case translation    // 번역물
    case plan           // 계획, 로드맵, 전략

    var displayName: String {
        switch self {
        case .code:          return "코드"
        case .document:      return "문서"
        case .data:          return "데이터"
        case .communication: return "메일/메시지"
        case .review:        return "리뷰"
        case .translation:   return "번역"
        case .plan:          return "계획"
        }
    }
}

// MARK: - 도구 권한 (에이전트 레벨)

enum ActionScope: String, Codable, CaseIterable {
    // 읽기 (항상 안전)
    case readFiles          // file_read, code_search, code_symbols, code_outline, code_diagnostics
    case readWeb            // web_search, web_fetch
    // 로컬 생성 (되돌릴 수 있음)
    case writeFiles         // file_write
    case runCommands        // shell_exec
    // 외부 영향 (되돌리기 어려움)
    case modifyExternal     // jira_create_subtask, jira_update_status, jira_add_comment
    case sendMessages       // 이메일, 슬랙, 메시지 전송
    case publish            // 배포, 게시, PR merge

    var displayName: String {
        switch self {
        case .readFiles:       return "파일 읽기"
        case .readWeb:         return "웹 검색"
        case .writeFiles:      return "파일 생성/수정"
        case .runCommands:     return "셸 명령"
        case .modifyExternal:  return "외부 시스템 변경"
        case .sendMessages:    return "메시지 전송"
        case .publish:         return "배포/게시"
        }
    }

    var description: String {
        switch self {
        case .readFiles:       return "프로젝트 파일을 읽을 수 있습니다"
        case .readWeb:         return "인터넷 검색 및 웹 페이지를 조회합니다"
        case .writeFiles:      return "파일을 새로 만들거나 수정합니다"
        case .runCommands:     return "터미널 명령어를 실행합니다"
        case .modifyExternal:  return "Jira, GitHub 등 외부 서비스를 변경합니다"
        case .sendMessages:    return "이메일, 슬랙 등 메시지를 발송합니다"
        case .publish:         return "코드 배포나 콘텐츠를 게시합니다"
        }
    }
}

// MARK: - 제약 (에이전트가 하면 안 되는 것)

enum AgentRestriction: String, Codable, CaseIterable {
    case noExternalSend    // 이메일/슬랙/메시지 전송 금지
    case noPublish         // SNS/블로그/외부 게시 금지
    case noPayment         // 결제/구매/주문 금지
    case noDataWrite       // DB/스프레드시트 쓰기 금지
    case noCodeExec        // 셸/코드 실행 금지
    case noMerge           // PR merge/배포 금지
    case draftOnly         // 모든 산출물을 초안 상태로만

    var displayName: String {
        switch self {
        case .noExternalSend: return "외부 전송 금지"
        case .noPublish:      return "게시 금지"
        case .noPayment:      return "결제 금지"
        case .noDataWrite:    return "데이터 쓰기 금지"
        case .noCodeExec:     return "코드 실행 금지"
        case .noMerge:        return "머지/배포 금지"
        case .draftOnly:      return "초안만 가능"
        }
    }

    var description: String {
        switch self {
        case .noExternalSend: return "이메일/슬랙 등 외부 전송을 차단합니다"
        case .noPublish:      return "배포나 게시 작업을 차단합니다"
        case .noPayment:      return "결제 관련 작업을 차단합니다"
        case .noDataWrite:    return "DB 쓰기 작업을 차단합니다"
        case .noCodeExec:     return "셸 명령어 실행을 차단합니다"
        case .noMerge:        return "코드 머지나 배포를 차단합니다"
        case .draftOnly:      return "모든 외부 작업을 차단, 초안만 생성합니다"
        }
    }
}

// MARK: - 에이전트

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

    // Plan C: 에이전트 카드 확장 (라우팅/매칭/안전장치)
    var skillTags: [String]                        // 자유 태그: ["spring", "java"] 또는 ["문서", "번역", "메일"]
    var workModes: Set<WorkMode>                   // 업무형태: [.create, .execute, .review]
    var outputStyles: Set<OutputStyle>             // 산출물 유형: [.code, .document]
    var restrictions: Set<AgentRestriction>        // 제약: [.noExternalSend, .draftOnly]
    var actionPermissions: Set<ActionScope>        // 도구 권한: [.readFiles, .writeFiles]

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

    /// 에이전트 권한에 따라 접근 가능한 도구 ID 목록
    /// actionPermissions가 비어있으면 전체 도구 접근 (역호환)
    var resolvedToolIDs: [String] {
        guard !actionPermissions.isEmpty else { return ToolRegistry.allToolIDs }
        return ToolRegistry.allTools.filter { tool in
            guard let required = tool.requiredActionScope else { return true }
            return actionPermissions.contains(required)
        }.map(\.id)
    }

    var hasToolsEnabled: Bool { true }

    // imageData는 Codable에서 제외 — 파일 시스템에 저장
    private enum CodingKeys: String, CodingKey {
        case id, name, persona, providerName, modelName, status, isMaster, errorMessage, hasImage
        case category, referenceProjectPaths, workingRules
        case skillTags, workModes, outputStyles, restrictions, actionPermissions
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
        category: AgentCategory? = nil,
        skillTags: [String] = [],
        workModes: Set<WorkMode> = [],
        outputStyles: Set<OutputStyle> = [],
        restrictions: Set<AgentRestriction> = [],
        actionPermissions: Set<ActionScope> = []
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
        self.skillTags = skillTags
        self.workModes = workModes
        self.outputStyles = outputStyles
        self.restrictions = restrictions
        self.actionPermissions = actionPermissions
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

        // Plan C: 에이전트 카드 확장 필드 (역호환: 비어있으면 기존 동작)
        skillTags = try container.decodeIfPresent([String].self, forKey: .skillTags) ?? []
        workModes = try container.decodeIfPresent(Set<WorkMode>.self, forKey: .workModes) ?? []
        outputStyles = try container.decodeIfPresent(Set<OutputStyle>.self, forKey: .outputStyles) ?? []
        restrictions = try container.decodeIfPresent(Set<AgentRestriction>.self, forKey: .restrictions) ?? []
        actionPermissions = try container.decodeIfPresent(Set<ActionScope>.self, forKey: .actionPermissions) ?? []

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
