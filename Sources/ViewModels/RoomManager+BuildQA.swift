import Foundation

// MARK: - 빌드/QA 루프 (BuildQAService로 위임)

extension RoomManager {

    /// BuildQAService에 전달할 Host 콜백 생성
    private func makeBuildQAHost() -> BuildQAService.Host {
        BuildQAService.Host(
            updateBuildQA: { [self] roomID, update in
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].updateBuildQA(update)
                }
            },
            appendMessage: { [self] msg, roomID in
                appendMessage(msg, to: roomID)
            },
            room: { [self] roomID in
                rooms.first(where: { $0.id == roomID })
            },
            executeStep: { [self] step, task, agentID, roomID, stepIdx, totalSteps, tracker in
                await executeStep(
                    step: step, fullTask: task, agentID: agentID,
                    roomID: roomID, stepIndex: stepIdx, totalSteps: totalSteps,
                    fileWriteTracker: tracker
                )
            },
            findQAAgent: { [self] room in qaAgentID(in: room) }
        )
    }

    /// 빌드→실패→에이전트 수정→재빌드 루프
    func runBuildLoop(
        roomID: UUID, buildCommand: String, projectPath: String,
        fileWriteTracker: FileWriteTracker?
    ) async -> Bool {
        await BuildQAService.runBuildLoop(
            roomID: roomID, buildCommand: buildCommand, projectPath: projectPath,
            fileWriteTracker: fileWriteTracker, host: makeBuildQAHost()
        )
    }

    /// 테스트→실패→에이전트 수정→재테스트 루프
    func runQALoop(
        roomID: UUID, testCommand: String, projectPath: String,
        fileWriteTracker: FileWriteTracker?
    ) async -> Bool {
        await BuildQAService.runQALoop(
            roomID: roomID, testCommand: testCommand, projectPath: projectPath,
            fileWriteTracker: fileWriteTracker, host: makeBuildQAHost()
        )
    }

    /// QA 에이전트 우선 선택
    func qaAgentID(in room: Room) -> UUID? {
        for agentID in room.assignedAgentIDs {
            if let agent = agentStore?.agents.first(where: { $0.id == agentID }),
               agent.name.lowercased().contains("qa") || agent.persona.lowercased().contains("qa") {
                return agentID
            }
        }
        return nil
    }
}
