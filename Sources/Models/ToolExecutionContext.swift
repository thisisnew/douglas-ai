import Foundation

/// 도구 실행 시 필요한 방/에이전트 컨텍스트 (Sendable)
struct ToolExecutionContext: Sendable {
    let roomID: UUID?
    let agentsByName: [String: UUID]      // 에이전트 이름 → ID 스냅샷
    let agentListString: String           // 에이전트 목록 문자열 스냅샷
    let inviteAgent: @Sendable (UUID) async -> Bool  // 방에 에이전트 초대
    let projectPath: String?              // 프로젝트 디렉토리 경로
    let currentAgentID: UUID?             // 현재 실행 중인 에이전트
    let fileWriteTracker: FileWriteTracker?  // 파일 쓰기 충돌 추적

    init(
        roomID: UUID?,
        agentsByName: [String: UUID],
        agentListString: String,
        inviteAgent: @escaping @Sendable (UUID) async -> Bool,
        projectPath: String? = nil,
        currentAgentID: UUID? = nil,
        fileWriteTracker: FileWriteTracker? = nil
    ) {
        self.roomID = roomID
        self.agentsByName = agentsByName
        self.agentListString = agentListString
        self.inviteAgent = inviteAgent
        self.projectPath = projectPath
        self.currentAgentID = currentAgentID
        self.fileWriteTracker = fileWriteTracker
    }

    static let empty = ToolExecutionContext(
        roomID: nil,
        agentsByName: [:],
        agentListString: "",
        inviteAgent: { _ in false }
    )
}
