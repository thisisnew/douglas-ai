import Foundation

// MARK: - Execution Phases (Design + Build + Review + Deliver + Legacy)

extension RoomManager {

    func executeDesignPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let specialists = executingAgentIDs(in: roomID)
        let room = rooms[idx]

        // 전문가 1명: intent에 따라 분기
        if specialists.count < 2 {
            // 문서 작업은 Design(계획 수립) 스킵 → Build에서 handleDocumentOutput 직행
            if room.workflowState.autoDocOutput {
                return
            }
            if room.workflowState.intent?.isDiscussionLike == true {
                await executeSoloDiscussion(roomID: roomID, task: task, room: room)
            } else {
                await executeSoloDesign(roomID: roomID, task: task, room: room)
            }
            return
        }

        // TaskBrief 기반 컨텍스트
        let intakeText = room.clarifyContext.intakeData?.asClarifyContextString() ?? ""
        let intakeBlock = intakeText.isEmpty ? "" : "\n\(intakeText)"
        let projectPathsBlock = room.effectiveProjectPaths.isEmpty ? "" : "\n[프로젝트 경로]\n" + room.effectiveProjectPaths.map { "- \($0)" }.joined(separator: "\n")

        let briefContext: String
        if let brief = room.taskBrief {
            briefContext = """
            [작업 브리프]
            목표: \(brief.goal)
            제약: \(brief.constraints.joined(separator: ", "))
            성공기준: \(brief.successCriteria.joined(separator: ", "))
            비목표: \(brief.nonGoals.joined(separator: ", "))
            위험도: \(brief.overallRisk.rawValue)
            산출물 유형: \(brief.outputType.rawValue)
            \(intakeBlock)\(projectPathsBlock)
            """
        } else {
            briefContext = (room.clarifyContext.clarifySummary ?? task) + intakeBlock + projectPathsBlock
        }

        // --- 멀티에이전트: 통합 토론 프로토콜 ---
        // discussion/task 모두 동일한 토론 (의견 → 상호 피드백 → DOUGLAS 종합)

        // DebateMode 결정: 에이전트 역할 겹침 + 주제 키워드 + IntentModifier 기반
        let agentRoles = specialists.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })?.name
        }
        let modifiers = IntentClassifier.extractModifiers(from: task)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].startDiscussion(topic: task, agentRoles: agentRoles, modifiers: modifiers)
        }

        await executeDiscussionDesign(roomID: roomID, task: task, briefContext: briefContext, specialists: specialists)

        // task intent: 토론 결과를 바탕으로 실행 계획 생성 + 승인
        if room.workflowState.intent?.isDiscussionLike != true {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            let discussionOutput = rooms.first(where: { $0.id == roomID })?.clarifyContext.clarifySummary ?? ""

            if rooms.first(where: { $0.id == roomID })?.plan == nil {
                let plan = await requestPlan(roomID: roomID, task: task, designOutput: discussionOutput)
                if let plan, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].setPlan(plan)
                }
            }

            guard rooms.first(where: { $0.id == roomID })?.plan != nil else {
                appendMessage(ChatMessage(
                    role: .system,
                    content: "계획 수립에 실패했습니다. 토론 결과를 바탕으로 바로 실행합니다.",
                    messageType: .progress
                ), to: roomID)
                scheduleSave()
                return
            }

            let approved = await awaitPlanApproval(roomID: roomID, task: task, designOutput: discussionOutput)
            if !approved {
                return
            }
            scheduleSave()
        }
    }

    /// workModes 기반 RuntimeRole 배정 (4d)
    func assignDesignRoles(specialists: [UUID]) -> (creator: UUID, reviewer: UUID, planner: UUID?) {
        guard specialists.count >= 2 else {
            return (specialists[0], specialists[0], nil)
        }

        var creatorID: UUID?
        var reviewerID: UUID?
        var plannerID: UUID?

        for id in specialists {
            guard let agent = agentStore?.agents.first(where: { $0.id == id }) else { continue }
            if creatorID == nil && agent.workModes.contains(.create) { creatorID = id }
            // reviewer는 creator와 반드시 다른 에이전트여야 함
            if reviewerID == nil && agent.workModes.contains(.review) && id != creatorID { reviewerID = id }
            if plannerID == nil && agent.workModes.contains(.plan) { plannerID = id }
        }

        // 폴백: 지정 안 된 역할은 순서대로 할당
        let creator = creatorID ?? specialists[0]
        let reviewer = reviewerID ?? specialists.first(where: { $0 != creator }) ?? specialists[0]
        let planner = specialists.count >= 3 ? (plannerID ?? specialists.first(where: { $0 != creator && $0 != reviewer })) : nil

        return (creator, reviewer, planner)
    }

    // MARK: - 토론 모드 Design (analysis/answer)

    /// Turn 2 발언 순서를 LLM이 안건 기반으로 결정
    /// 실패 시 원래 순서(agentInfos) 그대로 반환
    private func determineTurn2Order(
        roomID: UUID,
        task: String,
        opinions: [(name: String, content: String)],
        agentInfos: [(id: UUID, agent: Agent, provider: any AIProvider)]
    ) async -> [(id: UUID, agent: Agent, provider: any AIProvider)] {
        // 에이전트 2명 미만이면 순서 결정 불필요
        guard agentInfos.count >= 2 else { return agentInfos }

        let agentNames = agentInfos.map { $0.agent.name }
        let opinionsText = opinions.map { "[\($0.name)] \($0.content.prefix(200))" }.joined(separator: "\n")

        // 마스터 에이전트의 프로바이더로 light model 호출
        guard let masterAgent = agentStore?.masterAgent,
              let provider = providerManager?.provider(named: masterAgent.providerName) else {
            return agentInfos
        }
        let lightModel = providerManager?.lightModelName(for: masterAgent.providerName) ?? masterAgent.modelName

        let orderSystemPrompt = """
        당신은 토론 진행자입니다. 아래 안건과 전문가 의견을 보고, 상호 피드백(Turn 2)의 최적 발언 순서를 결정하세요.

        원칙:
        - 안건의 핵심 도메인을 담당하는 전문가가 먼저 발언합니다.
        - 의존 관계가 있으면 상위(결정권자)가 먼저, 하위(수용자)가 나중에 발언합니다.
          예: API 설계 → 프론트엔드 (백엔드가 먼저), UI 리뉴얼 → API 연동 (프론트엔드가 먼저)
        - 나중에 발언하는 전문가는 앞선 피드백을 모두 참고할 수 있으므로 더 종합적인 의견을 낼 수 있습니다.

        반드시 아래 JSON 형식으로만 응답하세요:
        {"order": ["에이전트1", "에이전트2", ...], "reason": "순서 결정 이유 (1문장)"}
        """

        let userMessage = """
        [안건] \(task)

        [Turn 1 의견]
        \(opinionsText)

        [전문가 목록] \(agentNames.joined(separator: ", "))
        """

        do {
            let response = try await provider.sendRouterMessage(
                model: lightModel,
                systemPrompt: orderSystemPrompt,
                messages: [("user", userMessage)]
            )

            if let orderedNames = DiscussionOrderParser.parse(from: response, agentNames: agentNames) {
                // 파싱 성공 → agentInfos를 orderedNames 순서로 재배열
                let reordered = orderedNames.compactMap { name in
                    agentInfos.first(where: { $0.agent.name == name })
                }
                if reordered.count == agentInfos.count {
                    return reordered
                }
            }
        } catch {
            // LLM 호출 실패 → 원래 순서 폴백 (토론 진행에 영향 없음)
            print("[DOUGLAS] Turn 2 순서 결정 실패: \(error.localizedDescription) → 원래 순서로 폴백")
        }

        return agentInfos
    }

    /// 토론 모드: 전문가 각자 의견 제시 → 상호 피드백(LLM 순서 결정) → DOUGLAS 종합
    /// Build/Review 단계 없이 Design 내에서 토론 완결
    func executeDiscussionDesign(roomID: UUID, task: String, briefContext: String, specialists: [UUID]) async {
        let startMsg = ChatMessage(
            role: .system,
            content: "전문가 토론을 시작합니다.",
            messageType: .phaseTransition
        )
        appendMessage(startMsg, to: roomID)

        // 전문가 에이전트 정보 수집
        let agentInfos: [(id: UUID, agent: Agent, provider: any AIProvider)] = specialists.compactMap { id in
            guard let agent = agentStore?.agents.first(where: { $0.id == id }),
                  let provider = providerManager?.provider(named: agent.providerName) else { return nil }
            return (id, agent, provider)
        }
        guard agentInfos.count >= 2 else { return }

        // 첫 사용자 메시지의 이미지 첨부파일 (토론에서 이미지 참조용)
        let firstUserMsg = rooms.first(where: { $0.id == roomID })?.messages
            .first(where: { $0.role == .user && $0.messageType == .text })
        let imageAttachments = firstUserMsg?.attachments?.filter { $0.isImage }
        let hasImages = imageAttachments != nil && !(imageAttachments?.isEmpty ?? true)

        let discussionTone = """
        [절대 규칙 — 위반 시 응답 거부됩니다]
        1. 분량: 최대 4문장. 4문장을 초과하면 응답이 잘립니다. 절대 초과 금지.
        2. 서식: **볼드**, ##헤더, 번호 목록, 테이블 사용 금지. 순수 텍스트만 쓰세요.
        3. 톤: 주장에는 반드시 근거나 트레이드오프를 붙이세요. 보고서나 에세이 형식은 금지하되, "~라고 봅니다. 왜냐하면 ~" 형태로 논거를 제시하세요.
        4. 이름 헤더(**[이름]** 등) 금지. UI가 화자를 이미 표시합니다.
        5. 한 가지 핵심 포인트에 집중하세요. 여러 주제를 나열하지 마세요.
        6. 자신의 전문 영역에 대해서만 말하세요. 다른 전문가의 영역을 설명하거나 분석하지 마세요.
           예: 프론트엔드 개발자는 백엔드 기술을, 백엔드 개발자는 프론트엔드 기술을 직접 설명하면 안 됩니다.
        """

        // --- Turn 1: 각 전문가가 자기 관점에서 의견 제시 (병렬) ---
        var opinions: [(name: String, content: String)] = []

        // 태스크 그룹 진입 전 시스템 프롬프트 미리 계산 (@MainActor 격리)
        let agentSystemPrompts = Dictionary(uniqueKeysWithValues: agentInfos.map { ($0.agent.id, systemPrompt(for: $0.agent, roomID: roomID)) })

        let turn1ProgressMsg = ChatMessage(role: .system, content: "각 전문가 의견 수렴 중", messageType: .progress)
        appendMessage(turn1ProgressMsg, to: roomID)

        await withTaskGroup(of: (String, String, UUID).self) { group in
            for info in agentInfos {
                let agentPrompt = agentSystemPrompts[info.agent.id] ?? info.agent.resolvedSystemPrompt
                group.addTask { [self] in
                    guard !Task.isCancelled else { return ("", "", info.id) }

                    let prompt = """
                    \(agentPrompt)

                    당신은 **\(info.agent.name)**입니다. 오직 자신의 전문 영역에 대해서만 발언하세요.
                    다른 분야(예: 프론트엔드 개발자가 백엔드를, 백엔드 개발자가 프론트엔드를)를 설명하면 안 됩니다.

                    \(discussionTone)

                    \(briefContext)
                    """

                    let placeholderID = UUID()
                    await MainActor.run { [self] in
                        self.speakingAgentIDByRoom[roomID] = info.id
                        self.appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: info.agent.name), to: roomID)
                        self.appendMessage(ChatMessage(
                            role: .assistant, content: "\(info.agent.name) 의견 작성 중",
                            agentName: info.agent.name, messageType: .toolActivity,
                            activityGroupID: turn1ProgressMsg.id,
                            toolDetail: ToolActivityDetail(toolName: "llm_call", subject: "\(info.agent.providerName) · \(info.agent.modelName)", contentPreview: nil, isError: false)
                        ), to: roomID)
                    }

                    do {
                        let userContent = "다음 주제에 대해 당신의 의견을 말해주세요:\n\n\(task)"
                        let result: String

                        // 이미지가 있으면 sendMessageWithTools로 이미지 데이터 전달
                        if hasImages {
                            let messages = [ConversationMessage.user(userContent, attachments: imageAttachments)]
                            let responseContent = try await info.provider.sendMessageWithTools(
                                model: info.agent.modelName,
                                systemPrompt: prompt,
                                messages: messages,
                                tools: []
                            )
                            switch responseContent {
                            case .text(let t): result = t
                            case .toolCalls: result = ""
                            case .mixed(let t, _): result = t
                            }
                        } else {
                            let buffer = StreamBuffer()
                            result = try await info.provider.sendMessageStreaming(
                                model: info.agent.modelName,
                                systemPrompt: prompt,
                                messages: [("user", userContent)],
                                onChunk: { [weak self] chunk in
                                    guard let self else { return }
                                    let current = buffer.append(chunk)
                                    Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                                }
                            )
                        }
                        await MainActor.run { [self] in
                            self.updateMessageContent(placeholderID, newContent: result, in: roomID)
                        }
                        return (info.agent.name, result, info.id)
                    } catch {
                        await MainActor.run { [self] in
                            self.updateMessageContent(placeholderID, newContent: "의견 작성 오류: \(error.localizedDescription)", in: roomID)
                        }
                        return (info.agent.name, "", info.id)
                    }
                }
            }
            for await (name, content, _) in group {
                if !content.isEmpty {
                    opinions.append((name, content))
                }
            }
        }

        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }
        guard !opinions.isEmpty else { return }

        // 사용자 체크포인트: Turn 1 의견 확인 후 피드백 기회
        let checkpoint1Msg = ChatMessage(
            role: .system,
            content: "전문가 의견이 나왔습니다. 의견이 있으시면 입력해주세요. 없으면 그대로 진행합니다.",
            messageType: .userQuestion
        )
        appendMessage(checkpoint1Msg, to: roomID)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].discussion.isCheckpoint = true
            rooms[i].transitionTo(.awaitingUserInput)
        }
        syncAgentStatuses()
        scheduleSave()

        let userFeedback1: String = await approvalGates.waitForUserInput(roomID: roomID)

        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].discussion.isCheckpoint = false
            rooms[i].transitionTo(.inProgress)
        }

        // 사용자 피드백이 있으면 Turn 2 컨텍스트에 포함
        if !userFeedback1.isEmpty {
            opinions.append(("사용자", userFeedback1))
        }

        // --- Turn 2 발언 순서 결정: LLM이 안건 기반으로 최적 순서 판단 ---
        let orderedAgentInfos = await determineTurn2Order(
            roomID: roomID, task: task, opinions: opinions, agentInfos: agentInfos
        )

        // --- Turn 2: 상호 피드백 (LLM이 결정한 순서) ---
        let turn2ProgressMsg = ChatMessage(role: .system, content: "상호 피드백 진행 중", messageType: .progress)
        appendMessage(turn2ProgressMsg, to: roomID)

        var feedbacks: [(name: String, content: String)] = []

        for info in orderedAgentInfos {
            guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { break }

            let othersOpinions = opinions.filter { $0.name != info.agent.name }
            guard !othersOpinions.isEmpty else { continue }

            // 이전 에이전트의 피드백도 컨텍스트에 포함
            let othersText = othersOpinions.map { "[\($0.name)]\n\($0.content)" }.joined(separator: "\n\n")
            let priorFeedbackText = feedbacks.isEmpty ? "" :
                "\n\n--- 이미 나온 피드백 ---\n" + feedbacks.map { "[\($0.name)]\n\($0.content)" }.joined(separator: "\n\n")

            // debateMode 기반 Turn 2 프롬프트 (Strategy 패턴)
            let currentDebateMode = rooms.first(where: { $0.id == roomID })?.discussion.debateMode
            let strategyPrompt = currentDebateMode?.strategy.turn2Prompt(
                agentRole: info.agent.name,
                otherOpinions: othersText + priorFeedbackText
            )

            let prompt: String
            if let strategyPrompt {
                prompt = """
                \(systemPrompt(for: info.agent, roomID: roomID))

                \(strategyPrompt)

                \(discussionTone)
                추가 규칙:
                - 절대 3문장을 초과하지 마세요.
                - 이미 나온 의견을 반복하지 마세요.
                """
            } else {
                // debateMode 미설정 시 기존 프롬프트 폴백
                prompt = """
                \(systemPrompt(for: info.agent, roomID: roomID))

                다른 전문가의 의견을 읽고, 당신의 전문 영역에서 빈틈이나 보완점을 짚어주세요.

                \(discussionTone)
                추가 규칙:
                - 동의만 하지 마세요. 반드시 보완, 반론, 또는 조건부 동의를 2-3문장으로 제시하세요. 절대 3문장을 초과하지 마세요.
                - "좋은 의견입니다", "동의합니다"로 시작하는 것을 금지합니다. 바로 논점으로 진입하세요.
                - 이미 나온 의견을 반복하지 마세요.
                """
            }

            let placeholderID = UUID()
            speakingAgentIDByRoom[roomID] = info.id
            appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: info.agent.name), to: roomID)
            appendMessage(ChatMessage(
                role: .assistant, content: "\(info.agent.name) 피드백 작성 중",
                agentName: info.agent.name, messageType: .toolActivity,
                activityGroupID: turn2ProgressMsg.id,
                toolDetail: ToolActivityDetail(toolName: "llm_call", subject: "\(info.agent.providerName) · \(info.agent.modelName)", contentPreview: nil, isError: false)
            ), to: roomID)

            do {
                let buffer = StreamBuffer()
                let result = try await info.provider.sendMessageStreaming(
                    model: info.agent.modelName,
                    systemPrompt: prompt,
                    messages: [("user", "다른 전문가들의 의견입니다:\n\n\(othersText)\(priorFeedbackText)\n\n이에 대해 반응해주세요.")],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: result, in: roomID)
                if !result.isEmpty {
                    feedbacks.append((info.agent.name, result))
                }
            } catch {
                // 피드백 실패 → 플레이스홀더에 오류 표시하고 계속 진행
                updateMessageContent(placeholderID, newContent: "피드백 작성 오류: \(error.localizedDescription)", in: roomID)
            }
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // 사용자 체크포인트: Turn 2 피드백 확인 후 종합 전 의견 반영 기회
        let checkpoint2Msg = ChatMessage(
            role: .system,
            content: "피드백이 완료되었습니다. 추가 의견이 있으시면 입력해주세요. 없으면 종합 정리로 진행합니다.",
            messageType: .userQuestion
        )
        appendMessage(checkpoint2Msg, to: roomID)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].discussion.isCheckpoint = true
            rooms[i].transitionTo(.awaitingUserInput)
        }
        syncAgentStatuses()
        scheduleSave()

        let userFeedback2: String = await approvalGates.waitForUserInput(roomID: roomID)

        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].discussion.isCheckpoint = false
            rooms[i].transitionTo(.inProgress)
        }

        // 사용자 피드백이 있으면 종합에 포함
        if !userFeedback2.isEmpty {
            feedbacks.append(("사용자", userFeedback2))
        }

        // --- DOUGLAS 진행자 종합 정리 ---
        let discussionSummary = opinions.map { "[\($0.name) 의견]\n\($0.content)" }.joined(separator: "\n\n")
            + "\n\n---\n\n"
            + feedbacks.map { "[\($0.name) 피드백]\n\($0.content)" }.joined(separator: "\n\n")

        // 토론 결과를 room에 저장 (workLog 등에서 참조)
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].appendDiscussionContext(discussionSummary)
        }

        let masterAgent = agentStore?.masterAgent
        let masterProvider = masterAgent.flatMap { providerManager?.provider(named: $0.providerName) }

        if let master = masterAgent, let provider = masterProvider {
            let synthesisProgressMsg = ChatMessage(role: .system, content: "토론 결과를 종합합니다.", messageType: .progress)
            appendMessage(synthesisProgressMsg, to: roomID)

            let isResearch = rooms.first(where: { $0.id == roomID })?.workflowState.intent == .research
            let synthesisPrompt: String
            if isResearch {
                synthesisPrompt = PromptCompositionService.researchSynthesisPrompt()
            } else {
                synthesisPrompt = PromptCompositionService.discussionSynthesisPrompt()
            }

            let placeholderID = UUID()
            speakingAgentIDByRoom[roomID] = master.id
            appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: master.name), to: roomID)
            appendMessage(ChatMessage(
                role: .assistant, content: "토론 결과 종합 중",
                agentName: master.name, messageType: .toolActivity,
                activityGroupID: synthesisProgressMsg.id,
                toolDetail: ToolActivityDetail(toolName: "llm_call", subject: "\(master.providerName) · \(master.modelName)", contentPreview: nil, isError: false)
            ), to: roomID)

            do {
                let buffer = StreamBuffer()
                let result = try await provider.sendMessageStreaming(
                    model: master.modelName,
                    systemPrompt: synthesisPrompt,
                    messages: [("user", "다음 토론 내용을 종합해주세요:\n\n\(discussionSummary)")],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: result, in: roomID)
            } catch {
                updateMessageContent(placeholderID, newContent: "종합 정리 중 오류가 발생했습니다.", in: roomID)
            }

            speakingAgentIDByRoom.removeValue(forKey: roomID)
        }

        scheduleSave()
    }

    /// 계획 승인 루프: 사용자가 승인할 때까지 계획 재수립 반복
    private func awaitPlanApproval(roomID: UUID, task: String, designOutput: String? = nil) async -> Bool {
        while true {
            guard !Task.isCancelled,
                  let room = rooms.first(where: { $0.id == roomID }),
                  room.isActive, room.plan != nil else { return false }

            let plan = room.plan!
            let stepsDesc = plan.steps.enumerated().map { i, s in
                let risk = s.riskLevel == .low ? "" : " [\(s.riskLevel.displayName)]"
                return "\(i + 1). \(s.text)\(risk)"
            }.joined(separator: "\n")

            // high-risk 단계 경고
            let highRiskSteps = plan.steps.enumerated().filter { $0.element.riskLevel != .low }
            let highRiskWarning: String
            if highRiskSteps.isEmpty {
                highRiskWarning = ""
            } else {
                let listing = highRiskSteps.map { "- 단계 \($0.offset + 1): \($0.element.text)" }.joined(separator: "\n")
                highRiskWarning = "\n\n⚠️ 이 계획에는 외부 영향 작업이 포함되어 있습니다:\n\(listing)\n승인 시 끝까지 자동으로 실행됩니다."
            }

            let approvalMsg = ChatMessage(
                role: .system,
                content: "실행 계획:\n\n\(stepsDesc)\(highRiskWarning)\n\n승인하시면 실행을 시작합니다. 수정이 필요하면 요건을 말씀해주세요.",
                messageType: .approvalRequest
            )
            appendMessage(approvalMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].awaitingType = .planApproval
                rooms[i].transitionTo(.awaitingApproval)
            }
            syncAgentStatuses()
            scheduleSave()

            let approved = await approvalGates.waitForApproval(roomID: roomID)
            guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return false }

            if approved {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.inProgress)
                }
                let resumeMsg = ChatMessage(
                    role: .system,
                    content: "계획이 승인되었습니다. 실행을 시작합니다.",
                    messageType: .progress
                )
                appendMessage(resumeMsg, to: roomID)
                return true
            } else {
                let feedback = rooms.first(where: { $0.id == roomID })?
                    .messages.last(where: { $0.role == .user })?.content ?? ""

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                    if rooms[i].plan != nil {
                        rooms[i].plan!.incrementVersion()
                    }
                }

                let retryMsg = ChatMessage(
                    role: .system,
                    content: "요건을 반영하여 계획을 재수립합니다.",
                    messageType: .progress
                )
                appendMessage(retryMsg, to: roomID)

                let newPlan = await requestPlan(
                    roomID: roomID, task: task,
                    previousPlan: rooms.first(where: { $0.id == roomID })?.plan,
                    feedback: feedback,
                    designOutput: designOutput
                )
                if let newPlan, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].plan = newPlan
                } else {
                    // 재생성 실패 → 구조화된 에러로 워크플로우 중단
                    handleWorkflowError(.approvalRejected(roomID: roomID), roomID: roomID)
                    return false
                }
            }
        }
    }

    /// 1인 에이전트 구조화된 플랜 생성 (4b: executePlanPhase 대신)
    private func executeSoloDesign(roomID: UUID, task: String, room: Room) async {
        let intakeText = room.clarifyContext.intakeData?.asClarifyContextString() ?? ""
        let intakeBlock = intakeText.isEmpty ? "" : "\n\(intakeText)"
        let projectPathsBlock = room.effectiveProjectPaths.isEmpty ? "" : "\n[프로젝트 경로]\n" + room.effectiveProjectPaths.map { "- \($0)" }.joined(separator: "\n")

        let briefContext: String
        if let brief = room.taskBrief {
            briefContext = """
            [작업 브리프]
            목표: \(brief.goal)
            제약: \(brief.constraints.joined(separator: ", "))
            성공기준: \(brief.successCriteria.joined(separator: ", "))
            위험도: \(brief.overallRisk.rawValue)
            \(intakeBlock)\(projectPathsBlock)
            """
        } else {
            briefContext = (room.clarifyContext.clarifySummary ?? task) + intakeBlock + projectPathsBlock
        }

        let specialists = executingAgentIDs(in: roomID)
        guard let agentID = specialists.first,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            let intent = room.workflowState.intent ?? .task
            await executePlanPhase(roomID: roomID, task: task, intent: intent)
            return
        }

        speakingAgentIDByRoom[roomID] = agentID
        let history = buildRoomHistory(roomID: roomID)
        let context = makeToolContext(roomID: roomID, currentAgentID: agentID)

        let soloPrompt = """
        \(systemPrompt(for: agent, roomID: roomID))

        아래 작업을 수행하기 위한 실행 계획을 JSON으로 작성하세요.

        \(briefContext)

        대화 히스토리를 참고하여 작업 대상을 파악하세요.
        반드시 아래 JSON 형식으로만 출력하세요:
        ```json
        {
          "plan": {
            "summary": "계획 요약",
            "estimated_minutes": 10,
            "steps": [
              {"text": "단계 설명", "risk_level": "low"}
            ]
          }
        }
        ```
        risk_level: low(읽기/분석), medium(파일수정/코드생성), high(외부시스템)

        세분화 규칙:
        - 각 단계는 한 가지 명확한 산출물을 가져야 합니다
        - 구현, 테스트, PR 등은 반드시 별개 단계로 분할하세요
        - 번역, 요약 등 단일 작업은 1단계로 작성하세요
        - 같은 산출물이라도 파일/모듈이 다르면 단계를 나누세요
        - estimated_minutes는 1~30분으로 현실적으로 추정하세요
        """

        do {
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "실행 계획을 수립하는 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { _ in
                // 계획 JSON은 내부 처리용 — 스트리밍 표시 불필요
                return try await ToolExecutor.smartSend(
                    provider: provider,
                    agent: agent,
                    systemPrompt: soloPrompt,
                    conversationMessages: history,
                    context: context,
                    useTools: false
                )
            }

            if let plan = parsePlan(from: response),
               let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = plan
            }
        } catch {
            appendMessage(ChatMessage(role: .assistant, content: "계획 수립 오류: \(error.userFacingMessage)", agentName: agent.name, messageType: .error), to: roomID)
        }
        speakingAgentIDByRoom.removeValue(forKey: roomID)

        // plan 파싱 실패 시 복구: 계획 없이 바로 실행 단계로 진행
        if rooms.first(where: { $0.id == roomID })?.plan == nil {
            appendMessage(ChatMessage(
                role: .system,
                content: "계획 수립을 건너뛰고 바로 실행합니다.",
                messageType: .progress
            ), to: roomID)
            scheduleSave()
            return
        }

        // 계획 승인 게이트: 사용자 승인/요건 추가 루프
        let approved = await awaitPlanApproval(roomID: roomID, task: task)
        if !approved {
            // 승인 실패 (재생성 실패 등) → awaitPlanApproval 내부에서 .failed 전환 완료
            return
        }
        scheduleSave()
    }

    /// 1인 에이전트 토론 모드: JSON 계획 없이 자연어 분석/의견 제시
    private func executeSoloDiscussion(roomID: UUID, task: String, room: Room) async {
        let specialists = executingAgentIDs(in: roomID)
        guard let agentID = specialists.first,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        speakingAgentIDByRoom[roomID] = agentID
        let history = buildRoomHistory(roomID: roomID)
        let context = makeToolContext(roomID: roomID, currentAgentID: agentID)

        let intakeText = room.clarifyContext.intakeData?.asClarifyContextString() ?? ""
        let intakeBlock = intakeText.isEmpty ? "" : "\n\(intakeText)"
        let projectPathsBlock = room.effectiveProjectPaths.isEmpty ? "" : "\n[프로젝트 경로]\n" + room.effectiveProjectPaths.map { "- \($0)" }.joined(separator: "\n")

        let discussionPrompt = """
        \(systemPrompt(for: agent, roomID: roomID))

        [시스템] 필요한 외부 데이터는 이미 수집되었습니다. 도구·인증·API 연동 관련 언급을 하지 마세요.
        \(intakeBlock)\(projectPathsBlock)

        아래 주제에 대해 전문가 관점에서 분석하고 의견을 제시하세요.
        대화 히스토리를 참고하여 작업 대상을 파악하세요.
        자연어로 구조적이고 명확하게 응답하세요. JSON이나 실행 계획은 불필요합니다.

        핵심 포인트, 장단점, 권장 사항을 포함해주세요.
        """

        let placeholderID = UUID()
        do {
            let buffer = StreamBuffer()
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "분석을 시작합니다…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { _ in
                let placeholder = ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: agent.name)
                self.appendMessage(placeholder, to: roomID)
                return try await ToolExecutor.smartSend(
                    provider: provider,
                    agent: agent,
                    systemPrompt: discussionPrompt,
                    conversationMessages: history,
                    context: context,
                    onStreamChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in
                            self.updateMessageContent(placeholderID, newContent: current, in: roomID)
                        }
                    },
                    useTools: false
                )
            }
            updateMessageContent(placeholderID, newContent: stripTrailingOptions(response), in: roomID)
        } catch {
            appendMessage(ChatMessage(role: .assistant, content: "분석 오류: \(error.userFacingMessage)", agentName: agent.name, messageType: .error), to: roomID)
        }
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        scheduleSave()
        // plan 없음 → Design 완료 후 discussion의 requiredPhases에 따라 Deliver로 직행
    }

    /// Build 단계 (Plan C): Creator가 단계별 실행 — riskLevel별 정책 적용
    func executeBuildPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let intent = rooms[idx].workflowState.intent ?? .task

        // 계획이 없으면 기존 execute 폴백
        guard rooms[idx].plan != nil else {
            if intent == .quickAnswer {
                await executeQuickAnswer(roomID: roomID, task: task)
            } else {
                await executeExecutePhase(roomID: roomID, task: task, intent: intent)
            }
            return
        }

        let engine = StepExecutionEngine(
            host: self, roomID: roomID, task: task, policy: .standard
        )
        await engine.run()
    }

    /// Review 단계 (Plan C): Reviewer가 Build 결과물 검토
    func executeReviewPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let room = rooms[idx]

        // 1인 에이전트: 자기 검토 스킵 (도구 없는 self-review는 무의미, final step approval이 품질 게이트)
        let specialists = executingAgentIDs(in: roomID)
        if specialists.count <= 1 {
            return
        }

        // reviewer 역할의 에이전트 찾기
        let reviewerID = room.agentRoles.first(where: { $0.value == .reviewer })?.key
        let reviewerAgent: Agent?
        if let rid = reviewerID {
            reviewerAgent = agentStore?.agents.first(where: { $0.id == rid })
        } else {
            let specialists = executingAgentIDs(in: roomID)
            if specialists.count >= 2 {
                reviewerAgent = agentStore?.agents.first(where: { $0.id == specialists[1] })
            } else {
                // 전문가 1명: 자기 검토 (Self-Review)
                await executeSoloReview(roomID: roomID, task: task)
                return
            }
        }

        guard let reviewer = reviewerAgent,
              let reviewerProvider = providerManager?.provider(named: reviewer.providerName) else { return }

        // Creator 찾기 (fail 시 수정 요청용)
        let creatorID = room.agentRoles.first(where: { $0.value == .creator })?.key
        let creatorAgent = creatorID.flatMap { cid in agentStore?.agents.first(where: { $0.id == cid }) }
            ?? executingAgentIDs(in: roomID).first.flatMap { id in agentStore?.agents.first(where: { $0.id == id }) }

        let briefContext: String
        if let brief = room.taskBrief {
            briefContext = "목표: \(brief.goal)\n성공기준: \(brief.successCriteria.joined(separator: ", "))"
        } else {
            briefContext = room.clarifyContext.clarifySummary ?? task
        }

        // 이전 페이즈 요약 컨텍스트 (토큰 최적화)
        let phaseContext = PhaseContextSummarizer.buildContextForPhase(.review, room: room)

        let maxRetries = 2
        var retryCount = 0

        while retryCount <= maxRetries {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            // Build 결과 수집
            let currentRoom = rooms.first(where: { $0.id == roomID })
            let recentMessages = (currentRoom?.messages ?? []).suffix(15)
            let buildOutput = recentMessages
                .filter { $0.role == .assistant }
                .compactMap { $0.content }
                .joined(separator: "\n---\n")

            guard !buildOutput.isEmpty else { return }

            let reviewPrompt = """
            \(systemPrompt(for: reviewer, roomID: roomID))

            당신은 Review 단계의 Reviewer입니다.
            Build 결과물이 작업 목표와 성공기준을 충족하는지 검토하세요.

            \(briefContext)\(phaseContext.isEmpty ? "" : "\n\n[이전 페이즈 요약]\n\(phaseContext)")

            검토 후 반드시 첫 줄에 판정을 작성하세요:
            - PASS: 결과물이 기준을 충족함
            - FAIL: 핵심 기준 미충족, 수정 필요 (사유를 구체적으로 작성)

            간결하게 핵심만 작성하세요.
            """

            // Review 진행 활동 추적
            let reviewProgressMsg = ChatMessage(
                role: .system,
                content: "\(reviewer.name) 검토 중",
                messageType: .progress
            )
            appendMessage(reviewProgressMsg, to: roomID)

            let reviewStartTime = Date()
            speakingAgentIDByRoom[roomID] = reviewer.id
            var reviewResult = ""
            do {
                let reviewStartDetail = ToolActivityDetail(toolName: "llm_call", subject: "\(reviewer.providerName) · \(reviewer.modelName)", contentPreview: nil, isError: false)
                appendMessage(ChatMessage(role: .assistant, content: "검토 시작", agentName: reviewer.name, messageType: .toolActivity, activityGroupID: reviewProgressMsg.id, toolDetail: reviewStartDetail), to: roomID)

                let placeholderID = UUID()
                appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: reviewer.name), to: roomID)

                let buffer = StreamBuffer()
                reviewResult = try await reviewerProvider.sendMessageStreaming(
                    model: reviewer.modelName,
                    systemPrompt: reviewPrompt,
                    messages: [("user", "다음 결과물을 검토해주세요:\n\n\(buildOutput)")],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: reviewResult, in: roomID)

                let reviewDuration = Date().timeIntervalSince(reviewStartTime)
                let durationStr = reviewDuration < 60
                    ? String(format: "%.1f초", reviewDuration)
                    : String(format: "%d분 %.0f초", Int(reviewDuration) / 60, reviewDuration.truncatingRemainder(dividingBy: 60))
                let resultDetail = ToolActivityDetail(toolName: "llm_result", subject: durationStr, contentPreview: nil, isError: false)
                appendMessage(ChatMessage(role: .assistant, content: "검토 완료 (\(durationStr))", agentName: reviewer.name, messageType: .toolActivity, activityGroupID: reviewProgressMsg.id, toolDetail: resultDetail), to: roomID)
            } catch {
                appendMessage(ChatMessage(role: .assistant, content: "검토 오류: \(error.userFacingMessage)", agentName: reviewer.name, messageType: .error), to: roomID)
                break
            }
            speakingAgentIDByRoom.removeValue(forKey: roomID)

            // Verdict 파싱
            let verdict = parseReviewVerdict(reviewResult)
            if verdict == .pass {
                break  // Review 통과
            }

            retryCount += 1
            if retryCount > maxRetries {
                // 최대 재시도 초과 → 자동 통과 (라이브 협업: 승인 게이트 제거)
                let autoPassMsg = ChatMessage(
                    role: .system,
                    content: "Review \(maxRetries)회 실패. 자동 통과 처리합니다.",
                    messageType: .progress
                )
                appendMessage(autoPassMsg, to: roomID)
                break
            }

            // FAIL → Creator에게 수정 요청
            guard let creator = creatorAgent,
                  let creatorProvider = providerManager?.provider(named: creator.providerName) else { break }

            let fixMsg = ChatMessage(
                role: .system,
                content: "Review 실패 (\(retryCount)/\(maxRetries)). Creator에게 수정을 요청합니다.",
                messageType: .progress
            )
            appendMessage(fixMsg, to: roomID)

            // Creator 수정 활동 추적
            let fixProgressMsg = fixMsg  // fixMsg는 이미 .progress로 추가됨
            let fixStartTime = Date()
            speakingAgentIDByRoom[roomID] = creator.id

            let fixPrompt = """
            \(systemPrompt(for: creator, roomID: roomID))

            Reviewer가 결과물을 반려했습니다. 피드백을 반영하여 수정하세요.

            [Reviewer 피드백]
            \(reviewResult)

            수정된 결과물만 출력하세요.
            """

            do {
                let fixStartDetail = ToolActivityDetail(toolName: "llm_call", subject: "\(creator.providerName) · \(creator.modelName)", contentPreview: nil, isError: false)
                appendMessage(ChatMessage(role: .assistant, content: "수정 시작", agentName: creator.name, messageType: .toolActivity, activityGroupID: fixProgressMsg.id, toolDetail: fixStartDetail), to: roomID)

                let placeholderID = UUID()
                appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: creator.name), to: roomID)

                let buffer = StreamBuffer()
                let fixedOutput = try await creatorProvider.sendMessageStreaming(
                    model: creator.modelName,
                    systemPrompt: fixPrompt,
                    messages: [("user", "Reviewer 피드백을 반영하여 수정해주세요.")],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: fixedOutput, in: roomID)

                let fixDuration = Date().timeIntervalSince(fixStartTime)
                let durationStr = fixDuration < 60
                    ? String(format: "%.1f초", fixDuration)
                    : String(format: "%d분 %.0f초", Int(fixDuration) / 60, fixDuration.truncatingRemainder(dividingBy: 60))
                let resultDetail = ToolActivityDetail(toolName: "llm_result", subject: durationStr, contentPreview: nil, isError: false)
                appendMessage(ChatMessage(role: .assistant, content: "수정 완료 (\(durationStr))", agentName: creator.name, messageType: .toolActivity, activityGroupID: fixProgressMsg.id, toolDetail: resultDetail), to: roomID)
            } catch {
                appendMessage(ChatMessage(role: .assistant, content: "수정 오류: \(error.userFacingMessage)", agentName: creator.name, messageType: .error), to: roomID)
                break
            }
            speakingAgentIDByRoom.removeValue(forKey: roomID)
            // 루프 → 다시 Review
        }
        scheduleSave()
    }

    /// Review verdict 파싱: PASS / FAIL
    private func parseReviewVerdict(_ text: String) -> ReviewVerdict {
        let upper = text.uppercased()
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let firstLineUpper = firstLine.uppercased()
        // PASS 계열
        if firstLineUpper.contains("PASS") || firstLine.contains("✅") || firstLine.contains("통과") || upper.hasPrefix("PASS") {
            return .pass
        }
        // FAIL 계열
        if firstLineUpper.contains("FAIL") || firstLine.contains("❌") || firstLine.contains("불합격") || firstLine.contains("실패") || upper.hasPrefix("FAIL") {
            return .fail
        }
        // 조건부 승인
        if firstLine.contains("⚠️") || text.contains("조건부 승인") || text.contains("조건부 통과") {
            return .pass
        }
        return .pass  // 불확실하면 pass
    }

    private enum ReviewVerdict {
        case pass, fail
    }

    /// 솔로 자기 검토 (Self-Review): 같은 에이전트에게 Reviewer 페르소나로 결과물 검토
    private func executeSoloReview(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let room = rooms[idx]

        let specialists = executingAgentIDs(in: roomID)
        guard let agentID = specialists.first,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        // Build 결과물 수집
        let recentMessages = room.messages.suffix(15)
        let buildOutput = recentMessages
            .filter { $0.role == .assistant }
            .compactMap { $0.content }
            .joined(separator: "\n---\n")
        guard !buildOutput.isEmpty else { return }

        let briefContext: String
        if let brief = room.taskBrief {
            briefContext = "목표: \(brief.goal)\n성공기준: \(brief.successCriteria.joined(separator: ", "))"
        } else {
            briefContext = room.clarifyContext.clarifySummary ?? task
        }

        let maxSelfRetries = 1
        var retryCount = 0

        while retryCount <= maxSelfRetries {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            let reviewPrompt = """
            \(systemPrompt(for: agent, roomID: roomID))

            지금부터 Reviewer 관점에서 Build 결과물이 작업 목표를 충족하는지 검토하세요.

            \(briefContext)

            검토 후 반드시 첫 줄에 판정을 작성하세요:
            - PASS: 결과물이 기준을 충족함
            - FAIL: 핵심 기준 미충족, 수정 필요 (사유를 구체적으로 작성)

            간결하게 핵심만 작성하세요.
            """

            speakingAgentIDByRoom[roomID] = agentID
            var reviewResult = ""
            do {
                let placeholderID = UUID()
                appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: agent.name), to: roomID)

                let buffer = StreamBuffer()
                reviewResult = try await provider.sendMessageStreaming(
                    model: agent.modelName,
                    systemPrompt: reviewPrompt,
                    messages: [("user", "다음 결과물을 검토해주세요:\n\n\(buildOutput)")],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: reviewResult, in: roomID)
            } catch {
                appendMessage(ChatMessage(role: .assistant, content: "자기 검토 오류: \(error.userFacingMessage)", agentName: agent.name, messageType: .error), to: roomID)
                break
            }
            speakingAgentIDByRoom.removeValue(forKey: roomID)

            let verdict = parseReviewVerdict(reviewResult)
            if verdict == .pass { break }

            retryCount += 1
            if retryCount > maxSelfRetries {
                // 자기 수정 1회 후에도 FAIL → 자동 PASS
                let autoPassMsg = ChatMessage(
                    role: .system,
                    content: "자기 검토 실패. 자동 통과 처리합니다.",
                    messageType: .progress
                )
                appendMessage(autoPassMsg, to: roomID)
                break
            }

            // FAIL → 같은 에이전트에게 자기 수정 요청
            let fixMsg = ChatMessage(
                role: .system,
                content: "자기 검토 실패. 수정을 시도합니다.",
                messageType: .progress
            )
            appendMessage(fixMsg, to: roomID)

            speakingAgentIDByRoom[roomID] = agentID
            let fixPrompt = """
            \(systemPrompt(for: agent, roomID: roomID))

            방금 자기 검토에서 결과물을 반려했습니다. 피드백을 반영하여 수정하세요.

            [자기 검토 피드백]
            \(reviewResult)

            수정된 결과물만 출력하세요.
            """

            do {
                let placeholderID = UUID()
                appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: agent.name), to: roomID)

                let buffer = StreamBuffer()
                let fixedOutput = try await provider.sendMessageStreaming(
                    model: agent.modelName,
                    systemPrompt: fixPrompt,
                    messages: [("user", "자기 검토 피드백을 반영하여 수정해주세요.")],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: fixedOutput, in: roomID)
            } catch {
                appendMessage(ChatMessage(role: .assistant, content: "수정 오류: \(error.userFacingMessage)", agentName: agent.name, messageType: .error), to: roomID)
                break
            }
            speakingAgentIDByRoom.removeValue(forKey: roomID)
        }
        scheduleSave()
    }

    /// Deliver 단계 (Plan C): 최종 전달 — high risk인 경우 Draft 프리뷰 + 명시 승인
    func executeDeliverPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let room = rooms[idx]

        // quickAnswer: deliver에서 실제 답변 실행 (requiredPhases에 execute 없음)
        if room.workflowState.intent == .quickAnswer {
            await executeQuickAnswer(roomID: roomID, task: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }
        }

        // discussion/research: 토론·조사 완료 (종합은 Design에서 이미 완료)
        if room.workflowState.intent?.isDiscussionLike == true {
            let label = room.workflowState.intent == .research
                ? "조사가 마무리되었습니다."
                : "토론이 마무리되었습니다."
            let doneMsg = ChatMessage(
                role: .system,
                content: label,
                agentName: masterAgentName,
                messageType: .phaseTransition
            )
            appendMessage(doneMsg, to: roomID)
            scheduleSave()
            return
        }

        // 최종 전달 메시지
        let deliverMsg = ChatMessage(
            role: .system,
            content: "작업이 완료되었습니다.",
            messageType: .phaseTransition
        )
        appendMessage(deliverMsg, to: roomID)
        scheduleSave()
    }

    /// Plan 단계: needsPlan=true일 때만 호출됨. 토론 → 계획 수립 → 승인 루프
    func executePlanPhase(roomID: UUID, task: String, intent: WorkflowIntent) async {
        let specialistCount = executingAgentIDs(in: roomID).count

        if specialistCount >= 2 && intent.requiresDiscussion {
            // 전문가 2명 이상: 토론 → 브리핑
            let startMsg = ChatMessage(
                role: .system,
                content: "토론을 시작합니다. 참여자: \(specialistCount)명 | 합의 시 자동 종료"
            )
            appendMessage(startMsg, to: roomID)

            await executeDiscussion(roomID: roomID, topic: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            await generateBriefing(roomID: roomID, topic: task)
            guard !Task.isCancelled else { return }
        }
        // 전문가 1명: soloAnalysis 스킵 (requestPlan이 직접 분석)

        // 계획 수립 (PlanCard UI로 표시되므로 별도 메시지 불필요)
        let currentPlan = await requestPlan(roomID: roomID, task: task)
        guard !Task.isCancelled else { return }

        if let plan = currentPlan {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = plan
            }
        }

        // 계획 승인 게이트: 사용자 승인/요건 추가 루프
        let approved = await awaitPlanApproval(roomID: roomID, task: task)
        if !approved {
            return
        }
        scheduleSave()
    }

    /// Execute 단계: quickAnswer 즉답 / task 토론+분석 또는 계획 기반 실행
    func executeExecutePhase(roomID: UUID, task: String, intent: WorkflowIntent) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        if intent == .quickAnswer {
            // quickAnswer: 전문가 1명이 바로 답변
            await executeQuickAnswer(roomID: roomID, task: task)
        } else if rooms[idx].workflowState.needsPlan {
            // task + needsPlan: 계획 기반 단계별 실행
            if rooms[idx].plan == nil {
                rooms[idx].plan = RoomPlan(summary: task, estimatedSeconds: 300, steps: [RoomStep(text: task)])
            }

            rooms[idx].timerDurationSeconds = rooms[idx].plan?.estimatedSeconds ?? 300
            rooms[idx].timerStartedAt = Date()
            rooms[idx].transitionTo(.inProgress)
            scheduleSave()

            await executeRoomWork(roomID: roomID, task: task)
        } else {
            // task + !needsPlan: 토론/분석 후 결과 정리
            let specialistCount = executingAgentIDs(in: roomID).count

            if specialistCount >= 2 && intent.requiresDiscussion {
                let startMsg = ChatMessage(
                    role: .system,
                    content: "토론을 시작합니다. 참여자: \(specialistCount)명 | 합의 시 자동 종료"
                )
                appendMessage(startMsg, to: roomID)

                await executeDiscussion(roomID: roomID, topic: task)
                guard !Task.isCancelled,
                      rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

                await generateBriefing(roomID: roomID, topic: task)
                guard !Task.isCancelled else { return }
            } else if specialistCount == 1 {
                // autoDocOutput은 소로 분석 스킵 → handleDocumentOutput에서 도구 포함 문서 작성
                let isDoc = rooms.first(where: { $0.id == roomID })?.workflowState.autoDocOutput == true
                if !isDoc {
                    await executeSoloAnalysis(roomID: roomID, task: task)
                    guard !Task.isCancelled else { return }
                }
            }

            // autoDocOutput 플래그가 설정된 경우 자동 문서화
            if let room = rooms.first(where: { $0.id == roomID }), room.workflowState.autoDocOutput {
                await handleDocumentOutput(roomID: roomID, task: task, suggestedType: room.workflowState.documentType)
            }
            scheduleSave()
        }
    }

    /// quickAnswer 실행: 최적 전문가 1명이 도구 포함 즉답 (전문가 없으면 마스터 폴백)
    private func executeQuickAnswer(roomID: UUID, task: String) async {
        let specialistIDs = executingAgentIDs(in: roomID)
        let room = rooms.first(where: { $0.id == roomID })

        // 라우팅: 전문가 2명+ LLM 지명 → 첫 번째 전문가 → 마스터 폴백
        let candidateID: UUID?
        if specialistIDs.count >= 2 {
            candidateID = await routeQuickAnswer(roomID: roomID, task: task, specialistIDs: specialistIDs)
                ?? specialistIDs.first
        } else {
            candidateID = specialistIDs.first ?? room?.assignedAgentIDs.first
        }

        guard let agentID = candidateID,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].transitionTo(.inProgress)
        }
        speakingAgentIDByRoom[roomID] = agentID

        let context = makeToolContext(roomID: roomID, currentAgentID: agentID)
        var history: [ConversationMessage] = []
        if let intakeData = room?.clarifyContext.intakeData, intakeData.sourceType != .text {
            history.append(ConversationMessage.user(intakeData.asClarifyContextString()))
        }
        if let workLog = rooms.first(where: { $0.id == roomID })?.workLog {
            history.append(ConversationMessage.user("[이전 작업 컨텍스트]\n\(workLog.asContextString())"))
        }
        history.append(contentsOf: buildRoomHistory(roomID: roomID))

        let placeholderID = UUID()
        do {
            // 웹 검색 지침 추가: 모르는 내용은 반드시 검색 후 답변
            let searchPrompt = systemPrompt(for: agent, roomID: roomID)
                + "\n\n[웹 검색 지침] 답을 확실히 알지 못하거나 최신 정보가 필요한 질문은 반드시 WebSearch 도구로 검색한 후 답변하세요. 인터넷 밈, 슬랭, 브랜드, 제품명, 또는 익숙하지 않은 용어는 검색을 먼저 수행하세요."
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "답변을 작성하는 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { onToolActivity in
                let placeholder = ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: agent.name)
                self.appendMessage(placeholder, to: roomID)
                let hasAttachments = history.contains { $0.attachments != nil && !($0.attachments?.isEmpty ?? true) }
                if let claudeProvider = provider as? ClaudeCodeProvider, !hasAttachments {
                    // ClaudeCodeProvider: CLI 자체 WebSearch 사용 (검색+읽기만 허용, 첨부 없을 때만)
                    let simple = history.compactMap { msg -> (role: String, content: String)? in
                        guard let content = msg.content else { return nil }
                        return (role: msg.role, content: content)
                    }
                    return try await claudeProvider.sendMessageWithSearch(
                        model: agent.modelName,
                        systemPrompt: searchPrompt,
                        messages: simple,
                        onToolActivity: onToolActivity
                    )
                } else {
                    // 다른 프로바이더: DOUGLAS 내장 도구 사용
                    let buffer = StreamBuffer()
                    return try await ToolExecutor.smartSend(
                        provider: provider,
                        agent: agent,
                        systemPrompt: searchPrompt,
                        conversationMessages: history,
                        context: context,
                        onToolActivity: onToolActivity,
                        onStreamChunk: { [weak self] chunk in
                            guard let self else { return }
                            let current = buffer.append(chunk)
                            Task { @MainActor in
                                self.updateMessageContent(placeholderID, newContent: current, in: roomID)
                            }
                        },
                        allowedToolIDs: hasAttachments ? ["web_search", "web_fetch", "Read"] : ["web_search", "web_fetch"]
                    )
                }
            }
            updateMessageContent(placeholderID, newContent: stripTrailingOptions(response), in: roomID)
        } catch {
            updateMessageContent(
                placeholderID,
                newContent: "오류: \(error.userFacingMessage)",
                in: roomID
            )
            if let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
               let msgIdx = rooms[roomIdx].messages.firstIndex(where: { $0.id == placeholderID }) {
                rooms[roomIdx].messages[msgIdx].messageType = .error
            }
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
    }

    /// 경량 라우팅: 마스터가 즉답에 최적인 전문가 1명을 지명
    /// LLM 1회 호출로 에이전트 이름만 반환받음. 실패 시 nil (호출측에서 첫 번째 폴백)
    private func routeQuickAnswer(roomID: UUID, task: String, specialistIDs: [UUID]) async -> UUID? {
        // 마스터 에이전트 + 프로바이더 확보
        guard let masterID = rooms.first(where: { $0.id == roomID })?.assignedAgentIDs.first,
              let master = agentStore?.agents.first(where: { $0.id == masterID }),
              let provider = providerManager?.provider(named: master.providerName) else { return nil }

        let roster = specialistIDs.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })
        }.map { "- \($0.name): \($0.persona.prefix(60))" }.joined(separator: "\n")

        let prompt = """
        아래 전문가 중 이 질문에 가장 적합한 1명의 **이름만** 출력하세요. 다른 내용은 절대 출력하지 마세요.

        전문가:
        \(roster)

        질문: \(task)
        """

        do {
            let lightModel = providerManager?.lightModelName(for: master.providerName) ?? master.modelName
            let response = try await provider.sendMessage(
                model: lightModel,
                systemPrompt: "당신은 질문 라우터입니다. 전문가 이름만 한 줄로 출력하세요.",
                messages: [("user", prompt)]
            )
            let name = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "- ", with: "")
            return specialistIDs.first { id in
                agentStore?.agents.first(where: { $0.id == id })?.name == name
            }
        } catch {
            return nil
        }
    }

    /// 전문가 1명 Solo 분석: 토론 없이 혼자 분석하여 결과 공유 (전문가 없으면 마스터 폴백)
    private func executeSoloAnalysis(roomID: UUID, task: String) async {
        let specialistIDs = executingAgentIDs(in: roomID)
        let room = rooms.first(where: { $0.id == roomID })
        // 첫 번째 전문가 → 마스터 폴백
        let candidateID = specialistIDs.first ?? room?.assignedAgentIDs.first
        guard let agentID = candidateID,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        speakingAgentIDByRoom[roomID] = agentID

        // intake 데이터 (Jira 트리거 제거된 중립 버전)
        let intakeBlock: String
        if let intakeData = room?.clarifyContext.intakeData, intakeData.sourceType != .text {
            intakeBlock = "\n" + intakeData.asClarifyContextString()
        } else {
            intakeBlock = ""
        }

        let soloPrompt = """
        \(systemPrompt(for: agent, roomID: roomID))

        현재 작업방에서 아래 작업에 대해 혼자 분석합니다.
        \(intakeBlock)

        [작업]
        \(task)

        대화 히스토리를 참고하여 핵심 사항, 접근 방향, 주의점을 정리해주세요.
        작업과 무관한 내용을 절대 생성하지 마세요.
        """

        let history = buildRoomHistory(roomID: roomID)
        let context = makeToolContext(roomID: roomID, currentAgentID: agentID)

        let placeholderID = UUID()
        do {
            let buffer = StreamBuffer()
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "사전 분석 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { _ in
                let placeholder = ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: agent.name)
                self.appendMessage(placeholder, to: roomID)
                return try await ToolExecutor.smartSend(
                    provider: provider,
                    agent: agent,
                    systemPrompt: soloPrompt,
                    conversationMessages: history,
                    context: context,
                    onStreamChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in
                            self.updateMessageContent(placeholderID, newContent: current, in: roomID)
                        }
                    },
                    useTools: false
                )
            }
            updateMessageContent(placeholderID, newContent: stripTrailingOptions(response), in: roomID)
        } catch {
            // 사전 분석 실패는 워크플로우에 영향 없음 — placeholder를 조용히 제거
            if let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
               let msgIdx = rooms[roomIdx].messages.firstIndex(where: { $0.id == placeholderID }) {
                rooms[roomIdx].messages.remove(at: msgIdx)
            }
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
    }

    /// 플레이북 override 감지 (완료 후 호출)
    func detectPlaybookOverrides(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let playbook = room.clarifyContext.playbook,
              room.primaryProjectPath != nil else { return }

        let workSummary = room.workLog?.outcome ?? ""
        var overrides: [String] = []

        if let branchPattern = playbook.branchPattern, !branchPattern.isEmpty,
           (workSummary.contains("branch") || workSummary.contains("브랜치")) {
            overrides.append("브랜치 패턴 변경 감지 (설정: \(branchPattern))")
        }

        if !overrides.isEmpty {
            let overrideMsg = ChatMessage(
                role: .system,
                content: "플레이북과 다른 패턴이 감지되었습니다:\n" + overrides.map { "- \($0)" }.joined(separator: "\n") + "\n\n플레이북을 업데이트하시겠습니까?"
            )
            appendMessage(overrideMsg, to: roomID)
        }
        scheduleSave()
    }


}
