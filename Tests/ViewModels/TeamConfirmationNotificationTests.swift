import Testing
import Foundation
@testable import DOUGLAS

@Suite("팀 확인 알림 테스트")
@MainActor
struct TeamConfirmationNotificationTests {

    @Test("showTeamConfirmation — 자동 승인 불가 시 pendingTeamConfirmation 설정 후 게이트 대기")
    func teamConfirmation_setsPendingBeforeWaiting() async {
        let rm = makeTestRoomManager()
        let store = AgentStore()
        let master = Agent(name: "DOUGLAS", persona: "master", providerName: "P", modelName: "M", isMaster: true)
        let agent1 = Agent(name: "프론트엔드 개발자", persona: "FE", providerName: "P", modelName: "M")
        let agent2 = Agent(name: "백엔드 개발자", persona: "BE", providerName: "P", modelName: "M")
        store.addAgent(master)
        store.addAgent(agent1)
        store.addAgent(agent2)
        rm.configure(agentStore: store, providerManager: ProviderManager())

        // Room 생성 + 에이전트 2명 배정 (멀티에이전트 → 자동 승인 불가)
        let room = rm.createRoom(title: "테스트", agentIDs: [master.id, agent1.id, agent2.id], createdBy: .user)
        let roomID = room.id

        // Intent를 task로 설정 (shouldAutoApproveTeam → false for multi-agent)
        if let idx = rm.rooms.firstIndex(where: { $0.id == roomID }) {
            rm.rooms[idx].classifyIntent(.task, modifiers: [])
            rm.rooms[idx].setTaskBrief(TaskBrief(goal: "test", overallRisk: .medium))
        }

        // showTeamConfirmation을 Task로 실행 (게이트에서 대기하므로 async)
        let task = Task {
            await rm.showTeamConfirmation(roomID: roomID)
        }

        // 게이트가 설정될 때까지 잠시 대기
        try? await Task.sleep(for: .milliseconds(100))

        // pendingTeamConfirmation이 설정되어야 함 → 알림 라인을 통과했음을 증명
        #expect(rm.pendingTeamConfirmation[roomID] != nil,
                "자동 승인 불가 시 pendingTeamConfirmation이 설정되어야 합니다 (알림 호출 지점 통과)")

        // 게이트 해소
        rm.confirmTeam(roomID: roomID)
        await task.value
    }

    @Test("showTeamConfirmation — individuallyApproved면 자동 진행 (pendingTeamConfirmation 미설정)")
    func teamConfirmation_individuallyApproved_autoProceeds() async {
        let rm = makeTestRoomManager()
        let store = AgentStore()
        let master = Agent(name: "DOUGLAS", persona: "master", providerName: "P", modelName: "M", isMaster: true)
        let agent1 = Agent(name: "FE", persona: "FE", providerName: "P", modelName: "M")
        store.addAgent(master)
        store.addAgent(agent1)
        rm.configure(agentStore: store, providerManager: ProviderManager())

        let room = rm.createRoom(title: "테스트", agentIDs: [master.id, agent1.id], createdBy: .user)

        // individuallyApproved: true → 자동 진행, 게이트 없음
        await rm.showTeamConfirmation(roomID: room.id, individuallyApproved: true)

        #expect(rm.pendingTeamConfirmation[room.id] == nil,
                "개별 승인 완료 시 pendingTeamConfirmation이 설정되지 않아야 합니다")
    }

    @Test("showTeamConfirmation — 전문가·후보 모두 없으면 방 완료")
    func teamConfirmation_noAgents_completesRoom() async {
        let rm = makeTestRoomManager()
        let store = AgentStore()
        // 마스터만 있고 서브에이전트 없음
        let master = Agent(name: "DOUGLAS", persona: "master", providerName: "P", modelName: "M", isMaster: true)
        store.addAgent(master)
        rm.configure(agentStore: store, providerManager: ProviderManager())

        let room = rm.createRoom(title: "테스트", agentIDs: [master.id], createdBy: .user)

        await rm.showTeamConfirmation(roomID: room.id)

        // 에이전트/후보 모두 없으므로 방 완료
        #expect(rm.pendingTeamConfirmation[room.id] == nil)
    }
}
