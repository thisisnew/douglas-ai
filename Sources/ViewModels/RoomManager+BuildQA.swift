import Foundation

// MARK: - 빌드/QA 루프 (RoomManager+Discussion에서 분리)

extension RoomManager {

    // MARK: - 빌드 루프

    /// 빌드→실패→에이전트 수정→재빌드 루프. 성공 시 true, 최대 재시도 초과 시 false.
    func runBuildLoop(
        roomID: UUID,
        buildCommand: String,
        projectPath: String,
        fileWriteTracker: FileWriteTracker?
    ) async -> Bool {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return false }
        let maxRetries = room.buildQA.maxBuildRetries

        // 빌드 루프 상태 초기화
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildQA.buildLoopStatus = .building
            rooms[i].buildQA.buildRetryCount = 0
        }

        let buildMsg = ChatMessage(
            role: .system,
            content: "빌드 실행 중: `\(buildCommand)`",
            messageType: .buildStatus
        )
        appendMessage(buildMsg, to: roomID)

        let result = await BuildLoopRunner.runBuild(command: buildCommand, workingDirectory: projectPath)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildQA.lastBuildResult = result
        }

        if result.success {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildQA.buildLoopStatus = .passed
            }
            let successMsg = ChatMessage(
                role: .system,
                content: "빌드 성공",
                messageType: .buildStatus
            )
            appendMessage(successMsg, to: roomID)
            return true
        }

        // 빌드 실패 → 수정 루프
        for retry in 1...maxRetries {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { return false }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildQA.buildLoopStatus = .fixing
                rooms[i].buildQA.buildRetryCount = retry
            }

            let failMsg = ChatMessage(
                role: .system,
                content: "빌드 실패 (시도 \(retry)/\(maxRetries)). 에이전트에게 수정 요청 중...",
                messageType: .buildStatus
            )
            appendMessage(failMsg, to: roomID)

            // 첫 번째 에이전트에게 수정 요청
            let lastOutput = rooms.first(where: { $0.id == roomID })?.buildQA.lastBuildResult?.output ?? ""
            let fixPrompt = BuildLoopRunner.buildFixPrompt(
                buildCommand: buildCommand,
                buildOutput: lastOutput,
                retryNumber: retry,
                maxRetries: maxRetries
            )

            if let firstAgentID = room.assignedAgentIDs.first {
                await executeStep(
                    step: fixPrompt,
                    fullTask: "빌드 오류 수정",
                    agentID: firstAgentID,
                    roomID: roomID,
                    stepIndex: 0,
                    totalSteps: 1,
                    fileWriteTracker: fileWriteTracker
                )
            }

            // 재빌드
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildQA.buildLoopStatus = .building
            }

            let rebuildMsg = ChatMessage(
                role: .system,
                content: "재빌드 실행 중... (시도 \(retry)/\(maxRetries))",
                messageType: .buildStatus
            )
            appendMessage(rebuildMsg, to: roomID)

            let retryResult = await BuildLoopRunner.runBuild(command: buildCommand, workingDirectory: projectPath)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildQA.lastBuildResult = retryResult
            }

            if retryResult.success {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].buildQA.buildLoopStatus = .passed
                }
                let successMsg = ChatMessage(
                    role: .system,
                    content: "빌드 성공 (시도 \(retry) 후)",
                    messageType: .buildStatus
                )
                appendMessage(successMsg, to: roomID)
                return true
            }
        }

        // 최대 재시도 초과
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildQA.buildLoopStatus = .failed
        }
        return false
    }

    // MARK: - QA 루프

    /// 테스트→실패→에이전트 수정→재테스트 루프. 성공 시 true, 최대 재시도 초과 시 false.
    func runQALoop(
        roomID: UUID,
        testCommand: String,
        projectPath: String,
        fileWriteTracker: FileWriteTracker?
    ) async -> Bool {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return false }
        let maxRetries = room.buildQA.maxQARetries

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildQA.qaLoopStatus = .testing
            rooms[i].buildQA.qaRetryCount = 0
        }

        let testMsg = ChatMessage(
            role: .system,
            content: "테스트 실행 중: `\(testCommand)`",
            messageType: .qaStatus
        )
        appendMessage(testMsg, to: roomID)

        let result = await BuildLoopRunner.runTests(command: testCommand, workingDirectory: projectPath)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildQA.lastQAResult = result
        }

        if result.success {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildQA.qaLoopStatus = .passed
            }
            let successMsg = ChatMessage(
                role: .system,
                content: "테스트 통과",
                messageType: .qaStatus
            )
            appendMessage(successMsg, to: roomID)
            return true
        }

        // 테스트 실패 → 수정 루프
        for retry in 1...maxRetries {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { return false }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildQA.qaLoopStatus = .analyzing
                rooms[i].buildQA.qaRetryCount = retry
            }

            let failMsg = ChatMessage(
                role: .system,
                content: "테스트 실패 (시도 \(retry)/\(maxRetries)). 에이전트에게 수정 요청 중...",
                messageType: .qaStatus
            )
            appendMessage(failMsg, to: roomID)

            let lastOutput = rooms.first(where: { $0.id == roomID })?.buildQA.lastQAResult?.output ?? ""
            let fixPrompt = BuildLoopRunner.qaFixPrompt(
                testCommand: testCommand,
                testOutput: lastOutput,
                retryNumber: retry,
                maxRetries: maxRetries
            )

            // QA 에이전트 우선, 없으면 첫 번째 에이전트
            let fixAgentID = qaAgentID(in: room) ?? room.assignedAgentIDs.first
            if let agentID = fixAgentID {
                await executeStep(
                    step: fixPrompt,
                    fullTask: "테스트 실패 수정",
                    agentID: agentID,
                    roomID: roomID,
                    stepIndex: 0,
                    totalSteps: 1,
                    fileWriteTracker: fileWriteTracker
                )
            }

            // 재테스트
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildQA.qaLoopStatus = .testing
            }

            let retestMsg = ChatMessage(
                role: .system,
                content: "재테스트 실행 중... (시도 \(retry)/\(maxRetries))",
                messageType: .qaStatus
            )
            appendMessage(retestMsg, to: roomID)

            let retryResult = await BuildLoopRunner.runTests(command: testCommand, workingDirectory: projectPath)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildQA.lastQAResult = retryResult
            }

            if retryResult.success {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].buildQA.qaLoopStatus = .passed
                }
                let successMsg = ChatMessage(
                    role: .system,
                    content: "테스트 통과 (시도 \(retry) 후)",
                    messageType: .qaStatus
                )
                appendMessage(successMsg, to: roomID)
                return true
            }
        }

        // 최대 재시도 초과
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildQA.qaLoopStatus = .failed
        }
        return false
    }

    /// QA 에이전트 우선 선택 (이름/페르소나에 QA 키워드 포함 에이전트 우선)
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
