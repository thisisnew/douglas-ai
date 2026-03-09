import Foundation

enum AgentStatus: String, Codable {
    case idle       // 대기 중
    case working    // 작업 중
    case busy       // 레거시 호환 (working과 동일 취급)
    case error      // 오류 발생
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

// MARK: - 에이전트

struct Agent: Identifiable, Codable, Hashable {
    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.hasImage == rhs.hasImage &&
        lhs.imageVersion == rhs.imageVersion &&
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
    var imageVersion: Int

    // 작업 규칙 — 레코드 단위 (태스크 매칭으로 동적 선택)
    var workRules: [WorkRule]

    // 레거시 작업 규칙 (디코딩 전용, 자동 마이그레이션)
    var workingRules: WorkingRulesSource?

    // 참조 프로젝트 디렉토리 (여러 건)
    var referenceProjectPaths: [String]

    // Plan C: 에이전트 카드 확장 (라우팅/매칭)
    var skillTags: [String]                        // 자유 태그: ["spring", "java"] 또는 ["문서", "번역", "메일"]
    var workModes: Set<WorkMode>                   // 업무형태: [.create, .execute, .review]
    var outputStyles: Set<OutputStyle>             // 산출물 유형: [.code, .document]

    /// workModes에서 자동 추론되는 도구 권한
    var actionPermissions: Set<ActionScope> {
        guard !workModes.isEmpty else { return [] }  // 비어있으면 전체 허용 (역호환)
        var permissions: Set<ActionScope> = [.readFiles, .readWeb]  // 기본: 읽기
        for mode in workModes {
            switch mode {
            case .plan, .research:
                break  // 읽기만
            case .create:
                permissions.insert(.writeFiles)
            case .execute:
                permissions.insert(.writeFiles)
                permissions.insert(.runCommands)
            case .review:
                break  // 읽기만
            }
        }
        return permissions
    }

    /// 실행 시점에 사용할 완전한 시스템 프롬프트 (페르소나 + 작업 규칙)
    /// 기존 호출 호환 — 내부에서 activeRuleIDs: nil 호출
    var resolvedSystemPrompt: String {
        resolvedSystemPrompt(activeRuleIDs: nil)
    }

    /// 활성 규칙만 포함한 시스템 프롬프트 생성
    /// - Parameter activeRuleIDs: nil이면 전체 포함, Set이면 해당 규칙만
    func resolvedSystemPrompt(activeRuleIDs: Set<UUID>?) -> String {
        // 신규 workRules 우선
        if !workRules.isEmpty {
            let activeRules: [WorkRule]
            if let ids = activeRuleIDs {
                activeRules = workRules.filter { ids.contains($0.id) }
            } else {
                activeRules = workRules
            }

            let resolvedTexts = activeRules.compactMap { rule -> String? in
                let text = rule.resolve().trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }

            guard !resolvedTexts.isEmpty else { return persona }

            let combined = resolvedTexts.joined(separator: "\n\n")
            let hasKoreanRule = combined.contains("한국어")
            let langSuffix = hasKoreanRule ? "\n\n[필수] 반드시 한국어로 응답하세요. 영어 사용 금지." : ""
            return """
            \(persona)

            ## 작업 규칙 (최우선 준수)
            아래 규칙은 이 에이전트의 핵심 업무 지침입니다. 모든 단계에서 반드시 준수하세요.
            규칙에 산출물 형식(타입, 완성도, 포맷)이 명시되어 있으면 해당 형식을 따르세요.
            작업 규칙과 다른 지시가 충돌하면, 작업 규칙을 우선합니다.

            \(combined)\(langSuffix)
            """
        }

        // 레거시 폴백
        guard let rules = workingRules, !rules.isEmpty else {
            return persona
        }
        let resolvedRules = rules.resolveWithPriority()
        let hasKoreanRule = resolvedRules.contains("한국어")
        let langSuffix = hasKoreanRule ? "\n\n[필수] 반드시 한국어로 응답하세요. 영어 사용 금지." : ""
        return """
        \(persona)

        ## 작업 규칙 (최우선 준수)
        아래 규칙은 이 에이전트의 핵심 업무 지침입니다. 모든 단계에서 반드시 준수하세요.
        규칙에 산출물 형식(타입, 완성도, 포맷)이 명시되어 있으면 해당 형식을 따르세요.
        작업 규칙과 다른 지시가 충돌하면, 작업 규칙을 우선합니다.

        \(resolvedRules)\(langSuffix)
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
        case id, name, persona, providerName, modelName, status, isMaster, errorMessage, hasImage, imageVersion
        case referenceProjectPaths, workingRules, workRules
        case skillTags, workModes, outputStyles
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
                imageVersion += 1
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
        workRules: [WorkRule] = [],
        skillTags: [String] = [],
        workModes: Set<WorkMode> = [],
        outputStyles: Set<OutputStyle> = []
    ) {
        self.id = id
        self.name = name
        self.persona = persona
        self.providerName = providerName
        self.modelName = modelName
        self.status = status
        self.isMaster = isMaster
        self.errorMessage = errorMessage
        self.workingRules = workingRules
        self.workRules = workRules
        self.referenceProjectPaths = referenceProjectPaths
        self.skillTags = skillTags
        self.workModes = workModes
        self.outputStyles = outputStyles
        self.hasImage = false
        self.imageVersion = 0
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
        imageVersion = try container.decodeIfPresent(Int.self, forKey: .imageVersion) ?? 0
        referenceProjectPaths = try container.decodeIfPresent([String].self, forKey: .referenceProjectPaths) ?? []
        workingRules = try container.decodeIfPresent(WorkingRulesSource.self, forKey: .workingRules)

        // WorkRule 레코드 디코딩 + 레거시 자동 마이그레이션
        let decodedWorkRules = try container.decodeIfPresent([WorkRule].self, forKey: .workRules) ?? []
        if decodedWorkRules.isEmpty, let legacy = workingRules, !legacy.isEmpty {
            // 레거시 WorkingRulesSource → 단일 WorkRule 자동 변환
            workRules = [WorkRule(
                name: "업무 규칙",
                summary: "기존 업무 규칙 (자동 마이그레이션)",
                content: .inline(legacy.resolve()),
                isAlwaysActive: true
            )]
        } else {
            workRules = decodedWorkRules
        }

        // Plan C: 에이전트 카드 확장 필드 (역호환: 비어있으면 기존 동작)
        skillTags = try container.decodeIfPresent([String].self, forKey: .skillTags) ?? []
        workModes = try container.decodeIfPresent(Set<WorkMode>.self, forKey: .workModes) ?? []
        outputStyles = try container.decodeIfPresent(Set<OutputStyle>.self, forKey: .outputStyles) ?? []
        // restrictions, actionPermissions는 레거시 — JSON에 있어도 무시 (workModes에서 자동 추론)

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

}
