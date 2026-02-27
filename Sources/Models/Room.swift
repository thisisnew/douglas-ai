import Foundation

// MARK: - 방 모드

enum RoomMode: String, Codable {
    case task        // 기존 방식: 계획 → 단계별 실행
    case discussion  // 토론: 에이전트들이 순차적으로 의견 교환
}

// MARK: - 방 상태

enum RoomStatus: String, Codable {
    case planning      // 에이전트가 계획 수립 중
    case inProgress    // 타이머 진행 중 (작업 중)
    case completed     // 작업 완료
    case failed        // 실패

    /// 허용된 상태 전이 검증
    func canTransition(to target: RoomStatus) -> Bool {
        switch (self, target) {
        case (.planning, .inProgress),
             (.planning, .completed),
             (.planning, .failed),
             (.inProgress, .completed),
             (.inProgress, .failed):
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

// MARK: - 작업 계획

struct RoomPlan: Codable {
    let summary: String           // 계획 요약
    let estimatedSeconds: Int     // 예상 소요 시간 (초)
    let steps: [String]           // 단계별 작업
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
    // 작업일지
    var workLog: WorkLog?

    /// 남은 시간 (초). 타이머 미시작 시 nil
    var remainingSeconds: Int? {
        guard let start = timerStartedAt,
              let duration = timerDurationSeconds else { return nil }
        let elapsed = Int(Date().timeIntervalSince(start))
        return max(0, duration - elapsed)
    }

    /// 활성 방 여부 (planning 또는 inProgress)
    var isActive: Bool {
        status == .planning || status == .inProgress
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
        createdAt: Date = Date()
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
        self.workLog = nil
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
        workLog = try container.decodeIfPresent(WorkLog.self, forKey: .workLog)
    }
}
