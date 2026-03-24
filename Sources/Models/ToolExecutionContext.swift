import Foundation

/// 도구 라운드 간 메시지 소비 기준점 추적 (Sendable 래퍼)
final class MessageCheckpoint: @unchecked Sendable {
    var value: Int
    init(_ initial: Int) { self.value = initial }
}

/// 도구 실행 시 필요한 방/에이전트 컨텍스트 (Sendable)
struct ToolExecutionContext: Sendable {
    let roomID: UUID?
    let agentsByName: [String: UUID]      // 에이전트 이름 → ID 스냅샷
    let agentListString: String           // 에이전트 목록 문자열 스냅샷
    let inviteAgent: @Sendable (UUID) async -> Bool  // 방에 에이전트 초대
    let suggestAgentCreation: @Sendable (RoomAgentSuggestion) async -> Bool  // 에이전트 생성 제안
    let projectPaths: [String]            // 프로젝트 디렉토리 경로 (복수)
    let currentAgentID: UUID?             // 현재 실행 중인 에이전트
    let currentAgentName: String?         // 현재 실행 중인 에이전트 이름
    let agentPermissions: Set<ActionScope>  // 에이전트 행동 권한 (비어있으면 모두 허용)
    let fileWriteTracker: FileWriteTracker?  // 파일 쓰기 충돌 추적
    // 워크플로우 (Phase E)
    let askUser: @Sendable (String, String?, [String]?) async -> String  // 사용자에게 질문
    let currentPhase: WorkflowPhase?      // 현재 워크플로우 단계
    // Build 중 사용자 메시지 실시간 반영
    let fetchPendingUserMessages: (@Sendable () async -> [ConversationMessage])?

    /// Build/Execute 단계에서는 사용자 메시지 주입을 차단 (자율 실행 원칙)
    var isAutonomousExecution: Bool {
        currentPhase == .build || currentPhase == .execute
    }

    // 플러그인 훅
    let dispatchPluginEvent: @Sendable (PluginEvent) -> Void
    let interceptTool: @Sendable (String, [String: String]) async -> ToolInterceptResult
    let allowedPaths: [String]  // research에서 에이전트별 경로 제한. 빈 배열이면 제한 없음.

    init(
        roomID: UUID?,
        agentsByName: [String: UUID],
        agentListString: String,
        inviteAgent: @escaping @Sendable (UUID) async -> Bool,
        suggestAgentCreation: @escaping @Sendable (RoomAgentSuggestion) async -> Bool = { _ in false },
        projectPaths: [String] = [],
        currentAgentID: UUID? = nil,
        currentAgentName: String? = nil,
        agentPermissions: Set<ActionScope> = [],
        fileWriteTracker: FileWriteTracker? = nil,
        askUser: @escaping @Sendable (String, String?, [String]?) async -> String = { _, _, _ in "" },
        currentPhase: WorkflowPhase? = nil,
        fetchPendingUserMessages: (@Sendable () async -> [ConversationMessage])? = nil,
        dispatchPluginEvent: @escaping @Sendable (PluginEvent) -> Void = { _ in },
        interceptTool: @escaping @Sendable (String, [String: String]) async -> ToolInterceptResult = { _, _ in .passthrough },
        allowedPaths: [String] = []
    ) {
        self.roomID = roomID
        self.agentsByName = agentsByName
        self.agentListString = agentListString
        self.inviteAgent = inviteAgent
        self.suggestAgentCreation = suggestAgentCreation
        self.projectPaths = projectPaths
        self.currentAgentID = currentAgentID
        self.currentAgentName = currentAgentName
        self.agentPermissions = agentPermissions
        self.fileWriteTracker = fileWriteTracker
        self.askUser = askUser
        self.currentPhase = currentPhase
        self.fetchPendingUserMessages = fetchPendingUserMessages
        self.dispatchPluginEvent = dispatchPluginEvent
        self.interceptTool = interceptTool
        self.allowedPaths = allowedPaths
    }

    static let empty = ToolExecutionContext(
        roomID: nil,
        agentsByName: [:],
        agentListString: "",
        inviteAgent: { _ in false }
    )
}
