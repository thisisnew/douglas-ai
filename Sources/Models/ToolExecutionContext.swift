import Foundation

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
    let fileWriteTracker: FileWriteTracker?  // 파일 쓰기 충돌 추적
    // 워크플로우 (Phase E)
    let askUser: @Sendable (String, String?, [String]?) async -> String  // 사용자에게 질문
    let approveFileWrite: @Sendable (String, String) async -> Bool  // 파일 쓰기 승인 (path, preview) -> approved
    let currentPhase: WorkflowPhase?      // 현재 워크플로우 단계

    init(
        roomID: UUID?,
        agentsByName: [String: UUID],
        agentListString: String,
        inviteAgent: @escaping @Sendable (UUID) async -> Bool,
        suggestAgentCreation: @escaping @Sendable (RoomAgentSuggestion) async -> Bool = { _ in false },
        projectPaths: [String] = [],
        currentAgentID: UUID? = nil,
        currentAgentName: String? = nil,
        fileWriteTracker: FileWriteTracker? = nil,
        askUser: @escaping @Sendable (String, String?, [String]?) async -> String = { _, _, _ in "" },
        approveFileWrite: @escaping @Sendable (String, String) async -> Bool = { _, _ in true },
        currentPhase: WorkflowPhase? = nil
    ) {
        self.roomID = roomID
        self.agentsByName = agentsByName
        self.agentListString = agentListString
        self.inviteAgent = inviteAgent
        self.suggestAgentCreation = suggestAgentCreation
        self.projectPaths = projectPaths
        self.currentAgentID = currentAgentID
        self.currentAgentName = currentAgentName
        self.fileWriteTracker = fileWriteTracker
        self.askUser = askUser
        self.approveFileWrite = approveFileWrite
        self.currentPhase = currentPhase
    }

    static let empty = ToolExecutionContext(
        roomID: nil,
        agentsByName: [:],
        agentListString: "",
        inviteAgent: { _ in false }
    )
}
