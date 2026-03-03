import Foundation

// MARK: - 프로젝트 플레이북

/// 프로젝트별 개발 프로세스 정의 (브랜치 전략, 테스트 정책 등)
/// 저장 위치: {projectPath}/.douglas/playbook.json
struct ProjectPlaybook: Codable {
    // 사용자 프로필
    var userRole: UserRole?
    var defaultIntent: WorkflowIntent?

    // 브랜치 전략
    var branchPattern: String?        // "feature/{jira-key}-{desc}"
    var baseBranch: String?           // "develop"

    // 완료 후 행동
    var afterComplete: AfterComplete?

    // 개발 프로세스
    var testStrategy: String?         // "새 기능은 반드시 단위 테스트 포함"
    var codeReviewPolicy: String?     // "PR 필수, 리뷰어 1명"
    var deployProcess: String?        // "CI 통과 후 자동 배포"

    // 자유 형식 메모
    var notes: [String]

    // 1회성 예외 기록 (점진적 학습용)
    var overrides: [PlaybookOverride]

    init(
        userRole: UserRole? = nil,
        defaultIntent: WorkflowIntent? = nil,
        branchPattern: String? = nil,
        baseBranch: String? = nil,
        afterComplete: AfterComplete? = nil,
        testStrategy: String? = nil,
        codeReviewPolicy: String? = nil,
        deployProcess: String? = nil,
        notes: [String] = [],
        overrides: [PlaybookOverride] = []
    ) {
        self.userRole = userRole
        self.defaultIntent = defaultIntent
        self.branchPattern = branchPattern
        self.baseBranch = baseBranch
        self.afterComplete = afterComplete
        self.testStrategy = testStrategy
        self.codeReviewPolicy = codeReviewPolicy
        self.deployProcess = deployProcess
        self.notes = notes
        self.overrides = overrides
    }

    // MARK: - 프리셋

    /// 스타트업: 빠르게, main 직접
    static let startup = ProjectPlaybook(
        branchPattern: "feature/{desc}",
        baseBranch: "main",
        afterComplete: .commitOnly,
        testStrategy: "필수 아님",
        notes: ["빠른 배포 우선"]
    )

    /// 팀 개발: feature → PR → merge
    static let team = ProjectPlaybook(
        branchPattern: "feature/{jira-key}-{desc}",
        baseBranch: "develop",
        afterComplete: .createPR,
        testStrategy: "새 기능은 단위 테스트 포함",
        codeReviewPolicy: "PR 필수, 리뷰어 1명"
    )

    /// 엔터프라이즈: Gitflow
    static let enterprise = ProjectPlaybook(
        branchPattern: "feature/{jira-key}/{desc}",
        baseBranch: "develop",
        afterComplete: .createPR,
        testStrategy: "단위 + 통합 테스트 필수",
        codeReviewPolicy: "PR 필수, 리뷰어 2명, CI 통과",
        deployProcess: "release 브랜치 → QA → main 머지"
    )

    // MARK: - 에이전트 컨텍스트 주입

    /// 에이전트 시스템 프롬프트에 삽입할 컨텍스트 문자열
    func asContextString() -> String {
        var parts: [String] = ["[프로젝트 플레이북]"]
        if let branch = branchPattern { parts.append("- 브랜치: \(branch)") }
        if let base = baseBranch { parts.append("- 베이스 브랜치: \(base)") }
        if let after = afterComplete { parts.append("- 완료 후: \(after.displayName)") }
        if let test = testStrategy { parts.append("- 테스트: \(test)") }
        if let review = codeReviewPolicy { parts.append("- 코드 리뷰: \(review)") }
        if let deploy = deployProcess { parts.append("- 배포: \(deploy)") }
        for note in notes { parts.append("- 참고: \(note)") }
        return parts.joined(separator: "\n")
    }
}

// MARK: - 사용자 역할

enum UserRole: String, Codable, CaseIterable {
    case developer
    case planner
    case qa
    case pm

    var displayName: String {
        switch self {
        case .developer: return "개발자"
        case .planner:   return "기획자"
        case .qa:        return "QA"
        case .pm:        return "PM"
        }
    }

    /// 역할에 따른 기본 워크플로우 의도
    var defaultIntent: WorkflowIntent {
        switch self {
        case .developer: return .implementation
        case .planner:   return .research
        case .qa:        return .research
        case .pm:        return .research
        }
    }
}

// MARK: - 완료 후 행동

enum AfterComplete: String, Codable, CaseIterable {
    case createPR
    case directMerge
    case commitOnly

    var displayName: String {
        switch self {
        case .createPR:    return "PR 생성"
        case .directMerge: return "바로 머지"
        case .commitOnly:  return "커밋만"
        }
    }
}

// MARK: - 플레이북 예외 기록

/// 실행 중 플레이북과 다르게 진행된 기록 (점진적 학습용)
struct PlaybookOverride: Codable, Identifiable {
    let id: UUID
    let field: String           // 어떤 플레이북 필드가 오버라이드됐는지
    let originalValue: String?
    let overrideValue: String
    let reason: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        field: String,
        originalValue: String? = nil,
        overrideValue: String,
        reason: String = "",
        timestamp: Date = Date()
    ) {
        self.id = id
        self.field = field
        self.originalValue = originalValue
        self.overrideValue = overrideValue
        self.reason = reason
        self.timestamp = timestamp
    }
}

// MARK: - 플레이북 파일 I/O

enum PlaybookManager {
    private static let directoryName = ".douglas"
    private static let fileName = "playbook.json"

    /// 프로젝트 경로에서 플레이북 로드
    static func load(from projectPath: String) -> ProjectPlaybook? {
        let url = fileURL(for: projectPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProjectPlaybook.self, from: data)
    }

    /// 플레이북을 프로젝트 경로에 저장
    static func save(_ playbook: ProjectPlaybook, to projectPath: String) throws {
        let dirURL = URL(fileURLWithPath: projectPath).appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(playbook)
        try data.write(to: fileURL(for: projectPath))
    }

    /// 예외 기록 추가
    static func recordOverride(
        in playbook: inout ProjectPlaybook,
        field: String,
        originalValue: String?,
        overrideValue: String,
        reason: String
    ) {
        let override = PlaybookOverride(
            field: field,
            originalValue: originalValue,
            overrideValue: overrideValue,
            reason: reason
        )
        playbook.overrides.append(override)
    }

    /// 같은 필드가 N회 이상 오버라이드됐으면 영구 변경 제안
    static func pendingSuggestions(in playbook: ProjectPlaybook, threshold: Int = 3) -> [PlaybookOverride] {
        let grouped = Dictionary(grouping: playbook.overrides) { $0.field }
        return grouped.compactMap { _, overrides in
            overrides.count >= threshold ? overrides.last : nil
        }
    }

    private static func fileURL(for projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath)
            .appendingPathComponent(directoryName)
            .appendingPathComponent(fileName)
    }
}
