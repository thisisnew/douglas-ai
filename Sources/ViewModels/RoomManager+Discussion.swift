import Foundation

// MARK: - 빌드/QA 루프 + 토론 실행 (Phase 6 분리)

extension RoomManager {

    // MARK: - 빌드 루프

    /// 빌드→실패→에이전트 수정→재빌드 루프. 성공 시 true, 최대 재시도 초과 시 false.
    private func runBuildLoop(
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
    private func runQALoop(
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
    private func qaAgentID(in room: Room) -> UUID? {
        for agentID in room.assignedAgentIDs {
            if let agent = agentStore?.agents.first(where: { $0.id == agentID }),
               agent.name.lowercased().contains("qa") || agent.persona.lowercased().contains("qa") {
                return agentID
            }
        }
        return nil
    }

    // MARK: - 토론 실행

    /// 합의 기반 토론 실행 (사용자가 빈 피드백 입력 시 종료)
    /// 토론: 라운드별 자유 토론 + 사용자 체크포인트
    func executeDiscussion(roomID: UUID, topic: String) async {
        guard rooms.first(where: { $0.id == roomID }) != nil else { return }

        var round = 0
        while true {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { break }

            // ── 토론 라운드 N ──
            let roundMsg = ChatMessage(
                role: .system,
                content: "── 토론 라운드 \(round + 1) ──",
                messageType: .discussionRound
            )
            appendMessage(roundMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].discussion.currentRound = round
            }

            // 마스터 제외한 전문가만 토론 참여
            let agentIDs = executingAgentIDs(in: roomID)
            guard !agentIDs.isEmpty else { break }

            // 첫 라운드는 병렬 (히스토리 스냅샷 기준), 이후는 순차 (이전 발언 참고)
            if round == 0 && agentIDs.count > 1 {
                let frozenHistory = buildDiscussionHistory(roomID: roomID, currentAgentName: nil)
                    .map { msg in
                        ConversationMessage(role: msg.role, content: msg.content,
                                            toolCalls: nil, toolCallID: nil,
                                            attachments: nil, isError: false)
                    }
                var historyBuilder: [ConversationMessage] = []
                if let firstUserMsg = rooms.first(where: { $0.id == roomID })?.messages
                    .first(where: { $0.role == .user && $0.messageType == .text }) {
                    let imageAttachments = firstUserMsg.attachments?.filter { $0.isImage }
                    historyBuilder.append(ConversationMessage.user(firstUserMsg.content, attachments: imageAttachments))
                }
                historyBuilder.append(contentsOf: frozenHistory)
                let fullHistory = historyBuilder

                var results: [(Int, ChatMessage, Bool)] = []
                await withTaskGroup(of: (Int, ChatMessage, Bool).self) { group in
                    for (idx, agentID) in agentIDs.enumerated() {
                        group.addTask { [weak self] in
                            guard !Task.isCancelled, let self else {
                                return (idx, ChatMessage(role: .assistant, content: "", agentName: nil, messageType: .error), false)
                            }
                            let (msg, agreed) = await self.generateDiscussionResponse(
                                topic: topic, agentID: agentID, roomID: roomID,
                                round: round,
                                frozenHistory: fullHistory
                            )
                            return (idx, msg, agreed)
                        }
                    }
                    for await item in group { results.append(item) }
                }
                for (_, msg, agreed) in results.sorted(by: { $0.0 < $1.0 }) {
                    appendMessage(msg, to: roomID)
                    if agreed, let agentName = msg.agentName,
                       let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        let decision = Self.parseDecisionContent(from: msg.content) ?? "합의 도달"
                        rooms[i].discussion.decisionLog.append(DecisionEntry(
                            round: round, decision: decision, supporters: [agentName]
                        ))
                    }
                }
            } else {
                for agentID in agentIDs {
                    guard !Task.isCancelled,
                          rooms.first(where: { $0.id == roomID })?.isActive == true else { break }

                    await executeDiscussionTurn(
                        topic: topic,
                        agentID: agentID,
                        roomID: roomID,
                        round: round
                    )
                }
            }

            // 사용자 체크포인트
            let checkpointMsg = ChatMessage(
                role: .system,
                content: "토론 라운드 \(round + 1) 완료. 피드백이 있으시면 입력해주세요.",
                messageType: .userQuestion
            )
            appendMessage(checkpointMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].discussion.isCheckpoint = true
                rooms[i].transitionTo(.awaitingUserInput)
            }
            scheduleSave()

            let feedback = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
                userInputContinuations[roomID] = cont
            }
            userInputContinuations.removeValue(forKey: roomID)
            guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].discussion.isCheckpoint = false
                rooms[i].transitionTo(.inProgress)
            }

            if feedback.isEmpty {
                // "진행" → 토론 종료, 브리핑으로
                break
            } else {
                // 사용자 피드백 → answerUserQuestion에서 이미 appendMessage 됨
                let feedbackNote = ChatMessage(
                    role: .system,
                    content: "사용자 피드백을 반영하여 새 라운드를 시작합니다."
                )
                appendMessage(feedbackNote, to: roomID)
            }
            round += 1
        }

        let doneMsg = ChatMessage(role: .system, content: "토론이 완료되었습니다. 다음 단계로 넘어갑니다.")
        appendMessage(doneMsg, to: roomID)
        scheduleSave()
    }

    /// 개별 에이전트의 토론 턴. 합의 여부를 Bool로 리턴.
    @discardableResult
    func executeDiscussionTurn(
        topic: String,
        agentID: UUID,
        roomID: UUID,
        round: Int
    ) async -> Bool {
        guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return false }

        // 토론 히스토리 (이미지 첨부파일은 실제 데이터로 전달)
        let roomRef = rooms.first(where: { $0.id == roomID })
        var history: [ConversationMessage] = []
        if let firstUserMsg = roomRef?.messages.first(where: { $0.role == .user && $0.messageType == .text }) {
            let imageAttachments = firstUserMsg.attachments?.filter { $0.isImage }
            history.append(ConversationMessage.user(firstUserMsg.content, attachments: imageAttachments))
        }
        let discussionMsgs = buildDiscussionHistory(roomID: roomID, currentAgentName: agent.name)
        history.append(contentsOf: discussionMsgs.map { msg in
            ConversationMessage(role: msg.role, content: msg.content, toolCalls: nil, toolCallID: nil, attachments: nil, isError: false)
        })

        // 동료 목록 (마스터 제외 — 전문가끼리만 토론)
        let otherSpecialists = executingAgentIDs(in: roomID)
            .filter { $0 != agentID }
            .compactMap { id in agentStore?.agents.first(where: { $0.id == id }) }
        let otherNames = otherSpecialists.map { $0.name }.joined(separator: ", ")

        // intake 데이터
        let intakeText = roomRef?.clarifyContext.intakeData?.asClarifyContextString() ?? ""
        let intakeBlock = intakeText.isEmpty ? "" : "\n\(intakeText)"

        // clarify 요약 앵커링 (토론 범위 제한)
        let clarifyText = roomRef?.clarifyContext.clarifySummary ?? ""
        let anchorBlock = clarifyText.isEmpty ? "" : """

        [사용자 확인 요약 — 이 범위를 벗어나지 마세요]
        \(clarifyText)
        """

        // 에이전트 이름에서 도메인 키워드 추출하여 전문 영역 힌트 생성
        let domainHint = Self.domainHint(for: agent.name)

        let discussionPrompt = """
        [역할] 당신은 **\(agent.name)**입니다.
        \(domainHint)
        \(systemPrompt(for: agent, roomID: roomID))
        [필수 규칙]
        - 첫 문장을 반드시 **\(agent.name)의 전문 영역 시각**으로 시작하세요.
        - 예: "\(agent.name) 관점에서 보면..."
        - 동료가 이미 말한 관점을 자신의 것처럼 반복하지 마세요.
        - 동료의 영역(예: 백엔드 개발자가 아닌데 "백엔드에서는..."이라고 말하는 것)은 금지입니다.
        - 동료 발언에 응답할 때도 자신의 전문 영역 시각으로 해석하여 답하세요.

        [시스템] 필요한 외부 데이터는 이미 수집되었습니다. 도구·인증·API 연동 관련 언급을 하지 마세요.
        \(intakeBlock)\(anchorBlock)

        [회의실] \(topic)
        라운드 \(round + 1) | 동료: \(otherNames)

        첨부된 이미지나 파일이 있으면 내용을 확인하고 참고하세요.
        2-4문장으로 핵심만 말하세요. 주장에는 반드시 근거나 트레이드오프를 붙이세요.
        동료 의견에 "좋은 의견입니다"식 피상적 동의를 금지합니다. 보완, 반론, 또는 조건부 동의로 응답하세요.
        이름 헤더(**[이름]** 등)를 붙이지 마세요. UI가 화자를 표시합니다.
        발언 마지막 줄에 [합의] 또는 [계속] 태그를 붙이세요.
        """

        // 활동 추적: ProgressActivityBubble로 모델/소요시간 표시
        let progressGroupID = UUID()
        let turnStartTime = Date()

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)
            speakingAgentIDByRoom[roomID] = agentID

            let progressMsg = ChatMessage(
                role: .assistant,
                content: "\(agent.providerName) · \(agent.modelName)",
                agentName: agent.name,
                messageType: .progress,
                activityGroupID: progressGroupID
            )
            appendMessage(progressMsg, to: roomID)

            // 스트리밍용 placeholder 메시지 — 청크가 실시간으로 표시됨
            let placeholderID = UUID()
            let placeholder = ChatMessage(
                id: placeholderID, role: .assistant, content: "",
                agentName: agent.name, messageType: .discussion
            )
            appendMessage(placeholder, to: roomID)

            // 이미지 첨부가 있으면 sendMessageWithTools 사용 (이미지 데이터 전달 필요)
            // 없으면 스트리밍으로 실시간 표시
            let hasImageInHistory = history.contains { $0.attachments != nil && !($0.attachments?.isEmpty ?? true) }
            let buffer = StreamBuffer()
            let response: String
            if hasImageInHistory || !provider.supportsStreaming {
                let responseContent = try await provider.sendMessageWithTools(
                    model: agent.modelName,
                    systemPrompt: discussionPrompt,
                    messages: history,
                    tools: []
                )
                switch responseContent {
                case .text(let t): response = t
                case .toolCalls: response = "[합의]"
                case .mixed(let t, _): response = t
                }
            } else {
                let simpleHistory = history.compactMap { msg -> (role: String, content: String)? in
                    guard let content = msg.content else { return nil }
                    return (role: msg.role, content: content)
                }
                response = try await provider.sendMessageStreaming(
                    model: agent.modelName,
                    systemPrompt: discussionPrompt,
                    messages: simpleHistory,
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in
                            self.updateMessageContent(placeholderID, newContent: current, in: roomID)
                        }
                    }
                )
            }

            // 활동 추적: 응답 완료
            let turnDuration = Date().timeIntervalSince(turnStartTime)
            let durationStr = turnDuration < 60
                ? String(format: "%.1f초", turnDuration)
                : String(format: "%d분 %.0f초", Int(turnDuration) / 60, turnDuration.truncatingRemainder(dividingBy: 60))
            let resultDetail = ToolActivityDetail(
                toolName: "llm_result",
                subject: durationStr,
                contentPreview: nil, isError: false
            )
            let resultActivity = ChatMessage(
                role: .assistant,
                content: "응답 완료 (\(durationStr))",
                agentName: agent.name,
                messageType: .toolActivity,
                activityGroupID: progressGroupID,
                toolDetail: resultDetail
            )
            appendMessage(resultActivity, to: roomID)

            speakingAgentIDByRoom.removeValue(forKey: roomID)

            // 합의 감지 (퍼지 매칭 포함) 후 DecisionLog 기록
            let agreed = Self.detectConsensus(in: response)
            if agreed, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                let decision = Self.parseDecisionContent(from: response) ?? "합의 도달"
                let entry = DecisionEntry(
                    round: round,
                    decision: decision,
                    supporters: [agent.name]
                )
                rooms[i].discussion.decisionLog.append(entry)
            }
            let cleanResponse = response
                .replacingOccurrences(of: "\\[합의(?::[^\\]]*)?\\]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[계속]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 산출물 파싱 → Room에 저장
            let newArtifacts = ArtifactParser.extractArtifacts(from: cleanResponse, producedBy: agent.name)
            if !newArtifacts.isEmpty, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                for artifact in newArtifacts {
                    if let existingIdx = rooms[i].discussion.artifacts.firstIndex(where: {
                        $0.type == artifact.type && $0.title == artifact.title
                    }) {
                        var updated = artifact
                        updated.version = rooms[i].discussion.artifacts[existingIdx].version + 1
                        rooms[i].discussion.artifacts[existingIdx] = updated
                    } else {
                        rooms[i].discussion.artifacts.append(artifact)
                    }
                }
            }
            let displayResponse = ArtifactParser.stripArtifactBlocks(from: cleanResponse)

            // placeholder를 최종 정리된 텍스트로 업데이트 (환각 제거 + ~/ 확장)
            let finalText = expandTildePaths(stripHallucinatedAuthLines(stripTrailingOptions(displayResponse.isEmpty ? cleanResponse : displayResponse)))
            updateMessageContent(placeholderID, newContent: finalText, in: roomID)

            return agreed
        } catch {
            // 활동 추적: 오류
            let turnDuration = Date().timeIntervalSince(turnStartTime)
            let errDurationStr = String(format: "%.1f초", turnDuration)
            let errorDetail = ToolActivityDetail(
                toolName: "llm_error",
                subject: error.userFacingMessage,
                contentPreview: nil, isError: true
            )
            let errorActivity = ChatMessage(
                role: .assistant,
                content: "오류 (\(errDurationStr)): \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .toolActivity,
                activityGroupID: progressGroupID,
                toolDetail: errorDetail
            )
            appendMessage(errorActivity, to: roomID)

            speakingAgentIDByRoom.removeValue(forKey: roomID)
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "발언 실패: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            return false
        }
    }

    /// 병렬 실행용: 토론 응답만 생성하고 Room에 append하지 않음 (발산 라운드용)
    private func generateDiscussionResponse(
        topic: String,
        agentID: UUID,
        roomID: UUID,
        round: Int,
        frozenHistory: [ConversationMessage]
    ) async -> (message: ChatMessage, agreed: Bool) {
        guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            return (ChatMessage(role: .assistant, content: "에이전트 없음", agentName: nil, messageType: .error), false)
        }

        // 동료 정보 구성 (마스터 제외 — 전문가끼리만 토론)
        let roomRef = rooms.first(where: { $0.id == roomID })
        let otherSpecialists = executingAgentIDs(in: roomID)
            .filter { $0 != agentID }
            .compactMap { id in agentStore?.agents.first(where: { $0.id == id }) }
        let otherNames = otherSpecialists.map { $0.name }.joined(separator: ", ")

        let clarifyText = roomRef?.clarifyContext.clarifySummary ?? ""
        let anchorBlock = clarifyText.isEmpty ? "" : """

        [사용자 확인 요약 — 이 범위를 벗어나지 마세요]
        \(clarifyText)
        """

        let discussionPrompt = """
        \(systemPrompt(for: agent, roomID: roomID))
        [시스템] 필요한 외부 데이터는 이미 수집되었습니다. 도구·인증·API 연동 관련 언급을 하지 마세요.
        \(anchorBlock)

        [회의실] \(topic)
        라운드 \(round + 1) | 동료: \(otherNames)
        전문 영역에서 의견을 제시하고, 보완/반론/조건부 동의하세요. 근거 없는 단순 동의는 금지합니다.

        첨부된 이미지나 파일이 있으면 내용을 확인하고 참고하세요.
        2-4문장으로 핵심만 말하세요. 주장에는 반드시 근거나 트레이드오프를 붙이세요.
        이름 헤더(**[이름]** 등)를 붙이지 마세요. UI가 화자를 표시합니다.
        발언 마지막 줄에 [합의] 또는 [계속] 태그를 붙이세요.
        """

        // 활동 추적: ProgressActivityBubble로 모델/소요시간 표시
        let progressGroupID = UUID()
        let turnStartTime = Date()

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)

            let progressMsg = ChatMessage(
                role: .assistant,
                content: "\(agent.name) 발언 중…",
                agentName: agent.name,
                messageType: .progress,
                activityGroupID: progressGroupID
            )
            appendMessage(progressMsg, to: roomID)

            // 병렬 실행이므로 비스트리밍 (placeholder 충돌 방지)
            let responseContent = try await provider.sendMessageWithTools(
                model: agent.modelName,
                systemPrompt: discussionPrompt,
                messages: frozenHistory,
                tools: []
            )
            let response: String
            switch responseContent {
            case .text(let t): response = t
            case .toolCalls: response = "[합의]"
            case .mixed(let t, _): response = t
            }

            // 활동 추적: 응답 완료
            let turnDuration = Date().timeIntervalSince(turnStartTime)
            let durationStr = turnDuration < 60
                ? String(format: "%.1f초", turnDuration)
                : String(format: "%d분 %.0f초", Int(turnDuration) / 60, turnDuration.truncatingRemainder(dividingBy: 60))
            let resultDetail = ToolActivityDetail(
                toolName: "llm_result",
                subject: durationStr,
                contentPreview: nil, isError: false
            )
            let resultActivity = ChatMessage(
                role: .assistant,
                content: "응답 완료 (\(durationStr))",
                agentName: agent.name,
                messageType: .toolActivity,
                activityGroupID: progressGroupID,
                toolDetail: resultDetail
            )
            appendMessage(resultActivity, to: roomID)

            agentStore?.updateStatus(agentID: agentID, status: .idle)

            let agreed = Self.detectConsensus(in: response)
            let cleanResponse = response
                .replacingOccurrences(of: "\\[합의(?::[^\\]]*)?\\]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[계속]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayResponse = ArtifactParser.stripArtifactBlocks(from: cleanResponse)

            let finalText = expandTildePaths(stripHallucinatedAuthLines(stripTrailingOptions(displayResponse.isEmpty ? cleanResponse : displayResponse)))
            let msg = ChatMessage(
                role: .assistant,
                content: finalText,
                agentName: agent.name,
                messageType: .discussion
            )
            return (msg, agreed)
        } catch {
            // 활동 추적: 오류
            let turnDuration = Date().timeIntervalSince(turnStartTime)
            let errDurationStr = String(format: "%.1f초", turnDuration)
            let errorDetail = ToolActivityDetail(
                toolName: "llm_error",
                subject: error.userFacingMessage,
                contentPreview: nil, isError: true
            )
            let errorActivity = ChatMessage(
                role: .assistant,
                content: "오류 (\(errDurationStr)): \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .toolActivity,
                activityGroupID: progressGroupID,
                toolDetail: errorDetail
            )
            appendMessage(errorActivity, to: roomID)

            agentStore?.updateStatus(agentID: agentID, status: .idle)
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "발언 실패: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            return (errorMsg, false)
        }
    }

    /// 토론 브리핑 생성 (컨텍스트 압축)
    func generateBriefing(roomID: UUID, topic: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        let history = buildDiscussionHistory(roomID: roomID, currentAgentName: nil)

        // 토론 전문을 아카이브에 기록 (브리핑 요약 전 원본 보존)
        let fullLog = history.map { "[\($0.role)] \($0.content)" }.joined(separator: "\n\n")
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].discussion.fullDiscussionLog = fullLog
        }

        // 산출물 목록도 포함
        let artifactList = room.discussion.artifacts.isEmpty ? "" :
            "\n\n산출물 목록:\n" + room.discussion.artifacts.map { "- [\($0.type.displayName)] \($0.title)" }.joined(separator: "\n")

        // 원래 사용자 요청 앵커링
        let originalContext: String
        if let summary = room.clarifyContext.clarifySummary {
            originalContext = "[원래 사용자 요청]\n\(summary)\n\n"
        } else {
            originalContext = ""
        }

        let briefingPrompt = """
        \(originalContext)토론 내용을 분석하여 실행팀을 위한 브리핑 문서를 JSON으로 작성하세요.\(artifactList)

        반드시 아래 형식의 JSON으로만 응답하세요:
        {"summary": "작업 요약 2-3문장", "key_decisions": ["결정1", "결정2"], "agent_responsibilities": {"에이전트명": "담당역할"}, "open_issues": ["미결사항"]}

        규칙:
        - summary: 팀이 합의한 방향과 핵심 목표 (2-3문장). 반드시 원래 사용자 요청 범위 내에서 작성
        - key_decisions: 토론에서 확정된 결정사항 (3-5개)
        - agent_responsibilities: 각 참여자의 담당 역할 (토론에서 드러난 전문성 기반)
        - open_issues: 추가 논의가 필요한 미결 사항 (없으면 빈 배열)
        - 반드시 유효한 JSON으로만 응답하세요
        """

        speakingAgentIDByRoom[roomID] = firstAgentID

        do {
            let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "토론 브리핑을 생성하는 중…",
                agentName: agent.name,
                modelName: lightModel,
                providerName: agent.providerName
            ) { _ in
                // sendRouterMessage: 도구 비활성화 (브리핑 요약 중 파일 수정 방지)
                try await provider.sendRouterMessage(
                    model: lightModel,
                    systemPrompt: briefingPrompt,
                    messages: history
                )
            }

            speakingAgentIDByRoom.removeValue(forKey: roomID)

            // JSON 파싱 → RoomBriefing
            if let briefing = parseBriefing(from: response) {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].discussion.briefing = briefing
                }
                let reply = ChatMessage(
                    role: .assistant,
                    content: briefing.asContextString(),
                    agentName: "토론 정리",
                    messageType: .summary
                )
                appendMessage(reply, to: roomID)
            } else {
                // JSON 파싱 실패 → 폴백 브리핑
                let fallback = RoomBriefing(
                    summary: response.prefix(500).description,
                    keyDecisions: [],
                    agentResponsibilities: [:],
                    openIssues: []
                )
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].discussion.briefing = fallback
                }
                let reply = ChatMessage(
                    role: .assistant,
                    content: response,
                    agentName: "토론 정리",
                    messageType: .summary
                )
                appendMessage(reply, to: roomID)
            }
        } catch {
            speakingAgentIDByRoom.removeValue(forKey: roomID)
            let errorMsg = ChatMessage(
                role: .system,
                content: "브리핑 생성 실패: \(error.userFacingMessage)",
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }
    }

    /// 브리핑 JSON 파싱
    private func parseBriefing(from response: String) -> RoomBriefing? {
        let jsonString = extractJSON(from: response)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["summary"] as? String else {
            return nil
        }
        let keyDecisions = json["key_decisions"] as? [String] ?? []
        let responsibilities = json["agent_responsibilities"] as? [String: String] ?? [:]
        let openIssues = json["open_issues"] as? [String] ?? []
        return RoomBriefing(
            summary: summary,
            keyDecisions: keyDecisions,
            agentResponsibilities: responsibilities,
            openIssues: openIssues
        )
    }

    /// 토론용 히스토리 빌드 (에이전트 이름을 명시하여 누가 말했는지 구분)
    func buildDiscussionHistory(roomID: UUID, currentAgentName: String?) -> [(role: String, content: String)] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.messages
            .filter { $0.messageType == .text || $0.messageType == .discussion || $0.messageType == .discussionRound }
            .suffix(20)
            .map { msg in
                let role: String
                var content: String
                switch msg.role {
                case .user:
                    role = "user"
                    content = msg.content
                case .assistant:
                    // 자신의 발언은 assistant, 다른 에이전트 발언은 user로 (컨텍스트 구분)
                    if let agentName = msg.agentName, agentName == currentAgentName {
                        role = "assistant"
                        content = msg.content
                    } else {
                        role = "user"
                        content = "[\(msg.agentName ?? "에이전트")의 발언]: \(msg.content)"
                    }
                case .system:
                    role = "user"
                    content = "[시스템]: \(msg.content)"
                }
                // 토큰 절감: 메시지당 최대 800자
                if content.count > 800 {
                    content = String(content.prefix(800)) + "…"
                }
                return (role: role, content: content)
            }
    }

    // MARK: - 도메인 힌트

    /// 에이전트 이름에서 전문 영역 힌트를 생성 (토론 시 역할 혼동 방지)
    static func domainHint(for agentName: String) -> String {
        let name = agentName.lowercased()
        if name.contains("프론트엔드") || name.contains("frontend") || name.contains("ui") {
            return """

            [전문 영역 — 반드시 준수] 당신은 프론트엔드 전문가입니다. 아래 영역만 다루세요:
            UI/UX, 클라이언트 상태관리, 컴포넌트 설계, 렌더링 성능, 브라우저 호환성, 반응형 디자인, 접근성, CSS/스타일링, 프론트엔드 프레임워크(React, Vue, Svelte 등)
            [금지] 백엔드, 서버, 데이터베이스, API 설계, 인프라에 대해 말하지 마세요. "백엔드에서는", "서버 측에서는"이라는 표현을 사용하면 안 됩니다. 주제가 백엔드와 관련되더라도 반드시 프론트엔드 시각으로만 해석하세요.
            """
        } else if name.contains("백엔드") || name.contains("backend") || name.contains("서버") {
            return """

            [전문 영역 — 반드시 준수] 당신은 백엔드 전문가입니다. 아래 영역만 다루세요:
            API 설계, 데이터베이스, 서버 아키텍처, 인증/보안, 성능 최적화, 인프라, 마이크로서비스
            [금지] 프론트엔드, UI/UX, 컴포넌트, 렌더링, CSS에 대해 말하지 마세요. "프론트엔드에서는", "클라이언트 측에서는"이라는 표현을 사용하면 안 됩니다. 주제가 프론트엔드와 관련되더라도 반드시 백엔드 시각으로만 해석하세요.
            """
        } else if name.contains("qa") || name.contains("테스트") || name.contains("품질") {
            return """

            [전문 영역] 테스트 전략, 품질 보증, 자동화 테스트, 버그 트래킹, 성능 테스트, 보안 테스트
            - "QA/테스트 관점에서"로 시작하세요.
            """
        } else if name.contains("디자인") || name.contains("design") || name.contains("ux") {
            return """

            [전문 영역] 사용자 경험, 인터페이스 디자인, 디자인 시스템, 프로토타이핑, 사용성 테스트, 접근성
            - "디자인 관점에서"로 시작하세요.
            """
        } else if name.contains("devops") || name.contains("인프라") || name.contains("sre") {
            return """

            [전문 영역] CI/CD, 컨테이너, 클라우드 인프라, 모니터링, 배포 전략, IaC
            - "DevOps/인프라 관점에서"로 시작하세요.
            """
        } else if name.contains("기획") || name.contains("pm") || name.contains("프로덕트") {
            return """

            [전문 영역] 제품 전략, 요구사항 분석, 로드맵, 사용자 리서치, 비즈니스 가치, 우선순위
            - "기획/PM 관점에서"로 시작하세요.
            """
        } else if name.contains("리서치") || name.contains("분석") || name.contains("research") {
            return """

            [전문 영역] 시장 조사, 데이터 분석, 트렌드 파악, 경쟁사 분석, 사용자 리서치
            - "리서치/분석 관점에서"로 시작하세요.
            """
        }
        return ""
    }

    // MARK: - Turn 2 발언 순서 파싱

    /// LLM 응답에서 에이전트 발언 순서 파싱
    /// 응답 형식: {"order": ["에이전트1", "에이전트2"], "reason": "이유"}
    /// 모든 에이전트가 포함되어야 하며, 불일치 시 nil 반환 (원래 순서 폴백)
    static func parseDiscussionOrder(from response: String, agentNames: [String]) -> [String]? {
        DiscussionOrderParser.parse(from: response, agentNames: agentNames)
    }
}

// MARK: - 토론 순서 파서

/// Turn 2 발언 순서 JSON 파싱 유틸리티
enum DiscussionOrderParser {
    /// LLM 응답에서 발언 순서 파싱. 전원 포함 필수, 불일치 시 nil.
    static func parse(from response: String, agentNames: [String]) -> [String]? {
        // JSON 추출 (코드블록 지원)
        let jsonString: String
        if let codeBlockRange = response.range(of: "```"),
           let endRange = response.range(of: "```", range: codeBlockRange.upperBound..<response.endIndex) {
            var block = String(response[codeBlockRange.upperBound..<endRange.lowerBound])
            // ```json 접두사 제거
            if block.hasPrefix("json") { block = String(block.dropFirst(4)) }
            jsonString = block.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let order = json["order"] as? [String] else {
            return nil
        }

        // 전원 포함 검증 (에이전트 수 일치 + 모든 이름 포함)
        let nameSet = Set(agentNames)
        let orderSet = Set(order)
        guard order.count == agentNames.count, orderSet == nameSet else {
            return nil
        }

        return order
    }
}
