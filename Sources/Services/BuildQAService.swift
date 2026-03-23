import Foundation

/// 빌드/QA 루프 실행 서비스 — RoomManager에서 추출된 도메인 서비스
/// RoomManager의 상태 변경은 콜백을 통해 위임 (의존성 역전)
enum BuildQAService {

    /// 빌드/QA 루프에서 필요한 RoomManager 기능을 추상화
    struct Host {
        /// Room의 BuildQAState 변경
        let updateBuildQA: (UUID, (inout BuildQAState) -> Void) -> Void
        /// 메시지 추가
        let appendMessage: (ChatMessage, UUID) -> Void
        /// Room 읽기 (현재 상태 확인)
        let room: (UUID) -> Room?
        /// 에이전트 실행 단계 위임
        let executeStep: (String, String, UUID, UUID, Int, Int, FileWriteTracker?) async -> Void
        /// QA 에이전트 검색
        let findQAAgent: (Room) -> UUID?
    }

    // MARK: - 빌드 루프

    /// 빌드→실패→에이전트 수정→재빌드 루프. 성공 시 true, 최대 재시도 초과 시 false.
    static func runBuildLoop(
        roomID: UUID,
        buildCommand: String,
        projectPath: String,
        fileWriteTracker: FileWriteTracker?,
        host: Host
    ) async -> Bool {
        guard let room = host.room(roomID) else { return false }
        let maxRetries = room.buildQA.maxBuildRetries

        host.updateBuildQA(roomID) { $0.startBuildLoop() }
        host.appendMessage(ChatMessage(role: .system, content: "빌드 실행 중: `\(buildCommand)`", messageType: .buildStatus), roomID)

        let result = await BuildLoopRunner.runBuild(command: buildCommand, workingDirectory: projectPath)
        host.updateBuildQA(roomID) { $0.recordBuildResult(result) }

        if result.success {
            host.updateBuildQA(roomID) { $0.recordBuildSuccess(result: result) }
            host.appendMessage(ChatMessage(role: .system, content: "빌드 성공", messageType: .buildStatus), roomID)
            return true
        }

        // 빌드 실패 → 수정 루프
        for retry in 1...maxRetries {
            guard !Task.isCancelled,
                  let currentRoom = host.room(roomID),
                  currentRoom.status == .inProgress else { return false }

            host.updateBuildQA(roomID) { $0.startFixing(retry: retry) }
            host.appendMessage(ChatMessage(
                role: .system,
                content: "빌드 실패 (시도 \(retry)/\(maxRetries)). 에이전트에게 수정 요청 중...",
                messageType: .buildStatus
            ), roomID)

            let lastOutput = host.room(roomID)?.buildQA.lastBuildResult?.output ?? ""
            let fixPrompt = BuildLoopRunner.buildFixPrompt(
                buildCommand: buildCommand, buildOutput: lastOutput,
                retryNumber: retry, maxRetries: maxRetries
            )

            if let firstAgentID = room.assignedAgentIDs.first {
                await host.executeStep(fixPrompt, "빌드 오류 수정", firstAgentID, roomID, 0, 1, fileWriteTracker)
            }

            host.updateBuildQA(roomID) { $0.startRebuilding() }
            host.appendMessage(ChatMessage(
                role: .system,
                content: "재빌드 실행 중... (시도 \(retry)/\(maxRetries))",
                messageType: .buildStatus
            ), roomID)

            let retryResult = await BuildLoopRunner.runBuild(command: buildCommand, workingDirectory: projectPath)
            host.updateBuildQA(roomID) { $0.recordBuildResult(retryResult) }

            if retryResult.success {
                host.updateBuildQA(roomID) { $0.recordBuildSuccess(result: retryResult) }
                host.appendMessage(ChatMessage(
                    role: .system,
                    content: "빌드 성공 (시도 \(retry) 후)",
                    messageType: .buildStatus
                ), roomID)
                return true
            }
        }

        host.updateBuildQA(roomID) { $0.markBuildFailed() }
        return false
    }

    // MARK: - QA 루프

    /// 테스트→실패→에이전트 수정→재테스트 루프. 성공 시 true, 최대 재시도 초과 시 false.
    static func runQALoop(
        roomID: UUID,
        testCommand: String,
        projectPath: String,
        fileWriteTracker: FileWriteTracker?,
        host: Host
    ) async -> Bool {
        guard let room = host.room(roomID) else { return false }
        let maxRetries = room.buildQA.maxQARetries

        host.updateBuildQA(roomID) { $0.startQALoop() }
        host.appendMessage(ChatMessage(role: .system, content: "테스트 실행 중: `\(testCommand)`", messageType: .qaStatus), roomID)

        let result = await BuildLoopRunner.runTests(command: testCommand, workingDirectory: projectPath)
        host.updateBuildQA(roomID) { $0.recordQAResult(result) }

        if result.success {
            host.updateBuildQA(roomID) { $0.recordQASuccess(result: result) }
            host.appendMessage(ChatMessage(role: .system, content: "테스트 통과", messageType: .qaStatus), roomID)
            return true
        }

        for retry in 1...maxRetries {
            guard !Task.isCancelled,
                  let currentRoom = host.room(roomID),
                  currentRoom.status == .inProgress else { return false }

            host.updateBuildQA(roomID) { $0.startAnalyzing(retry: retry) }
            host.appendMessage(ChatMessage(
                role: .system,
                content: "테스트 실패 (시도 \(retry)/\(maxRetries)). 에이전트에게 수정 요청 중...",
                messageType: .qaStatus
            ), roomID)

            let lastOutput = host.room(roomID)?.buildQA.lastQAResult?.output ?? ""
            let fixPrompt = BuildLoopRunner.qaFixPrompt(
                testCommand: testCommand, testOutput: lastOutput,
                retryNumber: retry, maxRetries: maxRetries
            )

            let fixAgentID = host.findQAAgent(room) ?? room.assignedAgentIDs.first
            if let agentID = fixAgentID {
                await host.executeStep(fixPrompt, "테스트 실패 수정", agentID, roomID, 0, 1, fileWriteTracker)
            }

            host.updateBuildQA(roomID) { $0.startRetesting() }
            host.appendMessage(ChatMessage(
                role: .system,
                content: "재테스트 실행 중... (시도 \(retry)/\(maxRetries))",
                messageType: .qaStatus
            ), roomID)

            let retryResult = await BuildLoopRunner.runTests(command: testCommand, workingDirectory: projectPath)
            host.updateBuildQA(roomID) { $0.recordQAResult(retryResult) }

            if retryResult.success {
                host.updateBuildQA(roomID) { $0.recordQASuccess(result: retryResult) }
                host.appendMessage(ChatMessage(
                    role: .system,
                    content: "테스트 통과 (시도 \(retry) 후)",
                    messageType: .qaStatus
                ), roomID)
                return true
            }
        }

        host.updateBuildQA(roomID) { $0.markQAFailed() }
        return false
    }
}
