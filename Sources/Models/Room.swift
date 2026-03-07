import Foundation

// MARK: - Plan C: 리스크 레벨 (실행 단계 태그)

enum RiskLevel: String, Codable {
    case low      // 내부 작업: 초안 작성, 분석, 리서치, 요약, 로컬 파일 생성
    case medium   // 수정 가능한 외부 작업: Draft PR, 문서 초안, 임시 저장
    case high     // 되돌리기 어려운 외부 작업: 메일 전송, merge, 배포, 결제, DB 변경

    var displayName: String {
        switch self {
        case .low:    return "안전"
        case .medium: return "주의"
        case .high:   return "위험"
        }
    }
}

// MARK: - Plan C: 산출물 유형 (TaskBrief용)

enum OutputType: String, Codable {
    case code           // 코드/PR/커밋
    case document       // 문서/보고서/기획서
    case message        // 이메일/슬랙/메시지
    case analysis       // 분석 결과/리서치 요약
    case data           // 스프레드시트/DB 변경
    case design         // 디자인 시안/와이어프레임
    case answer         // 즉답 (quickAnswer)
}

// MARK: - Plan C: 런타임 역할 (작업마다 배정)

enum RuntimeRole: String, Codable {
    case creator    // 산출물을 만드는 역할
    case reviewer   // 산출물을 검토하는 역할
    case planner    // 3명+ 일 때 전체 설계를 잡는 역할

    var displayName: String {
        switch self {
        case .creator:  return "작성자"
        case .reviewer: return "검토자"
        case .planner:  return "설계자"
        }
    }
}

// MARK: - Plan C: TaskBrief (Understand 출력)

struct TaskBrief: Codable, Equatable {
    var goal: String              // "거래처 납기 지연 사과 메일 발송"
    var constraints: [String]     // ["격식체", "새 납기일: 3/20"]
    var successCriteria: [String] // ["사과 표현", "새 납기일 명시"]
    var nonGoals: [String]        // ["전체 공지 아님"]
    var overallRisk: RiskLevel    // .high (이메일 전송)
    var outputType: OutputType    // .message
    var needsClarification: Bool  // 정보 부족 시 true → 질문 1회 표시
    var questions: [String]       // needsClarification=true 시 질문 목록 (최대 2개)

    init(
        goal: String,
        constraints: [String] = [],
        successCriteria: [String] = [],
        nonGoals: [String] = [],
        overallRisk: RiskLevel = .low,
        outputType: OutputType = .answer,
        needsClarification: Bool = false,
        questions: [String] = []
    ) {
        self.goal = goal
        self.constraints = constraints
        self.successCriteria = successCriteria
        self.nonGoals = nonGoals
        self.overallRisk = overallRisk
        self.outputType = outputType
        self.needsClarification = needsClarification
        self.questions = questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goal = try container.decode(String.self, forKey: .goal)
        constraints = try container.decodeIfPresent([String].self, forKey: .constraints) ?? []
        successCriteria = try container.decodeIfPresent([String].self, forKey: .successCriteria) ?? []
        nonGoals = try container.decodeIfPresent([String].self, forKey: .nonGoals) ?? []
        overallRisk = try container.decodeIfPresent(RiskLevel.self, forKey: .overallRisk) ?? .low
        outputType = try container.decodeIfPresent(OutputType.self, forKey: .outputType) ?? .answer
        needsClarification = try container.decodeIfPresent(Bool.self, forKey: .needsClarification) ?? false
        questions = try container.decodeIfPresent([String].self, forKey: .questions) ?? []
    }
}

// MARK: - Plan C: DeferredAction (Build에서 Deliver로 넘기는 작업)

struct DeferredAction: Codable, Identifiable, Equatable {
    let id: UUID
    let toolName: String           // "shell_exec", 미래의 "email_send" 등
    let arguments: [String: ToolArgumentValue]
    let description: String        // "고객에게 사과 메일 전송"
    let riskLevel: RiskLevel       // .high
    let previewContent: String?    // Draft 프리뷰용 텍스트
    var status: DeferredStatus

    enum DeferredStatus: String, Codable {
        case pending    // 사용자 승인 대기
        case approved   // 승인됨 → 실행 예정
        case executed   // 실행 완료
        case cancelled  // 취소됨
    }

    init(
        id: UUID = UUID(),
        toolName: String,
        arguments: [String: ToolArgumentValue],
        description: String,
        riskLevel: RiskLevel = .high,
        previewContent: String? = nil,
        status: DeferredStatus = .pending
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.description = description
        self.riskLevel = riskLevel
        self.previewContent = previewContent
        self.status = status
    }
}

// MARK: - 위임 정보 (Clarify → Assemble 전달)

/// clarify 단계에서 LLM이 판단한 에이전트 위임 정보
struct DelegationInfo: Codable, Equatable {
    enum DelegationType: String, Codable {
        case explicit  // 사용자가 특정 에이전트를 지정
        case open      // 시스템이 판단 (기존 assemble 흐름)
    }
    let type: DelegationType
    let agentNames: [String]  // explicit일 때 지정된 에이전트 이름 목록
}

// MARK: - 토론 라운드 타입

/// 토론 라운드 타입 (Codable 호환 유지)
enum DiscussionRoundType: String, Codable {
    case diverge   // 발산: 각자 의견 자유 제시
    case converge  // 수렴: 반론/보완, 공통점 탐색
    case conclude  // 합의: 결론 도출
}

// MARK: - 방 모드

enum RoomMode: String, Codable {
    case task        // 기존 방식: 계획 → 단계별 실행
    case discussion  // 토론: 에이전트들이 순차적으로 의견 교환
}

// MARK: - 방 상태

enum RoomStatus: String, Codable {
    case planning           // 에이전트가 계획 수립 중
    case inProgress         // 타이머 진행 중 (작업 중)
    case awaitingApproval   // 승인 대기 (Human-in-the-loop)
    case awaitingUserInput  // 사용자 입력 대기 (ask_user 도구)
    case completed          // 작업 완료
    case failed             // 실패

    /// 허용된 상태 전이 검증
    func canTransition(to target: RoomStatus) -> Bool {
        switch (self, target) {
        case (.planning, .inProgress),
             (.planning, .completed),
             (.planning, .failed),
             (.planning, .awaitingApproval),
             (.planning, .awaitingUserInput),
             (.inProgress, .completed),
             (.inProgress, .failed),
             (.inProgress, .awaitingApproval),
             (.inProgress, .awaitingUserInput),
             (.awaitingApproval, .inProgress),
             (.awaitingApproval, .planning),
             (.awaitingApproval, .failed),
             (.awaitingApproval, .completed),
             (.awaitingUserInput, .planning),
             (.awaitingUserInput, .inProgress),
             (.awaitingUserInput, .completed),
             (.awaitingUserInput, .failed),
             (.completed, .inProgress),
             (.completed, .planning),
             (.failed, .inProgress),
             (.failed, .planning):
            return true
        default:
            return false
        }
    }
}

// MARK: - 방 생성자

enum RoomCreator: Codable, Equatable {
    case master(agentID: UUID)    // 마스터가 위임으로 생성
    case user                      // 사용자가 수동 생성
}

// MARK: - 작업 단계

/// 개별 실행 단계 (승인 게이트 + 에이전트 배정 지원)
/// 단계 실행 상태
enum StepStatus: String, Codable {
    case pending, inProgress, completed, skipped, failed
}

struct RoomStep: Codable, Equatable {
    let text: String
    let requiresApproval: Bool
    var assignedAgentID: UUID?
    var riskLevel: RiskLevel
    var status: StepStatus

    init(text: String, requiresApproval: Bool = false, assignedAgentID: UUID? = nil, riskLevel: RiskLevel = .low, status: StepStatus = .pending) {
        self.text = text
        self.requiresApproval = requiresApproval
        self.assignedAgentID = assignedAgentID
        self.riskLevel = riskLevel
        self.status = status
    }

    /// 커스텀 디코딩: plain String 또는 {"text":..., "requires_approval":...} 둘 다 지원
    init(from decoder: Decoder) throws {
        // 먼저 plain String 시도
        if let container = try? decoder.singleValueContainer(),
           let str = try? container.decode(String.self) {
            self.text = str
            self.requiresApproval = false
            self.assignedAgentID = nil
            self.riskLevel = .low
            self.status = .pending
            return
        }
        // object 형태
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
        self.assignedAgentID = try container.decodeIfPresent(UUID.self, forKey: .assignedAgentID)
        self.riskLevel = try container.decodeIfPresent(RiskLevel.self, forKey: .riskLevel) ?? .low
        self.status = try container.decodeIfPresent(StepStatus.self, forKey: .status) ?? .pending
    }

    func encode(to encoder: Encoder) throws {
        // 승인 불필요 + 배정 없으면 plain String으로 인코딩 (역호환)
        if !requiresApproval && assignedAgentID == nil && riskLevel == .low && status == .pending {
            var container = encoder.singleValueContainer()
            try container.encode(text)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encode(requiresApproval, forKey: .requiresApproval)
            try container.encodeIfPresent(assignedAgentID, forKey: .assignedAgentID)
            if riskLevel != .low {
                try container.encode(riskLevel, forKey: .riskLevel)
            }
            if status != .pending {
                try container.encode(status, forKey: .status)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case requiresApproval = "requires_approval"
        case assignedAgentID = "assigned_agent_id"
        case riskLevel = "risk_level"
        case status
    }
}

extension RoomStep: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.text = value
        self.requiresApproval = false
        self.riskLevel = .low
        self.status = .pending
    }
}

// MARK: - 에이전트 생성 제안

/// 에이전트 생성 제안 (분석가가 필요한 에이전트를 제안 → 사용자 승인)
struct RoomAgentSuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let persona: String
    let recommendedPreset: String?
    let recommendedProvider: String?
    let recommendedModel: String?
    let reason: String
    let suggestedBy: String       // 제안한 에이전트 이름
    let createdAt: Date
    var status: SuggestionStatus
    let skillTags: [String]?
    let outputStyles: Set<OutputStyle>?

    enum SuggestionStatus: String, Codable {
        case pending
        case approved
        case rejected
    }

    init(
        id: UUID = UUID(),
        name: String,
        persona: String,
        recommendedPreset: String? = nil,
        recommendedProvider: String? = nil,
        recommendedModel: String? = nil,
        reason: String = "",
        suggestedBy: String = "",
        createdAt: Date = Date(),
        status: SuggestionStatus = .pending,
        skillTags: [String]? = nil,
        outputStyles: Set<OutputStyle>? = nil
    ) {
        self.id = id
        self.name = name
        self.persona = persona
        self.recommendedPreset = recommendedPreset
        self.recommendedProvider = recommendedProvider
        self.recommendedModel = recommendedModel
        self.reason = reason
        self.suggestedBy = suggestedBy
        self.createdAt = createdAt
        self.status = status
        self.skillTags = skillTags
        self.outputStyles = outputStyles
    }
}

// MARK: - 작업 계획

struct RoomPlan: Codable {
    let summary: String           // 계획 요약
    let estimatedSeconds: Int     // 예상 소요 시간 (초)
    let steps: [RoomStep]         // 단계별 작업
    var version: Int              // 계획 버전 (거부 시 +1)

    init(summary: String, estimatedSeconds: Int, steps: [RoomStep], version: Int = 1) {
        self.summary = summary
        self.estimatedSeconds = estimatedSeconds
        self.steps = steps
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        estimatedSeconds = try container.decode(Int.self, forKey: .estimatedSeconds)
        steps = try container.decode([RoomStep].self, forKey: .steps)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}

// MARK: - 작업일지

struct WorkLog: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let roomTitle: String
    let participants: [String]       // 에이전트 이름 목록
    let task: String                 // 원본 작업 내용
    let discussionSummary: String    // 토론 요약
    let planSummary: String          // 계획 요약
    let outcome: String              // 최종 결과
    let durationSeconds: Int         // 소요 시간

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        roomTitle: String,
        participants: [String],
        task: String,
        discussionSummary: String = "",
        planSummary: String = "",
        outcome: String,
        durationSeconds: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.roomTitle = roomTitle
        self.participants = participants
        self.task = task
        self.discussionSummary = discussionSummary
        self.planSummary = planSummary
        self.outcome = outcome
        self.durationSeconds = durationSeconds
    }

    func asContextString() -> String {
        var parts: [String] = []
        parts.append("[이전 작업] \(task)")
        if !discussionSummary.isEmpty {
            parts.append("[토론 결과] \(discussionSummary)")
        }
        if !planSummary.isEmpty {
            parts.append("[실행 계획] \(planSummary)")
        }
        parts.append("[최종 결과] \(outcome)")
        return parts.joined(separator: "\n")
    }
}

// MARK: - 토론 브리핑 (컨텍스트 압축)

struct RoomBriefing: Codable {
    let summary: String                         // 작업 요약 (2-3문장)
    let keyDecisions: [String]                  // 핵심 결정사항
    let agentResponsibilities: [String: String] // 에이전트명 → 담당 역할
    let openIssues: [String]                    // 미결 사항

    /// 실행 단계에서 사용할 컨텍스트 문자열
    func asContextString() -> String {
        var parts: [String] = []
        parts.append("[요약] \(summary)")
        if !keyDecisions.isEmpty {
            parts.append("[결정사항]\n" + keyDecisions.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !agentResponsibilities.isEmpty {
            parts.append("[역할 분담]\n" + agentResponsibilities.map { "- \($0.key): \($0.value)" }.joined(separator: "\n"))
        }
        if !openIssues.isEmpty {
            parts.append("[미결 사항]\n" + openIssues.map { "- \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - 방

struct Room: Identifiable, Codable {
    let id: UUID
    var title: String
    var assignedAgentIDs: [UUID]
    var messages: [ChatMessage]
    var status: RoomStatus
    var mode: RoomMode
    var plan: RoomPlan?
    var timerStartedAt: Date?
    var timerDurationSeconds: Int?
    let createdAt: Date
    var completedAt: Date?
    let createdBy: RoomCreator
    var currentStepIndex: Int
    // 토론 관련
    var currentRound: Int
    // 토론 산출물
    var artifacts: [DiscussionArtifact]
    // 토론 브리핑 (컨텍스트 압축)
    var briefing: RoomBriefing?
    // 프로젝트 연동
    var projectPaths: [String]
    /// git worktree 경로 (동일 projectPath 동시 사용 시 lazy 생성)
    var worktreePath: String?
    var buildCommand: String?
    // 빌드 루프
    var buildLoopStatus: BuildLoopStatus?
    var buildRetryCount: Int
    var maxBuildRetries: Int
    var lastBuildResult: BuildResult?
    // 승인 게이트
    var pendingApprovalStepIndex: Int?
    // QA 루프
    var testCommand: String?
    var qaLoopStatus: QALoopStatus?
    var qaRetryCount: Int
    var maxQARetries: Int
    var lastQAResult: QAResult?
    // 에이전트 생성 제안
    var pendingAgentSuggestions: [RoomAgentSuggestion]
    // 작업일지
    var workLog: WorkLog?
    // 워크플로우 (Phase E)
    var intent: WorkflowIntent?
    var documentType: DocumentType?
    /// 초기 메시지에서 문서 요청 감지 시 설정 (리서치 완료 후 자동 문서화)
    var autoDocOutput: Bool
    /// clarify 완료 후 동적으로 결정: 실행 계획이 필요한가?
    var needsPlan: Bool
    var currentPhase: WorkflowPhase?
    var completedPhases: Set<WorkflowPhase>
    var assumptions: [WorkflowAssumption]?
    var userAnswers: [UserAnswer]?
    var playbook: ProjectPlaybook?
    var intakeData: IntakeData?
    var clarifyQuestionCount: Int
    /// 복명복창에서 사용자가 승인한 요약 (토론 의도 앵커링용)
    var clarifySummary: String?
    /// clarify LLM이 판단한 위임 정보 (explicit: 지정 에이전트만, open: 시스템 판단)
    var delegationInfo: DelegationInfo?
    /// 토론 사이클 후 사용자 체크포인트 대기 여부
    var isDiscussionCheckpoint: Bool
    // 토론 결정 로그
    var decisionLog: [DecisionEntry]
    // Plan C: 새 워크플로우 필드
    var taskBrief: TaskBrief?
    var agentRoles: [String: RuntimeRole]       // agentID.uuidString → RuntimeRole
    var deferredActions: [DeferredAction]
    // Phase 1: 승인 기록 + 대기 유형
    var approvalHistory: [ApprovalRecord]
    var awaitingType: AwaitingType?

    /// 남은 시간 (초). 타이머 미시작 시 nil
    var remainingSeconds: Int? {
        guard let start = timerStartedAt,
              let duration = timerDurationSeconds else { return nil }
        let elapsed = Int(Date().timeIntervalSince(start))
        return max(0, duration - elapsed)
    }

    /// 짧은 ID (UUID 앞 6자리, 대화에서 참조용)
    var shortID: String {
        String(id.uuidString.prefix(6)).lowercased()
    }

    /// 첫 번째 프로젝트 경로 (빌드/테스트/shell 기본 workDir)
    var primaryProjectPath: String? { projectPaths.first }

    /// 실제 작업 디렉토리 (worktree 있으면 worktree, 없으면 원본)
    var effectiveProjectPath: String? { worktreePath ?? primaryProjectPath }

    /// 도구 실행 컨텍스트용 경로 배열 (effectiveProjectPath + 나머지 참조 경로)
    var effectiveProjectPaths: [String] {
        guard let effective = effectiveProjectPath else { return projectPaths }
        return [effective] + projectPaths.dropFirst()
    }

    /// 활성 방 여부 (planning, inProgress, awaitingApproval, awaitingUserInput)
    var isActive: Bool {
        status == .planning || status == .inProgress || status == .awaitingApproval || status == .awaitingUserInput
    }

    /// 사용자 확인이 필요한 상태 (승인 대기, 입력 대기, 에이전트 생성 제안 대기)
    var needsUserAttention: Bool {
        status == .awaitingApproval ||
        status == .awaitingUserInput ||
        pendingAgentSuggestions.contains { $0.status == .pending }
    }

    /// currentPhase 기반 활동 라벨
    var phaseLabel: String {
        guard status == .planning else {
            switch status {
            case .inProgress: return "진행 중"
            case .completed:  return "완료"
            case .failed:     return "실패"
            default:          return ""
            }
        }
        switch currentPhase {
        case .intake, .intent, .assemble:
            return "준비 중"
        case .clarify, .understand:
            return "요건 확인"
        case .design:
            return "설계 중"
        case .build:
            return "구현 중"
        case .review:
            return "검토 중"
        case .deliver:
            return "전달 중"
        case .plan:
            if currentRound > 0 { return "토론 중 (\(currentRound)R)" }
            if plan != nil { return "계획 검토 중" }
            if briefing != nil { return "계획 수립 중" }
            return "분석 중"
        case .execute:
            return "진행 중"
        case nil:
            return "준비 중"
        }
    }

    /// 남은 시간 포맷 문자열
    var timerDisplayText: String {
        switch status {
        case .planning:
            return phaseLabel
        case .inProgress:
            guard let remaining = remainingSeconds else { return "진행 중" }
            if remaining <= 0 { return "시간 초과" }
            let min = remaining / 60
            let sec = remaining % 60
            return String(format: "%d:%02d", min, sec)
        case .awaitingApproval:
            return "승인 대기"
        case .awaitingUserInput:
            return "입력 대기"
        case .completed:
            return "완료"
        case .failed:
            return "실패"
        }
    }

    // MARK: - 값 객체 접근자 (Phase 2)

    /// 워크플로우 진행 상태 그룹
    var workflowState: WorkflowState {
        get {
            WorkflowState(
                intent: intent,
                documentType: documentType,
                autoDocOutput: autoDocOutput,
                needsPlan: needsPlan,
                currentPhase: currentPhase,
                completedPhases: completedPhases
            )
        }
        set {
            intent = newValue.intent
            documentType = newValue.documentType
            autoDocOutput = newValue.autoDocOutput
            needsPlan = newValue.needsPlan
            currentPhase = newValue.currentPhase
            completedPhases = newValue.completedPhases
        }
    }

    /// 복명복창 컨텍스트 그룹
    var clarifyContext: ClarifyContext {
        get {
            ClarifyContext(
                intakeData: intakeData,
                clarifySummary: clarifySummary,
                clarifyQuestionCount: clarifyQuestionCount,
                assumptions: assumptions,
                userAnswers: userAnswers,
                delegationInfo: delegationInfo,
                playbook: playbook
            )
        }
        set {
            intakeData = newValue.intakeData
            clarifySummary = newValue.clarifySummary
            clarifyQuestionCount = newValue.clarifyQuestionCount
            assumptions = newValue.assumptions
            userAnswers = newValue.userAnswers
            delegationInfo = newValue.delegationInfo
            playbook = newValue.playbook
        }
    }

    /// 토론 세션 그룹
    var discussion: DiscussionSession {
        get {
            DiscussionSession(
                currentRound: currentRound,
                isCheckpoint: isDiscussionCheckpoint,
                decisionLog: decisionLog,
                artifacts: artifacts,
                briefing: briefing
            )
        }
        set {
            currentRound = newValue.currentRound
            isDiscussionCheckpoint = newValue.isCheckpoint
            decisionLog = newValue.decisionLog
            artifacts = newValue.artifacts
            briefing = newValue.briefing
        }
    }

    /// 프로젝트 연동 컨텍스트 그룹
    var projectContext: ProjectContext {
        get {
            ProjectContext(
                projectPaths: projectPaths,
                worktreePath: worktreePath,
                buildCommand: buildCommand,
                testCommand: testCommand
            )
        }
        set {
            projectPaths = newValue.projectPaths
            worktreePath = newValue.worktreePath
            buildCommand = newValue.buildCommand
            testCommand = newValue.testCommand
        }
    }

    /// 검증된 상태 전이. 유효하지 않으면 false 반환
    @discardableResult
    mutating func transitionTo(_ newStatus: RoomStatus) -> Bool {
        guard status.canTransition(to: newStatus) else { return false }
        status = newStatus
        return true
    }

    /// 바운드 체크된 단계 인덱스 설정
    mutating func setCurrentStep(_ index: Int) {
        let maxIndex = max(0, (plan?.steps.count ?? 1) - 1)
        currentStepIndex = max(0, min(index, maxIndex))
    }

    init(
        id: UUID = UUID(),
        title: String,
        assignedAgentIDs: [UUID],
        createdBy: RoomCreator,
        mode: RoomMode = .task,
        status: RoomStatus = .planning,
        createdAt: Date = Date(),
        projectPaths: [String] = [],
        buildCommand: String? = nil,
        testCommand: String? = nil
    ) {
        self.id = id
        self.title = title
        self.assignedAgentIDs = assignedAgentIDs
        self.messages = []
        self.status = status
        self.mode = mode
        self.plan = nil
        self.timerStartedAt = nil
        self.timerDurationSeconds = nil
        self.createdAt = createdAt
        self.completedAt = nil
        self.createdBy = createdBy
        self.currentStepIndex = 0
        self.currentRound = 0
        self.artifacts = []
        self.briefing = nil
        self.projectPaths = projectPaths
        self.worktreePath = nil
        self.buildCommand = buildCommand
        self.buildLoopStatus = nil
        self.buildRetryCount = 0
        self.maxBuildRetries = 3
        self.lastBuildResult = nil
        self.pendingApprovalStepIndex = nil
        self.pendingAgentSuggestions = []
        self.testCommand = testCommand
        self.qaLoopStatus = nil
        self.qaRetryCount = 0
        self.maxQARetries = 3
        self.lastQAResult = nil
        self.workLog = nil
        self.intent = nil
        self.documentType = nil
        self.autoDocOutput = false
        self.needsPlan = false
        self.currentPhase = nil
        self.completedPhases = []
        self.assumptions = nil
        self.userAnswers = nil
        self.playbook = nil
        self.intakeData = nil
        self.clarifyQuestionCount = 0
        self.clarifySummary = nil
        self.delegationInfo = nil
        self.isDiscussionCheckpoint = false
        self.decisionLog = []
        self.taskBrief = nil
        self.agentRoles = [:]
        self.deferredActions = []
        self.approvalHistory = []
        self.awaitingType = nil
    }

    // 기존 저장 데이터 호환
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        assignedAgentIDs = try container.decode([UUID].self, forKey: .assignedAgentIDs)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        status = try container.decode(RoomStatus.self, forKey: .status)
        mode = try container.decodeIfPresent(RoomMode.self, forKey: .mode) ?? .task
        plan = try container.decodeIfPresent(RoomPlan.self, forKey: .plan)
        timerStartedAt = try container.decodeIfPresent(Date.self, forKey: .timerStartedAt)
        timerDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .timerDurationSeconds)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        createdBy = try container.decode(RoomCreator.self, forKey: .createdBy)
        currentStepIndex = try container.decodeIfPresent(Int.self, forKey: .currentStepIndex) ?? 0
        // maxDiscussionRounds 제거됨 — 레거시 JSON의 해당 키는 자동 무시
        currentRound = try container.decodeIfPresent(Int.self, forKey: .currentRound) ?? 0
        artifacts = try container.decodeIfPresent([DiscussionArtifact].self, forKey: .artifacts) ?? []
        briefing = try container.decodeIfPresent(RoomBriefing.self, forKey: .briefing)
        // 하위 호환: projectPaths 배열 우선, 없으면 기존 projectPath 단일 문자열 변환
        if let paths = try container.decodeIfPresent([String].self, forKey: .projectPaths) {
            projectPaths = paths
        } else {
            enum LegacyKeys: String, CodingKey { case projectPath }
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let path = try legacy.decodeIfPresent(String.self, forKey: .projectPath) {
                projectPaths = [path]
            } else {
                projectPaths = []
            }
        }
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        buildCommand = try container.decodeIfPresent(String.self, forKey: .buildCommand)
        buildLoopStatus = try container.decodeIfPresent(BuildLoopStatus.self, forKey: .buildLoopStatus)
        buildRetryCount = try container.decodeIfPresent(Int.self, forKey: .buildRetryCount) ?? 0
        maxBuildRetries = try container.decodeIfPresent(Int.self, forKey: .maxBuildRetries) ?? 3
        lastBuildResult = try container.decodeIfPresent(BuildResult.self, forKey: .lastBuildResult)
        pendingApprovalStepIndex = try container.decodeIfPresent(Int.self, forKey: .pendingApprovalStepIndex)
        pendingAgentSuggestions = try container.decodeIfPresent([RoomAgentSuggestion].self, forKey: .pendingAgentSuggestions) ?? []
        testCommand = try container.decodeIfPresent(String.self, forKey: .testCommand)
        qaLoopStatus = try container.decodeIfPresent(QALoopStatus.self, forKey: .qaLoopStatus)
        qaRetryCount = try container.decodeIfPresent(Int.self, forKey: .qaRetryCount) ?? 0
        maxQARetries = try container.decodeIfPresent(Int.self, forKey: .maxQARetries) ?? 3
        lastQAResult = try container.decodeIfPresent(QAResult.self, forKey: .lastQAResult)
        workLog = try container.decodeIfPresent(WorkLog.self, forKey: .workLog)
        intent = try container.decodeIfPresent(WorkflowIntent.self, forKey: .intent)
        documentType = try container.decodeIfPresent(DocumentType.self, forKey: .documentType)
        autoDocOutput = try container.decodeIfPresent(Bool.self, forKey: .autoDocOutput) ?? false
        needsPlan = try container.decodeIfPresent(Bool.self, forKey: .needsPlan) ?? false
        currentPhase = (try? container.decodeIfPresent(WorkflowPhase.self, forKey: .currentPhase)) ?? nil
        completedPhases = try container.decodeIfPresent(Set<WorkflowPhase>.self, forKey: .completedPhases) ?? []
        assumptions = try container.decodeIfPresent([WorkflowAssumption].self, forKey: .assumptions)
        userAnswers = try container.decodeIfPresent([UserAnswer].self, forKey: .userAnswers)
        playbook = try container.decodeIfPresent(ProjectPlaybook.self, forKey: .playbook)
        intakeData = try container.decodeIfPresent(IntakeData.self, forKey: .intakeData)
        clarifyQuestionCount = try container.decodeIfPresent(Int.self, forKey: .clarifyQuestionCount) ?? 0
        clarifySummary = try container.decodeIfPresent(String.self, forKey: .clarifySummary)
        delegationInfo = try container.decodeIfPresent(DelegationInfo.self, forKey: .delegationInfo)
        isDiscussionCheckpoint = try container.decodeIfPresent(Bool.self, forKey: .isDiscussionCheckpoint) ?? false
        decisionLog = try container.decodeIfPresent([DecisionEntry].self, forKey: .decisionLog) ?? []
        taskBrief = try container.decodeIfPresent(TaskBrief.self, forKey: .taskBrief)
        agentRoles = try container.decodeIfPresent([String: RuntimeRole].self, forKey: .agentRoles) ?? [:]
        deferredActions = try container.decodeIfPresent([DeferredAction].self, forKey: .deferredActions) ?? []
        approvalHistory = try container.decodeIfPresent([ApprovalRecord].self, forKey: .approvalHistory) ?? []
        awaitingType = try container.decodeIfPresent(AwaitingType.self, forKey: .awaitingType)
    }
}
