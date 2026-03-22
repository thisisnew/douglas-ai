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
    let goal: String              // "거래처 납기 지연 사과 메일 발송"
    let constraints: [String]     // ["격식체", "새 납기일: 3/20"]
    let successCriteria: [String] // ["사과 표현", "새 납기일 명시"]
    let nonGoals: [String]        // ["전체 공지 아님"]
    let overallRisk: RiskLevel    // .high (이메일 전송)
    let outputType: OutputType    // .message
    let needsClarification: Bool  // 정보 부족 시 true → 질문 1회 표시
    let questions: [String]       // needsClarification=true 시 질문 목록 (최대 2개)

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
    case cancelled          // 사용자 취소

    /// 허용된 상태 전이 검증
    func canTransition(to target: RoomStatus) -> Bool {
        switch (self, target) {
        case (.planning, .inProgress),
             (.planning, .completed),
             (.planning, .failed),
             (.planning, .cancelled),
             (.planning, .awaitingApproval),
             (.planning, .awaitingUserInput),
             (.inProgress, .completed),
             (.inProgress, .failed),
             (.inProgress, .cancelled),
             (.inProgress, .awaitingApproval),
             (.inProgress, .awaitingUserInput),
             (.awaitingApproval, .inProgress),
             (.awaitingApproval, .planning),
             (.awaitingApproval, .failed),
             (.awaitingApproval, .cancelled),
             (.awaitingApproval, .completed),
             (.awaitingUserInput, .planning),
             (.awaitingUserInput, .inProgress),
             (.awaitingUserInput, .completed),
             (.awaitingUserInput, .failed),
             (.awaitingUserInput, .cancelled),
             (.completed, .inProgress),    // Follow-up cycle: 완료된 방 재활성화 (launchFollowUpCycle)
             (.completed, .planning),      // Follow-up cycle: 완료된 방에서 새 워크플로우 시작
             (.failed, .inProgress),       // 실패 복구: 재시도
             (.failed, .planning),         // 실패 복구: 재계획
             (.cancelled, .inProgress),    // 취소 후 재활성화
             (.cancelled, .planning):      // 취소 후 재계획
            return true
        default:
            return false
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = RoomStatus(rawValue: raw) ?? .failed
    }
}

// MARK: - 요청 상태 (WORKFLOW_SPEC §7 — 21개 상태 투영)

enum RequestStatus: String, Codable {
    // Intake
    case received
    // Clarification
    case intentClassified
    case waitingClarification
    // Setup
    case roomCreated
    case agentMatched
    case waitingAgentConfirmation
    // Work
    case discussing, planning, executing, documenting
    // Approval Gates
    case waitingPlanApproval, waitingExecutionApproval
    case waitingUserFeedback, waitingFinalApproval
    // Terminal
    case completed, failed, cancelled
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
    case pending, inProgress, awaitingApproval, completed, skipped, failed
}

struct RoomStep: Codable, Equatable {
    var text: String
    let requiresApproval: Bool
    var assignedAgentID: UUID?
    var riskLevel: RiskLevel
    var status: StepStatus
    var workingDirectory: String?

    init(text: String, requiresApproval: Bool = false, assignedAgentID: UUID? = nil, riskLevel: RiskLevel = .low, status: StepStatus = .pending, workingDirectory: String? = nil) {
        self.text = text
        self.requiresApproval = requiresApproval
        self.assignedAgentID = assignedAgentID
        self.riskLevel = riskLevel
        self.status = status
        self.workingDirectory = workingDirectory
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
            self.workingDirectory = nil
            return
        }
        // object 형태
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
        self.assignedAgentID = try container.decodeIfPresent(UUID.self, forKey: .assignedAgentID)
        self.riskLevel = try container.decodeIfPresent(RiskLevel.self, forKey: .riskLevel) ?? .low
        self.status = try container.decodeIfPresent(StepStatus.self, forKey: .status) ?? .pending
        self.workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
    }

    func encode(to encoder: Encoder) throws {
        // 승인 불필요 + 배정 없으면 plain String으로 인코딩 (역호환)
        if !requiresApproval && assignedAgentID == nil && riskLevel == .low && status == .pending && workingDirectory == nil {
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
            try container.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case requiresApproval = "requires_approval"
        case assignedAgentID = "assigned_agent_id"
        case riskLevel = "risk_level"
        case status
        case workingDirectory = "working_directory"
    }
}

extension RoomStep: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.text = value
        self.requiresApproval = false
        self.riskLevel = .low
        self.status = .pending
        self.workingDirectory = nil
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
    var steps: [RoomStep]         // 단계별 작업
    private(set) var version: Int  // 계획 버전 (거부 시 incrementVersion() 호출)
    var stepJournal: [String]     // 완료된 단계의 요약 (인덱스 = 단계 번호, 300자 캡)
    /// 단계 결과 전문 아카이브 — journal의 300자 캡 전 원본 (다음 단계에서 재참조용)
    var stepResultsFull: [String]

    /// 계획 버전 증가 (거부 → 재수립 시)
    mutating func incrementVersion() { version += 1 }

    init(summary: String, estimatedSeconds: Int, steps: [RoomStep], version: Int = 1) {
        self.summary = summary
        self.estimatedSeconds = estimatedSeconds
        self.steps = steps
        self.version = version
        self.stepJournal = []
        self.stepResultsFull = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        estimatedSeconds = try container.decode(Int.self, forKey: .estimatedSeconds)
        steps = try container.decode([RoomStep].self, forKey: .steps)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        stepJournal = try container.decodeIfPresent([String].self, forKey: .stepJournal) ?? []
        stepResultsFull = try container.decodeIfPresent([String].self, forKey: .stepResultsFull) ?? []
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

// MARK: - 조사 브리핑 (Research 전용 구조화 결과물)

/// 조사 결과의 개별 주제
struct ResearchFinding: Codable, Equatable {
    let topic: String    // 조사 주제
    let detail: String   // 상세 내용
}

/// Research intent의 구조화된 브리핑 — 핵심요약/조사결과/실무포인트/한계
struct ResearchBriefing: Codable, Equatable {
    let executiveSummary: String       // 핵심 요약 (2-3문장)
    let findings: [ResearchFinding]    // 조사 결과 (주제별)
    let actionablePoints: [String]     // 실무 포인트
    let limitations: [String]          // 한계/추가 조사 필요

    /// 후속 단계에서 사용할 컨텍스트 문자열
    func asContextString() -> String {
        var parts: [String] = []
        parts.append("[핵심 요약] \(executiveSummary)")
        if !findings.isEmpty {
            parts.append("[조사 결과]\n" + findings.map { "- \($0.topic): \($0.detail)" }.joined(separator: "\n"))
        }
        if !actionablePoints.isEmpty {
            parts.append("[실무 포인트]\n" + actionablePoints.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !limitations.isEmpty {
            parts.append("[한계/추가 조사 필요]\n" + limitations.map { "- \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - 방

struct Room: Identifiable, Codable {
    let id: UUID
    private(set) var title: String
    var assignedAgentIDs: [UUID]                     // addAgent/removeAgent로 변경
    var messages: [ChatMessage]                       // addMessage/insertMessage 권장 (private(set) 보류 — 208곳 위임 필요)
    var status: RoomStatus                            // transitionTo/complete/fail/cancel 권장
    var mode: RoomMode
    var plan: RoomPlan?                               // setPlan 권장 (private(set) 보류: 중첩 step mutation ~15곳)
    var timerStartedAt: Date?                         // startExecution 권장
    var timerDurationSeconds: Int?                    // startExecution 권장
    let createdAt: Date
    var completedAt: Date?                            // complete/fail/cancel/resumeWorkflow 권장
    let createdBy: RoomCreator
    var currentStepIndex: Int                        // setCurrentStep으로 변경
    // 승인 게이트
    var pendingApprovalStepIndex: Int?
    // 에이전트 생성 제안
    var pendingAgentSuggestions: [RoomAgentSuggestion]
    // 작업일지
    private(set) var workLog: WorkLog?                // setWorkLog/clearWorkLog로 변경
    // Plan C: 새 워크플로우 필드
    private(set) var taskBrief: TaskBrief?            // setTaskBrief로 변경
    private(set) var agentRoles: [UUID: RuntimeRole]  // assignRole로 변경
    private(set) var agentPositions: [UUID: WorkflowPosition]  // assignPosition으로 변경
    // Phase 1: 승인 기록 + 대기 유형
    var approvalHistory: [ApprovalRecord]              // recordApproval 권장
    var awaitingType: AwaitingType?                    // awaitApproval/recordApproval 권장
    var pendingAgentConfirmationID: UUID?  // agentConfirmation 대기 중인 에이전트 ID
    // Phase 7: 값 객체 — 도메인 메서드 사용 권장 (private(set) 보류: 중첩 mutating 위임 ~200곳 필요)
    var workflowState: WorkflowState
    var clarifyContext: ClarifyContext
    var projectContext: ProjectContext
    var discussion: DiscussionSession
    var buildQA: BuildQAState
    // Phase 7: 요청/후속 이력
    var requests: [DouglasRequest]
    var followUpActions: [FollowUpAction]

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
    var primaryProjectPath: String? { projectContext.projectPaths.first }

    /// 실제 작업 디렉토리 (worktree 있으면 worktree, 없으면 원본)
    var effectiveProjectPath: String? { projectContext.worktreePath ?? primaryProjectPath }

    /// 도구 실행 컨텍스트용 경로 배열 (effectiveProjectPath + 나머지 참조 경로)
    var effectiveProjectPaths: [String] {
        guard let effective = effectiveProjectPath else { return projectContext.projectPaths }
        return [effective] + projectContext.projectPaths.dropFirst()
    }

    /// 활성 방 여부 (planning, inProgress, awaitingApproval, awaitingUserInput)
    var isActive: Bool {
        switch status {
        case .planning, .inProgress, .awaitingApproval, .awaitingUserInput: return true
        case .completed, .failed, .cancelled: return false
        }
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
        switch workflowState.currentPhase {
        case .intake, .intent, .assemble:
            return "준비 중"
        case .clarify, .understand:
            return "요건 확인"
        case .design:
            return workflowState.intent == .discussion ? "토론 중" : "설계 중"
        case .build:
            return "구현 중"
        case .review:
            return "검토 중"
        case .deliver:
            return workflowState.intent == .discussion ? "결론 도출 중" : "전달 중"
        case .plan:
            if discussion.currentRound > 0 { return "토론 중 (\(discussion.currentRound)R)" }
            if plan != nil { return "계획 검토 중" }
            if discussion.researchBriefing != nil || discussion.briefing != nil { return "계획 수립 중" }
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
        case .cancelled:
            return "취소됨"
        }
    }

    // MARK: - 요청 상태 투영 (WORKFLOW_SPEC §7)

    /// RoomStatus + WorkflowPhase + AwaitingType 조합으로 명세 §7의 세분화된 상태를 투영
    var requestStatus: RequestStatus {
        switch status {
        case .planning:
            guard let phase = workflowState.currentPhase else { return .received }
            switch phase {
            case .intake: return .received
            case .intent, .understand: return .intentClassified
            case .clarify: return awaitingType == .clarification ? .waitingClarification : .intentClassified
            case .assemble: return awaitingType == .agentConfirmation ? .waitingAgentConfirmation : .agentMatched
            case .design: return .discussing
            case .plan: return awaitingType == .planApproval ? .waitingPlanApproval : .planning
            case .build, .execute: return .executing
            case .review: return .executing
            case .deliver: return awaitingType == .deliverApproval ? .waitingFinalApproval : .documenting
            }
        case .inProgress:
            return .executing
        case .awaitingApproval:
            switch awaitingType {
            case .planApproval: return .waitingPlanApproval
            case .stepApproval, .irreversibleStep: return .waitingExecutionApproval
            case .finalApproval, .deliverApproval: return .waitingFinalApproval
            case .agentConfirmation: return .waitingAgentConfirmation
            case .clarification: return .waitingClarification
            case .designApproval: return .waitingPlanApproval
            default: return .waitingUserFeedback
            }
        case .awaitingUserInput: return .waitingUserFeedback
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
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

    // MARK: - 에이전트 관리 도메인 메서드

    /// 에이전트를 방에 추가 (중복 방지)
    mutating func addAgent(_ agentID: UUID) {
        guard !assignedAgentIDs.contains(agentID) else { return }
        assignedAgentIDs.append(agentID)
    }

    /// 에이전트를 방에서 제거
    mutating func removeAgent(_ agentID: UUID) {
        assignedAgentIDs.removeAll(where: { $0 == agentID })
        agentRoles.removeValue(forKey: agentID)
        agentPositions.removeValue(forKey: agentID)
    }

    /// 에이전트에 런타임 역할 배정
    mutating func assignRole(_ role: RuntimeRole, to agentID: UUID) {
        agentRoles[agentID] = role
    }

    /// 에이전트에 워크플로우 포지션 배정
    mutating func assignPosition(_ position: WorkflowPosition, to agentID: UUID) {
        agentPositions[agentID] = position
    }

    // MARK: - 워크플로우 도메인 메서드 (Aggregate Root 캡슐화)

    /// Intent 분류 결과 설정 — 이미 분류되었으면 무시 (재분류 방지)
    /// nil intent는 무시 (quickClassify 실패 시)
    mutating func classifyIntent(_ intent: WorkflowIntent?, modifiers: Set<IntentModifier>) {
        guard workflowState.intent == nil, let intent else { return }
        workflowState.intent = intent
        workflowState.modifiers = modifiers
    }

    /// 실행 계획 설정 + needsPlan 자동 해제
    mutating func setPlan(_ plan: RoomPlan) {
        self.plan = plan
        workflowState.needsPlan = false
    }

    /// 승인 기록 추가 + 대기 상태 해제
    mutating func recordApproval(_ record: ApprovalRecord) {
        approvalHistory.append(record)
        awaitingType = nil
    }

    /// 토론 결과를 clarify 컨텍스트에 추가
    mutating func appendDiscussionContext(_ summary: String) {
        let existing = clarifyContext.clarifySummary ?? ""
        clarifyContext.clarifySummary = existing + "\n\n[토론 결과]\n" + summary
    }

    /// 토론 모드 선택 — DiscussionSession에 위임
    mutating func startDiscussion(topic: String, agentRoles: [String], modifiers: Set<IntentModifier>) {
        discussion.selectDebateMode(topic: topic, agentRoles: agentRoles, modifiers: modifiers)
    }

    /// 워크플로우 완료 처리
    mutating func complete() {
        workflowState.clearCurrentPhase()
        status = .completed
        completedAt = Date()
    }

    // MARK: - 원자적 상태 전이 (다중 필드 불일관 방지)

    /// 워크플로우 실패 — status + completedAt + clearCurrentPhase 원자 처리
    mutating func fail() {
        transitionTo(.failed)
        completedAt = Date()
        workflowState.clearCurrentPhase()
    }

    /// 실행 시작 — status + timer 원자 처리
    mutating func startExecution(duration: Int? = nil) {
        transitionTo(.inProgress)
        timerStartedAt = Date()
        if let d = duration { timerDurationSeconds = d }
    }

    /// 승인 대기 — awaitingType + status 원자 처리
    mutating func awaitApproval(type: AwaitingType) {
        awaitingType = type
        transitionTo(.awaitingApproval)
    }

    /// 사용자 입력 대기 — isCheckpoint + status 원자 처리
    mutating func awaitUserInput() {
        discussion.isCheckpoint = true
        transitionTo(.awaitingUserInput)
    }

    /// 워크플로우 취소 — cancelled + completedAt + clearCurrentPhase
    mutating func cancel() {
        transitionTo(.cancelled)
        completedAt = Date()
        workflowState.clearCurrentPhase()
    }

    /// 워크플로우 재개 (Follow-up cycle) — planning + completedAt 리셋
    mutating func resumeWorkflow() {
        transitionTo(.planning)
        completedAt = nil
    }

    // MARK: - 메시지 + TaskBrief 도메인 메서드

    mutating func addMessage(_ message: ChatMessage) { messages.append(message) }
    mutating func insertMessage(_ message: ChatMessage, at index: Int) {
        guard index >= 0, index <= messages.count else { return }
        messages.insert(message, at: index)
    }
    mutating func setTaskBrief(_ brief: TaskBrief?) { taskBrief = brief }
    mutating func setTitle(_ title: String) { self.title = title }
    mutating func setWorkLog(_ log: WorkLog?) { workLog = log }
    mutating func clearWorkLog() { workLog = nil }

    // MARK: - Plan 위임 메서드

    /// Plan 단계 상태 업데이트
    mutating func updatePlanStep(at index: Int, status: StepStatus) {
        guard index >= 0, index < (plan?.steps.count ?? 0) else { return }
        plan?.steps[index].status = status
    }

    /// Plan 단계 결과 기록
    mutating func recordStepResult(journal: String, fullResult: String) {
        plan?.stepJournal.append(journal)
        plan?.stepResultsFull.append(fullResult)
    }

    /// Plan 전체 교체 (step 결과 포함)
    mutating func updatePlan(_ mutate: (inout RoomPlan) -> Void) {
        guard plan != nil else { return }
        mutate(&plan!)
    }

    /// 타이머 기간 설정
    mutating func setTimerDuration(_ seconds: Int) { timerDurationSeconds = seconds }

    /// completedAt 직접 설정 (cancel/complete가 아닌 특수 케이스)
    mutating func markCompletedNow() { completedAt = Date() }

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
        self.pendingApprovalStepIndex = nil
        self.pendingAgentSuggestions = []
        self.workLog = nil
        self.taskBrief = nil
        self.agentRoles = [:]
        self.agentPositions = [:]
        self.approvalHistory = []
        self.awaitingType = nil
        self.workflowState = WorkflowState()
        self.clarifyContext = ClarifyContext()
        self.projectContext = ProjectContext(projectPaths: projectPaths, buildCommand: buildCommand, testCommand: testCommand)
        self.discussion = DiscussionSession()
        self.buildQA = BuildQAState()
        self.requests = []
        self.followUpActions = []
    }

    // MARK: - Factory Methods

    /// 마스터 에이전트가 만드는 작업 방
    static func forTask(title: String, agentIDs: [UUID] = [], masterAgentID: UUID, projectPaths: [String] = []) -> Room {
        Room(title: title, assignedAgentIDs: agentIDs, createdBy: .master(agentID: masterAgentID), projectPaths: projectPaths)
    }

    /// 사용자가 직접 만드는 방
    static func forUser(title: String, agentIDs: [UUID] = [], projectPaths: [String] = []) -> Room {
        Room(title: title, assignedAgentIDs: agentIDs, createdBy: .user, projectPaths: projectPaths)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, assignedAgentIDs, messages, status, mode, plan
        case timerStartedAt, timerDurationSeconds, createdAt, completedAt, createdBy
        case currentStepIndex, pendingApprovalStepIndex, pendingAgentSuggestions
        case workLog, taskBrief, agentRoles, agentPositions
        case approvalHistory, awaitingType, pendingAgentConfirmationID
        case requests, followUpActions
        // WorkflowState (개별 키 유지 — JSON 호환)
        case intent, documentType, autoDocOutput, needsPlan, currentPhase, completedPhases, phaseTransitions
        // ClarifyContext
        case intakeData, clarifySummary, clarifyQuestionCount
        case assumptions, userAnswers, delegationInfo, playbook
        // ProjectContext
        case projectPaths, worktreePath, buildCommand, testCommand
        // DiscussionSession
        case currentRound, isDiscussionCheckpoint, decisionLog, artifacts, briefing, fullDiscussionLog
        // BuildQAState
        case buildLoopStatus, buildRetryCount, maxBuildRetries, lastBuildResult
        case qaLoopStatus, qaRetryCount, maxQARetries, lastQAResult
    }

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
        pendingApprovalStepIndex = try container.decodeIfPresent(Int.self, forKey: .pendingApprovalStepIndex)
        pendingAgentSuggestions = try container.decodeIfPresent([RoomAgentSuggestion].self, forKey: .pendingAgentSuggestions) ?? []
        workLog = try container.decodeIfPresent(WorkLog.self, forKey: .workLog)
        taskBrief = try container.decodeIfPresent(TaskBrief.self, forKey: .taskBrief)
        // agentRoles: [String: RuntimeRole] → [UUID: RuntimeRole] 하위 호환 변환
        if let uuidKeyed = try? container.decodeIfPresent([UUID: RuntimeRole].self, forKey: .agentRoles) {
            agentRoles = uuidKeyed ?? [:]
        } else if let stringKeyed = try? container.decodeIfPresent([String: RuntimeRole].self, forKey: .agentRoles) {
            // 레거시: String 키(agent name)는 UUID 변환 불가 → 빈 dict (재매칭됨)
            var converted: [UUID: RuntimeRole] = [:]
            for (key, value) in stringKeyed {
                if let uuid = UUID(uuidString: key) { converted[uuid] = value }
            }
            agentRoles = converted
        } else {
            agentRoles = [:]
        }
        // agentPositions: [String: WorkflowPosition] → [UUID: WorkflowPosition] 하위 호환 변환
        if let stringKeyed = try container.decodeIfPresent([String: WorkflowPosition].self, forKey: .agentPositions) {
            var converted: [UUID: WorkflowPosition] = [:]
            for (key, value) in stringKeyed {
                if let uuid = UUID(uuidString: key) { converted[uuid] = value }
            }
            agentPositions = converted
        } else {
            agentPositions = [:]
        }
        approvalHistory = try container.decodeIfPresent([ApprovalRecord].self, forKey: .approvalHistory) ?? []
        awaitingType = try container.decodeIfPresent(AwaitingType.self, forKey: .awaitingType)
        pendingAgentConfirmationID = try container.decodeIfPresent(UUID.self, forKey: .pendingAgentConfirmationID)
        requests = try container.decodeIfPresent([DouglasRequest].self, forKey: .requests) ?? []
        followUpActions = try container.decodeIfPresent([FollowUpAction].self, forKey: .followUpActions) ?? []

        // WorkflowState
        workflowState = WorkflowState(
            intent: try container.decodeIfPresent(WorkflowIntent.self, forKey: .intent),
            documentType: try container.decodeIfPresent(DocumentType.self, forKey: .documentType),
            autoDocOutput: try container.decodeIfPresent(Bool.self, forKey: .autoDocOutput) ?? false,
            needsPlan: try container.decodeIfPresent(Bool.self, forKey: .needsPlan) ?? false,
            currentPhase: (try? container.decodeIfPresent(WorkflowPhase.self, forKey: .currentPhase)) ?? nil,
            completedPhases: try container.decodeIfPresent(Set<WorkflowPhase>.self, forKey: .completedPhases) ?? [],
            phaseTransitions: try container.decodeIfPresent([PhaseTransition].self, forKey: .phaseTransitions) ?? []
        )

        // ClarifyContext
        clarifyContext = ClarifyContext(
            intakeData: try container.decodeIfPresent(IntakeData.self, forKey: .intakeData),
            clarifySummary: try container.decodeIfPresent(String.self, forKey: .clarifySummary),
            clarifyQuestionCount: try container.decodeIfPresent(Int.self, forKey: .clarifyQuestionCount) ?? 0,
            assumptions: try container.decodeIfPresent([WorkflowAssumption].self, forKey: .assumptions),
            userAnswers: try container.decodeIfPresent([UserAnswer].self, forKey: .userAnswers),
            delegationInfo: try container.decodeIfPresent(DelegationInfo.self, forKey: .delegationInfo),
            playbook: try container.decodeIfPresent(ProjectPlaybook.self, forKey: .playbook)
        )

        // ProjectContext (하위 호환: projectPaths 배열 우선, 없으면 기존 projectPath 단일 문자열)
        let paths: [String]
        if let p = try container.decodeIfPresent([String].self, forKey: .projectPaths) {
            paths = p
        } else {
            enum LegacyKeys: String, CodingKey { case projectPath }
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            paths = (try legacy.decodeIfPresent(String.self, forKey: .projectPath)).map { [$0] } ?? []
        }
        projectContext = ProjectContext(
            projectPaths: paths,
            worktreePath: try container.decodeIfPresent(String.self, forKey: .worktreePath),
            buildCommand: try container.decodeIfPresent(String.self, forKey: .buildCommand),
            testCommand: try container.decodeIfPresent(String.self, forKey: .testCommand)
        )

        // DiscussionSession
        discussion = DiscussionSession(
            currentRound: try container.decodeIfPresent(Int.self, forKey: .currentRound) ?? 0,
            isCheckpoint: try container.decodeIfPresent(Bool.self, forKey: .isDiscussionCheckpoint) ?? false,
            decisionLog: try container.decodeIfPresent([DecisionEntry].self, forKey: .decisionLog) ?? [],
            artifacts: try container.decodeIfPresent([DiscussionArtifact].self, forKey: .artifacts) ?? [],
            briefing: try container.decodeIfPresent(RoomBriefing.self, forKey: .briefing),
            fullDiscussionLog: try container.decodeIfPresent(String.self, forKey: .fullDiscussionLog)
        )

        // BuildQAState
        buildQA = BuildQAState(
            buildLoopStatus: try container.decodeIfPresent(BuildLoopStatus.self, forKey: .buildLoopStatus),
            buildRetryCount: try container.decodeIfPresent(Int.self, forKey: .buildRetryCount) ?? 0,
            maxBuildRetries: try container.decodeIfPresent(Int.self, forKey: .maxBuildRetries) ?? 3,
            lastBuildResult: try container.decodeIfPresent(BuildResult.self, forKey: .lastBuildResult),
            qaLoopStatus: try container.decodeIfPresent(QALoopStatus.self, forKey: .qaLoopStatus),
            qaRetryCount: try container.decodeIfPresent(Int.self, forKey: .qaRetryCount) ?? 0,
            maxQARetries: try container.decodeIfPresent(Int.self, forKey: .maxQARetries) ?? 3,
            lastQAResult: try container.decodeIfPresent(QAResult.self, forKey: .lastQAResult)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(assignedAgentIDs, forKey: .assignedAgentIDs)
        try container.encode(messages, forKey: .messages)
        try container.encode(status, forKey: .status)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(plan, forKey: .plan)
        try container.encodeIfPresent(timerStartedAt, forKey: .timerStartedAt)
        try container.encodeIfPresent(timerDurationSeconds, forKey: .timerDurationSeconds)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(currentStepIndex, forKey: .currentStepIndex)
        try container.encodeIfPresent(pendingApprovalStepIndex, forKey: .pendingApprovalStepIndex)
        try container.encode(pendingAgentSuggestions, forKey: .pendingAgentSuggestions)
        try container.encodeIfPresent(workLog, forKey: .workLog)
        try container.encodeIfPresent(taskBrief, forKey: .taskBrief)
        if !agentRoles.isEmpty { try container.encode(agentRoles, forKey: .agentRoles) }
        if !agentPositions.isEmpty {
            // UUID 키 → String 키 변환 (JSON 호환)
            let stringKeyed = Dictionary(uniqueKeysWithValues: agentPositions.map { ($0.key.uuidString, $0.value) })
            try container.encode(stringKeyed, forKey: .agentPositions)
        }
        if !approvalHistory.isEmpty { try container.encode(approvalHistory, forKey: .approvalHistory) }
        try container.encodeIfPresent(awaitingType, forKey: .awaitingType)
        try container.encodeIfPresent(pendingAgentConfirmationID, forKey: .pendingAgentConfirmationID)
        if !requests.isEmpty { try container.encode(requests, forKey: .requests) }
        if !followUpActions.isEmpty { try container.encode(followUpActions, forKey: .followUpActions) }
        // WorkflowState (개별 키로 인코딩 — JSON 호환)
        try container.encodeIfPresent(workflowState.intent, forKey: .intent)
        try container.encodeIfPresent(workflowState.documentType, forKey: .documentType)
        if workflowState.autoDocOutput { try container.encode(true, forKey: .autoDocOutput) }
        if workflowState.needsPlan { try container.encode(true, forKey: .needsPlan) }
        try container.encodeIfPresent(workflowState.currentPhase, forKey: .currentPhase)
        if !workflowState.completedPhases.isEmpty { try container.encode(workflowState.completedPhases, forKey: .completedPhases) }
        if !workflowState.phaseTransitions.isEmpty { try container.encode(workflowState.phaseTransitions, forKey: .phaseTransitions) }
        // ClarifyContext
        try container.encodeIfPresent(clarifyContext.intakeData, forKey: .intakeData)
        try container.encodeIfPresent(clarifyContext.clarifySummary, forKey: .clarifySummary)
        if clarifyContext.clarifyQuestionCount > 0 { try container.encode(clarifyContext.clarifyQuestionCount, forKey: .clarifyQuestionCount) }
        try container.encodeIfPresent(clarifyContext.assumptions, forKey: .assumptions)
        try container.encodeIfPresent(clarifyContext.userAnswers, forKey: .userAnswers)
        try container.encodeIfPresent(clarifyContext.delegationInfo, forKey: .delegationInfo)
        try container.encodeIfPresent(clarifyContext.playbook, forKey: .playbook)
        // ProjectContext
        if !projectContext.projectPaths.isEmpty { try container.encode(projectContext.projectPaths, forKey: .projectPaths) }
        try container.encodeIfPresent(projectContext.worktreePath, forKey: .worktreePath)
        try container.encodeIfPresent(projectContext.buildCommand, forKey: .buildCommand)
        try container.encodeIfPresent(projectContext.testCommand, forKey: .testCommand)
        // DiscussionSession
        if discussion.currentRound > 0 { try container.encode(discussion.currentRound, forKey: .currentRound) }
        if discussion.isCheckpoint { try container.encode(true, forKey: .isDiscussionCheckpoint) }
        if !discussion.decisionLog.isEmpty { try container.encode(discussion.decisionLog, forKey: .decisionLog) }
        if !discussion.artifacts.isEmpty { try container.encode(discussion.artifacts, forKey: .artifacts) }
        try container.encodeIfPresent(discussion.briefing, forKey: .briefing)
        try container.encodeIfPresent(discussion.fullDiscussionLog, forKey: .fullDiscussionLog)
        // BuildQAState
        try container.encodeIfPresent(buildQA.buildLoopStatus, forKey: .buildLoopStatus)
        if buildQA.buildRetryCount > 0 { try container.encode(buildQA.buildRetryCount, forKey: .buildRetryCount) }
        if buildQA.maxBuildRetries != 3 { try container.encode(buildQA.maxBuildRetries, forKey: .maxBuildRetries) }
        try container.encodeIfPresent(buildQA.lastBuildResult, forKey: .lastBuildResult)
        try container.encodeIfPresent(buildQA.qaLoopStatus, forKey: .qaLoopStatus)
        if buildQA.qaRetryCount > 0 { try container.encode(buildQA.qaRetryCount, forKey: .qaRetryCount) }
        if buildQA.maxQARetries != 3 { try container.encode(buildQA.maxQARetries, forKey: .maxQARetries) }
        try container.encodeIfPresent(buildQA.lastQAResult, forKey: .lastQAResult)
    }
}
