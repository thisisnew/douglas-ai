import Foundation

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
             (.awaitingUserInput, .failed):
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
struct RoomStep: Codable, Equatable {
    let text: String
    let requiresApproval: Bool
    var assignedAgentID: UUID?

    init(text: String, requiresApproval: Bool = false, assignedAgentID: UUID? = nil) {
        self.text = text
        self.requiresApproval = requiresApproval
        self.assignedAgentID = assignedAgentID
    }

    /// 커스텀 디코딩: plain String 또는 {"text":..., "requires_approval":...} 둘 다 지원
    init(from decoder: Decoder) throws {
        // 먼저 plain String 시도
        if let container = try? decoder.singleValueContainer(),
           let str = try? container.decode(String.self) {
            self.text = str
            self.requiresApproval = false
            self.assignedAgentID = nil
            return
        }
        // object 형태
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
        self.assignedAgentID = try container.decodeIfPresent(UUID.self, forKey: .assignedAgentID)
    }

    func encode(to encoder: Encoder) throws {
        // 승인 불필요 + 배정 없으면 plain String으로 인코딩 (역호환)
        if !requiresApproval && assignedAgentID == nil {
            var container = encoder.singleValueContainer()
            try container.encode(text)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encode(requiresApproval, forKey: .requiresApproval)
            try container.encodeIfPresent(assignedAgentID, forKey: .assignedAgentID)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case requiresApproval = "requires_approval"
        case assignedAgentID = "assigned_agent_id"
    }
}

extension RoomStep: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.text = value
        self.requiresApproval = false
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
        status: SuggestionStatus = .pending
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
    }
}

// MARK: - 작업 계획

struct RoomPlan: Codable {
    let summary: String           // 계획 요약
    let estimatedSeconds: Int     // 예상 소요 시간 (초)
    let steps: [RoomStep]         // 단계별 작업
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
    var maxDiscussionRounds: Int
    var currentRound: Int
    // 토론 산출물
    var artifacts: [DiscussionArtifact]
    // 토론 브리핑 (컨텍스트 압축)
    var briefing: RoomBriefing?
    // 프로젝트 연동
    var projectPaths: [String]
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
    var currentPhase: WorkflowPhase?
    var assumptions: [WorkflowAssumption]?
    var userAnswers: [UserAnswer]?
    var playbook: ProjectPlaybook?
    var intakeData: IntakeData?
    var clarifyQuestionCount: Int

    /// 남은 시간 (초). 타이머 미시작 시 nil
    var remainingSeconds: Int? {
        guard let start = timerStartedAt,
              let duration = timerDurationSeconds else { return nil }
        let elapsed = Int(Date().timeIntervalSince(start))
        return max(0, duration - elapsed)
    }

    /// 첫 번째 프로젝트 경로 (빌드/테스트/shell 기본 workDir)
    var primaryProjectPath: String? { projectPaths.first }

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

    /// 토론 진행률 텍스트 (합의 기반)
    var discussionProgressText: String {
        if status != .planning { return "토론 완료" }
        if currentRound == 0 { return "토론 준비 중" }
        return "토론 중 (\(currentRound)라운드)"
    }

    /// 남은 시간 포맷 문자열
    var timerDisplayText: String {
        switch status {
        case .planning:
            return "계획 중..."
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
        maxDiscussionRounds: Int = 10,
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
        self.maxDiscussionRounds = max(1, maxDiscussionRounds)
        self.currentRound = 0
        self.artifacts = []
        self.briefing = nil
        self.projectPaths = projectPaths
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
        self.currentPhase = nil
        self.assumptions = nil
        self.userAnswers = nil
        self.playbook = nil
        self.intakeData = nil
        self.clarifyQuestionCount = 0
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
        maxDiscussionRounds = max(1, try container.decodeIfPresent(Int.self, forKey: .maxDiscussionRounds) ?? 3)
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
        currentPhase = try container.decodeIfPresent(WorkflowPhase.self, forKey: .currentPhase)
        assumptions = try container.decodeIfPresent([WorkflowAssumption].self, forKey: .assumptions)
        userAnswers = try container.decodeIfPresent([UserAnswer].self, forKey: .userAnswers)
        playbook = try container.decodeIfPresent(ProjectPlaybook.self, forKey: .playbook)
        intakeData = try container.decodeIfPresent(IntakeData.self, forKey: .intakeData)
        clarifyQuestionCount = try container.decodeIfPresent(Int.self, forKey: .clarifyQuestionCount) ?? 0
    }
}
