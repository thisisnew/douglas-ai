import Foundation

/// 플러그인에 노출되는 DOUGLAS 시스템 파사드
/// RoomManager/AgentStore를 직접 노출하지 않고 안전한 API만 제공
@MainActor
final class PluginContext {
    private weak var roomManager: RoomManager?
    private weak var agentStore: AgentStore?

    init(roomManager: RoomManager, agentStore: AgentStore) {
        self.roomManager = roomManager
        self.agentStore = agentStore
    }

    // MARK: - Room 조작

    /// 외부 소스에서 새 Room 생성 + 워크플로우 시작
    @discardableResult
    func createRoom(
        title: String,
        task: String,
        agentIDs: [UUID]? = nil,
        intent: WorkflowIntent? = nil
    ) -> UUID? {
        guard let rm = roomManager, let store = agentStore else { return nil }

        // 에이전트 미지정 시 마스터 에이전트 사용
        let ids = agentIDs ?? [store.masterAgent?.id].compactMap { $0 }
        guard !ids.isEmpty else { return nil }

        rm.createManualRoom(title: title, agentIDs: ids, task: task, intent: intent)
        return rm.rooms.last?.id
    }

    /// 기존 Room에 사용자 메시지 주입 (워크플로우 트리거 포함)
    func sendUserMessage(_ text: String, to roomID: UUID) async {
        await roomManager?.sendUserMessage(text, to: roomID)
    }

    /// Room 조회
    func room(for id: UUID) -> Room? {
        roomManager?.rooms.first { $0.id == id }
    }

    /// 활성 Room 목록
    func activeRooms() -> [Room] {
        roomManager?.activeRooms ?? []
    }

    // MARK: - Agent 조회

    func masterAgent() -> Agent? {
        agentStore?.masterAgent
    }

    func subAgents() -> [Agent] {
        agentStore?.subAgents ?? []
    }
}
