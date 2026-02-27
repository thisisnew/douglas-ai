import Foundation

/// 도구 실행 시 필요한 방/에이전트 컨텍스트 (Sendable)
struct ToolExecutionContext: Sendable {
    let roomID: UUID?
    let agentsByName: [String: UUID]      // 에이전트 이름 → ID 스냅샷
    let agentListString: String           // 에이전트 목록 문자열 스냅샷
    let inviteAgent: @Sendable (UUID) async -> Bool  // 방에 에이전트 초대

    static let empty = ToolExecutionContext(
        roomID: nil,
        agentsByName: [:],
        agentListString: "",
        inviteAgent: { _ in false }
    )
}
