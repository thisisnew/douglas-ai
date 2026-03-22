import Foundation

// MARK: - Understanding Phases (Clarify + Assemble + Understand)

extension RoomManager {

    func executeClarifyPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        speakingAgentIDByRoom[roomID] = firstAgentID

        // 컨텍스트 구성: IntakeData + 플레이북
        var contextParts: [String] = []
        if let intakeData = rooms[idx].clarifyContext.intakeData {
            // Clarify 단계에서는 Jira/API 언급을 제거한 중립 컨텍스트 사용 (LLM 환각 방지)
            contextParts.append(intakeData.asClarifyContextString())
        }
        if let playbook = rooms[idx].clarifyContext.playbook {
            contextParts.append(playbook.asContextString())
        }
        let contextString = contextParts.joined(separator: "\n\n")

        // 첨부 파일 정보 수집 (Clarify에서는 파일명만 참조, 실제 파일은 실행 단계에서 전달)
        let fileAttachments = rooms[idx].messages
            .compactMap { $0.attachments }
            .flatMap { $0 }

        // Clarify용 첨부 요약 (파일 데이터 없이 이름만)
        let attachmentSummary: String
        if !fileAttachments.isEmpty {
            let names = fileAttachments.map { att in
                let typeLabel = att.isImage ? "이미지" : "문서"
                return "- \(typeLabel): \(att.displayName) (\(FileAttachment.formatFileSize(att.fileSizeBytes)))"
            }.joined(separator: "\n")
            attachmentSummary = "\n\n[첨부 파일 \(fileAttachments.count)개]\n\(names)\n(파일 내용은 실행 단계에서 전문가에게 전달됩니다. 여기서는 파일 존재만 인지하세요.)"
        } else {
            attachmentSummary = ""
        }

        // 문서 유형 템플릿 주입
        let docTypeContext = rooms[idx].workflowState.documentType?.templatePromptBlock() ?? ""

        // 등록된 서브 에이전트 목록 (delegation 판단용)
        let agentListStr: String
        if let subAgents = agentStore?.subAgents, !subAgents.isEmpty {
            agentListStr = subAgents.map { "- \($0.name)" }.joined(separator: "\n")
        } else {
            agentListStr = "(없음)"
        }

        // 사용자 직접 선택 방: 배정 에이전트 명시 + delegation 블록 제거
        let isUserSelectedTeam: Bool
        let teamContext: String
        if rooms[idx].createdBy == .user {
            let subAgentNames = rooms[idx].assignedAgentIDs.compactMap { id -> String? in
                guard let a = agentStore?.agents.first(where: { $0.id == id }), !a.isMaster else { return nil }
                return a.name
            }
            isUserSelectedTeam = !subAgentNames.isEmpty
            if isUserSelectedTeam {
                let names = subAgentNames.joined(separator: ", ")
                teamContext = "\n이 작업방에는 사용자가 직접 선택한 에이전트가 배정되어 있습니다: \(names)\n이 팀으로 작업을 진행합니다.\n"
            } else {
                teamContext = ""
            }
        } else {
            isUserSelectedTeam = false
            teamContext = ""
        }

        let delegationBlock: String
        if isUserSelectedTeam {
            // 에이전트가 이미 확정 → delegation 분석 불필요
            delegationBlock = ""
        } else {
            delegationBlock = """

            요약 후 반드시 아래 블록을 마지막에 추가하세요:
            [delegation]
            type: (explicit 또는 open)
            agents: (에이전트 이름을 쉼표 구분, explicit일 때만. open이면 이 줄 생략)
            [/delegation]

            - 사용자가 특정 에이전트를 지정했으면 → type: explicit, agents에 해당 이름
            - 특정 에이전트를 지정하지 않았으면 → type: open

            [등록된 에이전트]
            \(agentListStr)
            """
        }

        let clarifySystemPrompt = """
        \(systemPrompt(for: agent, roomID: roomID))

        당신은 요건 확인(Clarify) 단계를 수행하고 있습니다.
        사용자의 요청을 정확히 이해했는지 복명복창(확인)만 합니다.
        \(docTypeContext.isEmpty ? "" : "\n\(docTypeContext)\n")\(teamContext)
        아래 형식으로 이해한 내용을 요약하세요:
        - 요청 내용: (1-2문장 요약)
        - 핵심 요구사항: (불릿 포인트, 각 항목 1줄 이내)
        - 예상 산출물: (무엇이 나와야 하는지)\(docTypeContext.isEmpty ? "" : "\n- 문서 구조: (선택된 템플릿 섹션 기반으로 구성할 섹션 나열)")
        \(delegationBlock)
        [절대 금지]
        - 요약\(isUserSelectedTeam ? "" : " + delegation 블록") 외의 내용을 출력하지 마세요.
        - 질문에 대한 답변, 개념 설명, 해결책을 작성하지 마세요.
        - 작업을 수행하지 마세요. 이 단계는 확인만 합니다.
        - 첨부파일(이미지, 문서)의 내용을 상세히 나열하거나 분석하지 마세요. "첨부 문서: design.md" 처럼 무엇인지만 간단히 언급하세요.
        - 번역, 계산, 코드 작성 등 실제 작업 결과물을 포함하지 마세요.
        - "1. 다음" "2. 수정" "x. 나가기" 같은 선택지/메뉴를 절대 출력하지 마세요. 사용자 선택은 UI 버튼으로 제공됩니다.
        - 시스템 도구·인증·설정 관련 언급을 하지 마세요. 필요한 데이터는 이미 수집되었습니다.
        """

        var currentSummary = ""

        // 무한 루프: 사용자가 승인할 때까지 반복
        while true {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            // 1) DOUGLAS가 이해한 내용 요약 생성 (첨부파일 이미지 데이터 포함)
            let clarifyMessages: [ConversationMessage]
            let hasImageAttachments = !fileAttachments.filter({ $0.isImage }).isEmpty
            if currentSummary.isEmpty {
                let userContent = "\(contextString)\(attachmentSummary)\n\n위 요청을 분석하고, 이해한 내용을 정리해주세요. 작업: \(task)"
                clarifyMessages = [ConversationMessage.user(userContent, attachments: hasImageAttachments ? fileAttachments : nil)]
            } else {
                // 사용자 피드백 반영 재요약
                let history = buildRoomHistory(roomID: roomID)
                    .map { "\($0.role): \($0.content ?? "")" }
                    .suffix(5)
                    .joined(separator: "\n")
                let feedbackContent = "이전 요약:\n\(currentSummary)\n\n사용자 피드백:\n\(history)\n\n피드백을 반영하여 다시 요약하세요."
                clarifyMessages = [ConversationMessage.user(feedbackContent)]
            }

            do {
                // 스트리밍용 placeholder 메시지
                let placeholderID = UUID()
                let placeholder = ChatMessage(
                    id: placeholderID, role: .assistant, content: "",
                    agentName: agent.name
                )
                appendMessage(placeholder, to: roomID)

                let response: String
                if provider.supportsStreaming && !hasImageAttachments {
                    // 첨부 없음 → 스트리밍 경로
                    let simpleMessages = clarifyMessages.compactMap { msg -> (role: String, content: String)? in
                        guard let content = msg.content else { return nil }
                        return (role: msg.role, content: content)
                    }
                    let buffer = StreamBuffer()
                    response = try await provider.sendMessageStreaming(
                        model: agent.modelName,
                        systemPrompt: clarifySystemPrompt,
                        messages: simpleMessages,
                        onChunk: { [weak self] chunk in
                            guard let self else { return }
                            let current = buffer.append(chunk)
                            Task { @MainActor in
                                self.updateMessageContent(placeholderID, newContent: current, in: roomID)
                            }
                        }
                    )
                } else {
                    // 이미지 첨부 있음 또는 스트리밍 미지원 → sendMessageWithTools로 이미지 데이터 전달
                    let responseContent = try await provider.sendMessageWithTools(
                        model: agent.modelName,
                        systemPrompt: clarifySystemPrompt,
                        messages: clarifyMessages,
                        tools: []
                    )
                    switch responseContent {
                    case .text(let t): response = t
                    case .mixed(let t, _): response = t
                    case .toolCalls: response = "(요약 생성 실패)"
                    }
                }
                currentSummary = stripDelegationBlock(stripHallucinatedAuthLines(stripTrailingOptions(response)))

                // 복명복창 요약에서 방 제목 자동 추출 (첫 라운드만)
                if currentSummary.isEmpty == false,
                   let i = rooms.firstIndex(where: { $0.id == roomID }),
                   rooms[i].title == "이미지 분석" || rooms[i].title == "새 작업" || rooms[i].title.count > 28 {
                    let refined = Self.extractTitleFromClarifySummary(response)
                    if !refined.isEmpty {
                        rooms[i].setTitle(refined)
                    }
                }

                // placeholder를 최종 텍스트로 업데이트 (선택지 텍스트 제거 후)
                updateMessageContent(placeholderID, newContent: currentSummary, in: roomID)
            } catch {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
                let errorMsg = ChatMessage(
                    role: .assistant,
                    content: "요건 확인 오류: \(error.userFacingMessage)",
                    agentName: agent.name,
                    messageType: .error
                )
                appendMessage(errorMsg, to: roomID)
                return
            }

            // 2) 사용자에게 컨펌 요청 (복명복창 요약 자체가 확인 요청)
            speakingAgentIDByRoom.removeValue(forKey: roomID)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].awaitApproval(type: .clarification)
            }
            syncAgentStatuses()
            scheduleSave()

            let approved = await approvalGates.waitForApproval(roomID: roomID)
            guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            if approved {
                // 승인됨 → clarify 요약 저장 + delegation 분리 + planning 복귀
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].clarifyContext.setDelegationInfo(parseDelegationBlock(currentSummary))
                    rooms[i].clarifyContext.setClarifySummary(stripDelegationBlock(currentSummary))
                    rooms[i].transitionTo(.planning)
                }
                break
            }

            // 3) 거부됨 → ApprovalCard에서 이미 피드백 입력된 경우 스킵
            let hasInlineFeedback: Bool = {
                guard let room = rooms.first(where: { $0.id == roomID }) else { return false }
                // "수정 요청" 직전 메시지가 사용자 메시지이면 인라인 피드백 있음
                guard let rejectIdx = room.messages.lastIndex(where: { $0.content == "수정 요청" && $0.role == .system }) else { return false }
                let prevIdx = rejectIdx - 1
                guard prevIdx >= 0 else { return false }
                return room.messages[prevIdx].role == .user
            }()

            if !hasInlineFeedback {
                let askMsg = ChatMessage(
                    role: .system,
                    content: "어떤 부분을 수정해야 하나요?",
                    messageType: .userQuestion
                )
                appendMessage(askMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.awaitingUserInput)
                }
                scheduleSave()

                let _ = await approvalGates.waitForUserInput(roomID: roomID)
            }

            guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            // 피드백 반영하여 재요약 (루프 계속)
        }
        scheduleSave()
    }

    /// 가정 산출물 텍스트에서 WorkflowAssumption 파싱
    private func parseAssumptions(from content: String) -> [WorkflowAssumption] {
        // 형식: "- [위험:낮음] 가정 내용" 또는 "- [위험:중간] 가정 내용" 등
        let lines = content.components(separatedBy: "\n")
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [위험:") else { return nil }

            var riskLevel: WorkflowAssumption.RiskLevel = .low
            if trimmed.contains("[위험:높음]") {
                riskLevel = .high
            } else if trimmed.contains("[위험:중간]") {
                riskLevel = .medium
            }

            // 텍스트 추출: "] " 이후
            guard let bracketEnd = trimmed.range(of: "] ") else { return nil }
            let text = String(trimmed[bracketEnd.upperBound...])
            guard !text.isEmpty else { return nil }

            return WorkflowAssumption(text: text, riskLevel: riskLevel)
        }
    }

    /// Assemble 단계: 마스터 역할 산출 → 시스템 매칭/초대 → 커버리지 게이트
    func executeAssemblePhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        // 사용자가 직접 에이전트를 선택한 방 → assemble 스킵
        if rooms[idx].createdBy == .user {
            let subAgentNames = rooms[idx].assignedAgentIDs.compactMap { id -> String? in
                guard let a = agentStore?.agents.first(where: { $0.id == id }), !a.isMaster else { return nil }
                return a.name
            }
            if !subAgentNames.isEmpty {
                let names = subAgentNames.joined(separator: ", ")
                let msg = ChatMessage(
                    role: .system,
                    content: "사용자가 선택한 팀으로 진행합니다: \(names)",
                    messageType: .phaseTransition
                )
                appendMessage(msg, to: roomID)
                return
            }
        }

        // quickAnswer도 LLM 매칭 → showTeamConfirmation 경로 사용
        // (L2285에서 maxAgentHint = "반드시 1명만" 지시)

        // 문서 생성 작업 → LLM 매칭 바이패스: 문서 전용 에이전트 직접 배정
        if rooms[idx].workflowState.autoDocOutput {
            let allSubAgents = agentStore?.subAgents ?? []
            let docNameKWs: Set<String> = ["문서", "리서치", "작성"]
            let nonDocKWs: Set<String> = ["개발", "jira", "프론트", "백엔드"]

            // 문서 전용 에이전트 판별: 이름에 문서/리서치/작성 포함 + 개발/jira 등 제외
            let isDocSpecialist: (Agent) -> Bool = { sub in
                let nameL = sub.name.lowercased()
                let hasDocName = docNameKWs.contains(where: { nameL.contains($0) })
                let hasNonDoc = nonDocKWs.contains(where: { nameL.contains($0) })
                return hasDocName && !hasNonDoc
            }

            // 1) 방에 이미 문서 전용 에이전트가 있는지 확인
            let existingSpecialists = executingAgentIDs(in: roomID)
            let alreadyHasDocAgent = existingSpecialists.contains { id in
                guard let sub = agentStore?.agents.first(where: { $0.id == id }) else { return false }
                return isDocSpecialist(sub)
            }

            if !alreadyHasDocAgent {
                // 2) 에이전트 풀에서 문서 전용 에이전트 찾기
                if let docAgent = allSubAgents.first(where: { isDocSpecialist($0) }) {
                    if !rooms[idx].assignedAgentIDs.contains(docAgent.id) {
                        addAgent(docAgent.id, to: roomID, silent: true)
                    }
                } else {
                    // 3) 문서 전용 에이전트 없음 → 생성 제안
                    let suggestion = RoomAgentSuggestion(
                        name: "리서치 & 문서 전문가",
                        persona: "조사·분석·문서 작성을 전문으로 하는 에이전트입니다. 주어진 주제를 체계적으로 정리하여 문서를 생성합니다.",
                        reason: "문서 생성 작업에 적합한 전용 에이전트가 필요합니다.",
                        suggestedBy: agent.name,
                        skillTags: ["조사", "분석", "리서치", "문서", "작성", "정리", "번역"],
                        outputStyles: [.document, .data]
                    )
                    addAgentSuggestion(suggestion, to: roomID)
                    await waitForSuggestionResponse(roomID: roomID)
                }
            }

            // RuntimeRole 배정
            let specialists = executingAgentIDs(in: roomID)
            if let solo = specialists.first,
               let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].assignRole(.creator, to: solo)
            }

            // 참여 메시지 표시
            let masterName = agentStore?.masterAgent?.name ?? "DOUGLAS"
            let docDescs = executingAgentIDs(in: roomID).compactMap { id -> String? in
                guard let name = agentStore?.agents.first(where: { $0.id == id })?.name else { return nil }
                if let role = rooms.first(where: { $0.id == roomID })?.agentRoles[id] {
                    return "\(name)(\(role.displayName))"
                }
                return name
            }
            if !docDescs.isEmpty {
                appendMessage(ChatMessage(
                    role: .system,
                    content: "\(docDescs.joined(separator: ", "))님이 참여합니다.",
                    agentName: masterName
                ), to: roomID)
            }

            scheduleSave()
            return
        }

        // 1) 마스터에게 역할 요구사항 산출 요청
        var contextParts: [String] = []
        if let intakeData = rooms[idx].clarifyContext.intakeData {
            contextParts.append(intakeData.asClarifyContextString())
        }
        if let assumptions = rooms[idx].clarifyContext.assumptions, !assumptions.isEmpty {
            contextParts.append("[가정]\n" + assumptions.map { "- \($0.text)" }.joined(separator: "\n"))
        }
        if let workLog = rooms[idx].workLog {
            contextParts.append(workLog.asContextString())
        }

        let intentName = rooms[idx].workflowState.intent?.displayName ?? "구현"
        let docTypeName = rooms[idx].workflowState.documentType?.displayName
        // 기존 에이전트 목록 구성
        let subAgents = agentStore?.subAgents ?? []
        let agentRoster: String
        if subAgents.isEmpty {
            agentRoster = "(없음)"
        } else {
            agentRoster = subAgents.map { agent in
                let tags = agent.skillTags.isEmpty ? "" : " [전문: \(agent.skillTags.joined(separator: ", "))]"
                let modes = agent.workModes.isEmpty ? "" : " [업무: \(agent.workModes.map(\.displayName).joined(separator: ", "))]"
                let styles = agent.outputStyles.isEmpty ? "" : " [산출물: \(agent.outputStyles.map(\.displayName).joined(separator: ", "))]"
                return "- \(agent.name)\(tags)\(modes)\(styles)"
            }.joined(separator: "\n")
        }

        let intent = rooms[idx].workflowState.intent
        let maxAgentHint: String
        switch intent {
        case .quickAnswer:
            maxAgentHint = "이 작업은 즉답(quickAnswer)이므로 **반드시 1명만** 요청하세요. 가장 적합한 전문가 1명만 선택하세요."
        case .task:
            maxAgentHint = rooms[idx].workflowState.autoDocOutput
                ? "이 작업은 조사/분석 + 문서 작성이므로 **2명**을 요청하세요."
                : "작업 범위를 정확히 분석하여 필요한 역할을 모두 요청하세요. 프론트엔드+백엔드 등 여러 도메인이 필요하면 각각 요청하세요."
        case .research:
            maxAgentHint = "이 작업은 조사/검색입니다. 단일 도메인 조사는 **1명**이면 충분합니다. 여러 도메인(프론트+백엔드 등)의 코드를 모두 봐야 할 때만 2명을 요청하세요."
        case .discussion:
            maxAgentHint = "이 작업은 토론/의견 교환이므로 **2명 이상** 요청하세요. 다양한 관점이 필요합니다."
        default:
            maxAgentHint = "작업 범위를 분석하여 필요한 역할을 모두 요청하세요."
        }

        // 문서 유형 컨텍스트
        let docTypeHint: String
        if rooms[idx].workflowState.autoDocOutput, let docType = rooms[idx].workflowState.documentType {
            docTypeHint = """

            이 작업은 조사/분석 후 **\(docType.displayName)** 문서를 출력합니다.
            조사/분석을 수행할 전문가와 문서 작성에 적합한 전문가가 모두 필요합니다.
            예: 테스트 계획서 → 리서치 전문가 + QA/테스트 전문가, PRD → 리서치 전문가 + 기획/PM 전문가.
            """
        } else if let docType = rooms[idx].workflowState.documentType, docType != .freeform {
            docTypeHint = """

            이 작업은 **\(docType.displayName)** 문서를 작성하는 작업입니다.
            문서를 잘 작성할 수 있는 전문가를 선택하세요.
            작업 대상 도메인(예: 백엔드, 프론트엔드)의 개발자가 아니라, 해당 문서 유형을 작성할 역량이 있는 전문가를 우선하세요.
            예: 테스트 계획서 → QA/테스트 전문가, PRD → 기획/PM 전문가, 기술 설계서 → 시니어 개발자/아키텍트.
            """
        } else {
            docTypeHint = ""
        }

        let assembleSystemPrompt = """
        \(systemPrompt(for: agent, roomID: roomID))

        당신은 Assemble(팀 구성) 단계를 수행하고 있습니다.
        작업 유형은 **\(intentName)**\(docTypeName != nil ? " (\(docTypeName!))" : "")입니다.

        작업에 **직접적으로** 필요한 역할만 최소한으로 요청하세요.
        작업과 무관한 역할은 절대 포함하지 마세요.
        \(maxAgentHint)\(docTypeHint)

        **핵심 원칙:**
        1. 사용자가 특정 역할/직군을 직접 지정하면 그것을 최우선합니다. (예: "백엔드만 있으면 돼" → 백엔드 개발자)
        2. 사용자 요청의 작업 유형(코드 수정, 분석, 문서 작성 등)에 맞는 에이전트를 선택하세요.
        3. 참조 데이터의 출처(Jira, GitHub 등)가 아닌, 실제 수행할 작업에 집중하세요.
        예: Jira URL이 있어도 코드 수정 작업이면 → 개발자. Jira 분석가가 아님.
        예: "프론트엔드 관점에서 분석해줘" → 프론트엔드 전문가만.
        3-1. [참조 데이터]에 "감지된 관련 도메인"이 있으면 역할 판단 시 참고하되, 최종 판단은 작업 내용 기준으로 하세요. 감지된 도메인이 실제 필요하지 않으면 무시하세요.
        4. **적합한 에이전트가 목록에 없으면 억지로 매칭하지 마세요.**
        일반 질문에 도메인 전문가(백엔드/프론트엔드 개발자 등)를 배정하지 마세요.
        작업과 직접 관련이 없는 에이전트를 선택하느니, 새로운 역할명을 만드세요.
        예: "두쯔쿠가 뭐야" → 백엔드 개발자(X), 질의응답 전문가(O)

        **역할 배정 규칙:**
        - 리서치/조사/분석/취합/문서작성/테스트계획/QA 작업에 소프트웨어 개발자(백엔드/프론트엔드/앱 개발자)를 배정하지 마세요.
          → 대신 해당 작업에 맞는 전문가를 선택하세요: QA 작업→QA/테스트 전문가, 분석→분석 전문가, Jira→Jira 전문가.
        - 개발자는 코드 생성/수정/버그 수정/구현 작업에만 배정하세요.
        - QA/테스트/TC 관련 작업(테스트 계획, TC 설계, QA 전략 등)에는 반드시 QA/테스트 전문가를 배정하세요.
        - [선택]은 사용자가 명시적으로 요청한 경우에만 추가하세요.
        - 코드 수정/구현 작업에는 해당 도메인 개발자 1명이면 충분합니다.
        - 사용자가 요청하지 않은 보조 역할을 보험 차원으로 추가하지 마세요.

        현재 사용 가능한 에이전트:
        \(agentRoster)

        반드시 아래 형식으로 산출물을 생성하세요:

        ```artifact:role_requirements title="역할 요구사항"
        - [필수] 역할이름 (position=implementer): 이 역할이 필요한 이유
        - [선택] 역할이름 (position=reviewer): 이 역할이 필요한 이유
        ```

        position은 다음 중 선택: architect, planner, implementer, writer, translator, reviewer, tester, auditor, researcher, analyst, coordinator, advisor

        주의:
        - 위 에이전트 목록에서 **작업과 직접 관련된** 에이전트가 있으면 그 이름을 정확히 사용하세요.
        - 목록에 적합한 에이전트가 없으면 새 역할명을 만드세요. 억지로 관련 없는 에이전트를 선택하지 마세요.
        - 일반 지식 질문, 잡담, 설명 요청 등에는 도메인 전문가(개발자 등)를 배정하지 마세요. → "질의응답 전문가" 등 적합한 역할을 쓰세요.
        - 작업 내용과 직접 관련된 에이전트만 선택하세요. "백엔드 쿼리 수정" → 백엔드 개발자, "UI 개선" → 프론트엔드 개발자.
        """

        // --- 명시적 위임 감지 (clarify LLM 판단) ---
        if let delegation = rooms[idx].clarifyContext.delegationInfo,
           delegation.type == .explicit,
           !delegation.agentNames.isEmpty {
            let matchedAgents = delegation.agentNames.compactMap { name -> Agent? in
                let lowered = name.lowercased()
                return subAgents.first { agent in
                    let agentLowered = agent.name.lowercased()
                    return agentLowered == lowered
                        || agentLowered.contains(lowered)
                        || lowered.contains(agentLowered)
                }
            }
            if !matchedAgents.isEmpty {
                for matched in matchedAgents {
                    if let room = rooms.first(where: { $0.id == roomID }),
                       !room.assignedAgentIDs.contains(matched.id) {
                        addAgent(matched.id, to: roomID, silent: true)
                    }
                }
                scheduleSave()
                await showTeamConfirmation(roomID: roomID)
                return  // LLM 역할 분석 스킵
            }
            // 매칭 실패 → 기존 directMatch + LLM 흐름으로 폴스루
        }

        // 사전 매칭 + LLM + 폴백에 사용할 enriched task (clarify 응답 포함)
        var enrichedTask = task
        if let clarifySummary = rooms[idx].clarifyContext.clarifySummary {
            enrichedTask += " " + clarifySummary
        }
        if let userAnswers = rooms[idx].clarifyContext.userAnswers {
            let answerTexts = userAnswers.map { $0.answer }.joined(separator: " ")
            enrichedTask += " " + answerTexts
        }
        // taskBrief.goal에 사용자 의도가 요약되어 있으면 추가
        if let briefGoal = rooms[idx].taskBrief?.goal, !briefGoal.isEmpty {
            enrichedTask += " " + briefGoal
        }
        let taskLowered = enrichedTask.lowercased()
        // 한글 조사/어미 제거 ("프론트보고" → "프론트", "백엔드를" → "백엔드", "프론트한테" → "프론트")
        // KoreanTextUtils.koreanStripSuffixes 공용 리스트 사용 (중복 제거)
        let taskWords = taskLowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .map { word -> String in
                for particle in KoreanTextUtils.koreanStripSuffixes {
                    if word.hasSuffix(particle) && word.count > particle.count + 1 {
                        return String(word.dropLast(particle.count))
                    }
                }
                return word
            }
        let directMatches: [Agent] = subAgents.filter { sub in
            let nameKeywords = sub.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { word in
                    guard word.count >= 2 else { return false }
                    // 숫자 접미사 제거 후 범용 접미사 확인 (전문가1 → 전문가 → 제외)
                    let stripped = word.replacingOccurrences(of: "\\d+$", with: "", options: .regularExpression)
                    return !AgentMatcher.isGenericSuffix(word) && !AgentMatcher.isGenericSuffix(stripped)
                }
            return nameKeywords.contains(where: { keyword in
                // 정확 매칭: task에 키워드 포함 (ex: "백엔드" in task)
                taskLowered.contains(keyword) ||
                // 접두어 매칭: task 단어가 키워드의 접두어 (ex: "프론트" → "프론트엔드")
                taskWords.contains(where: { word in
                    guard !AgentMatcher.isGenericSuffix(word) else { return false }
                    return keyword.hasPrefix(word) && word.count >= 2
                })
            })
        }

        if !directMatches.isEmpty {
            // directMatches: 사용자가 이름을 직접 언급한 에이전트 → 제한 없이 전부 초대
            for sub in directMatches {
                if let room = rooms.first(where: { $0.id == roomID }),
                   !room.assignedAgentIDs.contains(sub.id) {
                    addAgent(sub.id, to: roomID, silent: true)
                }
            }
            scheduleSave()
            await showTeamConfirmation(roomID: roomID)
            return
        }

        // 사용자 요청을 먼저, 참조 데이터를 뒤로 (LLM이 요청에 집중하도록)
        let contextSuffix = contextParts.isEmpty ? "" : "\n\n[참조 데이터]\n\(contextParts.joined(separator: "\n\n"))"
        let messages: [(role: String, content: String)] = [
            ("user", "사용자 요청: \(enrichedTask)\n\n위 요청에 필요한 역할을 분석하세요.\(contextSuffix)")
        ]

        do {
            let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
            let response = try await provider.sendMessage(
                model: lightModel,
                systemPrompt: assembleSystemPrompt,
                messages: messages
            )

            // 산출물 추출
            let artifacts = ArtifactParser.extractArtifacts(from: response, producedBy: agent.name)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].discussion.artifacts.append(contentsOf: artifacts)
            }

            // role_requirements 산출물에서 역할 파싱
            var requirements: [RoleRequirement] = []
            for artifact in artifacts where artifact.type == .roleRequirements {
                requirements.append(contentsOf: AgentMatcher.parseRoleRequirements(from: artifact.content))
            }

            // documentType이 설정되고 autoDocOutput이 아닌 경우: 최대 1명만 허용
            // autoDocOutput이면 리서치+문서 복합 → 다수 에이전트 허용
            if rooms[idx].workflowState.documentType != nil && !rooms[idx].workflowState.autoDocOutput, requirements.count > 1 {
                if let firstRequired = requirements.first(where: { $0.priority == .required }) {
                    requirements = [firstRequired]
                } else {
                    requirements = [requirements[0]]
                }
            }

            if requirements.isEmpty {
                // 기존 전문가가 있으면 팀 확인 후 진행
                let existingSpecialists = executingAgentIDs(in: roomID)
                if !existingSpecialists.isEmpty {
                    await showTeamConfirmation(roomID: roomID)
                    return
                }

                // 전문가 없음 → 적합한 에이전트가 있으면 초대, 없으면 생성 제안
                let subAgentsForFallback = agentStore?.subAgents ?? []
                let taskBriefForFallback = rooms[idx].taskBrief

                var autoInvited = false
                let intent = rooms[idx].workflowState.intent

                // 1) AgentMatcher로 키워드 기반 최적 에이전트 탐색
                if let best = AgentMatcher.findBestFallbackMatch(task: enrichedTask, agents: subAgentsForFallback, intent: intent) {
                    addAgent(best.id, to: roomID, silent: true)
                    autoInvited = true
                }

                // 2) 매칭 실패 → 제안 이름 결정 후 기존 에이전트 탐색 or 생성 제안
                if !autoInvited {
                    let (suggestedName, suggestedPersona) = AgentMatcher.suggestAgentProfile(
                        for: enrichedTask, intent: intent, taskBrief: taskBriefForFallback
                    )

                    if let existing = AgentMatcher.findByName(suggestedName, among: subAgentsForFallback) {
                        addAgent(existing.id, to: roomID, silent: true)
                        autoInvited = true
                    } else {
                        let suggestion = RoomAgentSuggestion(
                            name: suggestedName,
                            persona: suggestedPersona,
                            reason: "'\(String(task.prefix(60)))' 작업에 적합한 전문가가 필요합니다.",
                            suggestedBy: agent.name
                        )
                        addAgentSuggestion(suggestion, to: roomID)
                    }
                }
                await waitForSuggestionResponse(roomID: roomID)

                // 제안 해결 후 → 팀 확인 게이트
                await showTeamConfirmation(roomID: roomID)
                return
            }

            // 2) 시스템 매칭 (Plan C: 3단 가중치 + 신뢰도 임계값 + 플러그인 태그)
            let subAgents = agentStore?.subAgents ?? []
            let taskBrief = rooms.first(where: { $0.id == roomID })?.taskBrief

            // 플러그인 주입 태그 사전 계산
            var pluginSkillTags: [UUID: [String]] = [:]
            if let provider = pluginSkillTagsProvider {
                for agent in subAgents where !agent.equippedPluginIDs.isEmpty {
                    let tags = provider(agent)
                    if !tags.isEmpty { pluginSkillTags[agent.id] = tags }
                }
            }

            let matched = AgentMatcher.matchRoles(
                requirements: requirements,
                agents: subAgents,
                intent: intent,
                documentType: rooms.first(where: { $0.id == roomID })?.workflowState.documentType,
                taskBrief: taskBrief,
                pluginSkillTags: pluginSkillTags
            )

            // 3) [필수] matched(0.7+) 에이전트 자동 초대
            for req in matched where req.status == .matched && req.priority == .required {
                if let agentID = req.matchedAgentID,
                   let room = rooms.first(where: { $0.id == roomID }),
                   !room.assignedAgentIDs.contains(agentID) {
                    addAgent(agentID, to: roomID, silent: true)
                }
            }

            // 3.2) 매칭된 에이전트의 WorkflowPosition 저장
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                for req in matched where req.matchedAgentID != nil && req.position != nil {
                    rooms[i].assignPosition(req.position!, to: req.matchedAgentID!)
                }
            }

            // 3.5) suggested(0.5~0.7) 에이전트: 사용자에게 추가 여부 질문
            // 중복 제거: agentID 기준 + 이미 배정된 에이전트 제외
            let currentAssigned = Set(rooms.first(where: { $0.id == roomID })?.assignedAgentIDs ?? [])
            var seenSuggestedAgentIDs = Set<UUID>()
            let suggestedReqs = matched.filter { req in
                guard req.status == .suggested, let agentID = req.matchedAgentID else { return false }
                guard !currentAssigned.contains(agentID) else { return false }
                return seenSuggestedAgentIDs.insert(agentID).inserted
            }
            for req in suggestedReqs {
                guard let agentID = req.matchedAgentID,
                      let sugAgent = agentStore?.agents.first(where: { $0.id == agentID }) else { continue }
                let suggestMsg = ChatMessage(
                    role: .system,
                    content: "\(sugAgent.name)도 참여시킬까요?",
                    messageType: .approvalRequest
                )
                appendMessage(suggestMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].pendingAgentConfirmationID = agentID
                    rooms[i].awaitApproval(type: .agentConfirmation)
                }
                syncAgentStatuses()
                scheduleSave()

                let approved = await approvalGates.waitForApproval(roomID: roomID)
                guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

                if approved {
                    if let room = rooms.first(where: { $0.id == roomID }),
                       !room.assignedAgentIDs.contains(agentID) {
                        addAgent(agentID, to: roomID, silent: true)
                    }
                }
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                }
            }

            // 4) [필수] 미매칭 역할: 이름 유사 에이전트 탐색 → 없으면 생성 제안
            for req in matched where req.status == .unmatched && req.priority == .required {
                if let existingAgent = AgentMatcher.findByName(req.roleName, among: subAgents) {
                    if let room = rooms.first(where: { $0.id == roomID }),
                       !room.assignedAgentIDs.contains(existingAgent.id) {
                        addAgent(existingAgent.id, to: roomID, silent: true)
                    }
                } else {
                    let suggestion = RoomAgentSuggestion(
                        name: req.roleName,
                        persona: "이 에이전트는 '\(req.roleName)' 역할을 수행합니다. \(req.reason)",
                        reason: req.reason,
                        suggestedBy: agent.name
                    )
                    addAgentSuggestion(suggestion, to: roomID)
                }
            }

            // 4.5) 미매칭 제안이 있으면 사용자가 추가/건너뛰기할 때까지 대기
            let hadUnmatched = matched.contains(where: { $0.status == .unmatched && $0.priority == .required })
            if hadUnmatched {
                await waitForSuggestionResponse(roomID: roomID)
            }

            // 5) RuntimeRole 사전 배정 (Plan C: Assemble에서 배정, UUID 기반)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                let specialists = executingAgentIDs(in: roomID)
                if specialists.count >= 2 {
                    let (creatorID, reviewerID, plannerID) = assignDesignRoles(specialists: specialists)
                    rooms[i].assignRole(.creator, to: creatorID)
                    rooms[i].assignRole(.reviewer, to: reviewerID)
                    if let plannerID { rooms[i].assignRole(.planner, to: plannerID) }
                } else if let solo = specialists.first {
                    rooms[i].assignRole(.creator, to: solo)
                }
            }

            // 6) 팀 구성 확인 게이트 (§6.4 — 항상 호출, 개별 승인 완료 시 자동 진행)
            await showTeamConfirmation(roomID: roomID, individuallyApproved: !suggestedReqs.isEmpty)

        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "Assemble 단계 오류: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }
        scheduleSave()
    }


    // MARK: - Plan C: 새 6단계 워크플로우

    /// Understand 단계 (Plan C): intake + intent + TaskBrief 생성 (clarify 루프 제거)
    /// 순서: intake(URL/Jira fetch) → 의도 확인(필요 시) → intent 분류 → TaskBrief
    func executeUnderstandPhase(roomID: UUID, task: String) async {
        var actualTask = task

        // 1) Intake: URL/Jira fetch (의도 확인 전에 실행하여 Jira 데이터 확보)
        await executeIntakePhase(roomID: roomID, task: task)
        guard !Task.isCancelled,
              rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // 2) 명시적 의도 없는 경우: 사용자에게 작업 의도 확인
        //    (파일만 업로드, URL만 입력, 이미지만 첨부 등)
        let hasExplicitIntentForTask = !task.isEmpty && IntentClassifier.hasExplicitUserIntent(task)
        if task.isEmpty || !hasExplicitIntentForTask {
            // 상황에 맞는 질문 생성 (Jira 데이터가 이미 있으면 티켓 정보 포함)
            let attachedFiles = rooms.first(where: { $0.id == roomID })?.messages
                .compactMap { $0.attachments }.flatMap { $0 } ?? []
            let hasURL = task.range(of: "https?://", options: .regularExpression) != nil
            let intakeData = rooms.first(where: { $0.id == roomID })?.clarifyContext.intakeData
            let questionContent: String
            if !attachedFiles.isEmpty && hasURL {
                // URL + 파일 첨부 동시
                let fileDesc = attachedFiles.map { $0.isImage ? "이미지(\($0.originalFilename ?? $0.displayName))" : $0.displayName }.joined(separator: ", ")
                questionContent = "\(fileDesc)과 링크를 공유해주셨네요. 어떤 작업을 진행할까요?\n(예: 개발, 분석, 요약, 기획서 작성, 코드 리뷰 등)"
            } else if !attachedFiles.isEmpty {
                // 파일 첨부만
                let fileDesc = attachedFiles.map { $0.isImage ? "이미지(\($0.originalFilename ?? $0.displayName))" : $0.displayName }.joined(separator: ", ")
                questionContent = "\(fileDesc)을 첨부해주셨네요. 어떤 작업을 진행할까요?\n(예: 번역, 분석, 텍스트 추출, 요약 등)"
            } else if hasURL, let intakeData, !intakeData.jiraDataList.isEmpty {
                // Jira URL + 티켓 데이터 성공적으로 조회됨
                let ticketInfo = intakeData.jiraDataList.map { "[\($0.key)] \($0.summary)" }.joined(separator: ", ")
                questionContent = "티켓을 확인했습니다: \(ticketInfo)\n\n이 이슈를 기반으로 어떤 작업을 진행할까요? (예: 개발, 기획서 작성, 분석, 요약, 코드 리뷰 등)"
            } else if hasURL {
                // URL만 입력
                questionContent = "추가 확인이 필요합니다:\n\n이 이슈를 기반으로 어떤 작업을 진행할까요? (예: 개발, 기획서 작성, 분석, 요약, 코드 리뷰 등)\n이슈를 확인한 뒤 작업 방향을 알려주시면 바로 시작하겠습니다."
            } else {
                questionContent = "어떤 작업을 도와드릴까요?"
            }
            let questionMsg = ChatMessage(
                role: .assistant,
                content: questionContent,
                agentName: masterAgentName,
                messageType: .userQuestion
            )
            appendMessage(questionMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.awaitingUserInput)
            }
            scheduleSave()

            // 사용자 응답 대기 (타임아웃 없음 — awaitingUserInput 상태로 무한 대기)
            let answer: String = await approvalGates.waitForUserInput(roomID: roomID)

            guard !answer.isEmpty else {
                return
            }
            let userAnswer = answer

            // 사용자 응답을 actualTask로 설정
            // (URL/Jira 데이터는 이미 intakeData에 저장되어 있으므로 별도 보존 불필요)
            actualTask = userAnswer
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
                let titleText = userAnswer.prefix(30).components(separatedBy: "\n").first ?? String(userAnswer.prefix(30))
                rooms[i].setTitle(String(titleText))
            }
            scheduleSave()
        }

        // 2b) 사용자에게 분석 시작 알림
        let analyzeMsg = ChatMessage(
            role: .system,
            content: "요청을 분석합니다...",
            agentName: masterAgentName,
            messageType: .progress
        )
        appendMessage(analyzeMsg, to: roomID)

        // 3) Intent: quickAnswer vs task 분류
        await executeIntentPhase(roomID: roomID, task: actualTask)
        guard !Task.isCancelled,
              rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // 3) TaskBrief 생성 (clarify 루프 대신 1회 질문으로 대체)
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName

        var intakeContext = rooms[idx].clarifyContext.intakeData?.asClarifyContextString()
        // 후속 사이클: 이전 대화 컨텍스트를 TaskBrief에 전달 (맥락 없는 엉뚱한 질문 방지)
        if let workLog = rooms[idx].workLog {
            let logContext = workLog.asContextString()
            if let existing = intakeContext {
                intakeContext = existing + "\n\n" + logContext
            } else {
                intakeContext = logContext
            }
        }
        let hasExplicitIntent = IntentClassifier.hasExplicitUserIntent(actualTask)

        // 이미지 첨부가 있으면 TaskBrief에 힌트 전달 (이미지 데이터는 못 보내지만 존재 사실 알림)
        let roomAttachments = rooms[idx].messages.compactMap { $0.attachments }.flatMap { $0 }
        let hasImageAttachment = roomAttachments.contains { $0.isImage }

        // Fast-path: 짧고 단순한 이미지 변환 작업은 LLM TaskBrief 생성 스킵
        // (번역/요약/추출 등 단일 변환만 해당, 설계/전략/계획 등 복합 작업은 제외)
        let complexTaskIndicators = ["설계", "전략", "계획", "테스트", "분석", "구현", "개발", "작성", "기획", "리뷰"]
        let hasComplexIndicator = complexTaskIndicators.contains(where: { actualTask.lowercased().contains($0) })
        let isSimpleImageTask = rooms[idx].workflowState.intent != nil
            && hasExplicitIntent
            && actualTask.count < 30
            && hasImageAttachment
            && !hasComplexIndicator

        if isSimpleImageTask {
            let inferredOutput: OutputType = {
                let lower = actualTask.lowercased()
                if lower.contains("번역") || lower.contains("translate") { return .document }
                if lower.contains("분석") || lower.contains("analy") { return .analysis }
                if lower.contains("요약") || lower.contains("summar") { return .analysis }
                if lower.contains("추출") || lower.contains("extract") { return .document }
                return .document
            }()
            rooms[idx].setTaskBrief(TaskBrief(
                goal: actualTask,
                outputType: inferredOutput,
                needsClarification: false
            ))
            scheduleSave()
            return
        }

        var taskWithAttachmentHint = actualTask
        if hasImageAttachment {
            let imageNames = roomAttachments.filter { $0.isImage }.map { $0.originalFilename ?? $0.displayName }
            taskWithAttachmentHint += "\n\n[첨부 이미지: \(imageNames.joined(separator: ", "))] 사용자가 이미지를 첨부했습니다. 이미지 내용(텍스트, 메뉴, 디자인 등)이 작업 대상일 수 있으므로 needsClarification: false로 설정하세요."
        }

        let clarifySummary = rooms[idx].clarifyContext.clarifySummary
        let brief = await IntentClassifier.generateTaskBrief(
            task: taskWithAttachmentHint,
            intakeContext: intakeContext,
            clarifySummary: clarifySummary,
            userHasExplicitIntent: hasExplicitIntent || hasImageAttachment,
            provider: provider,
            model: lightModel
        )

        // await 이후 idx 재탐색 (배열 변동 가능)
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        if var brief {
            // 명시적 의도 + 외부 데이터(Jira 등) 또는 첨부파일이 있으면 clarification 강제 스킵
            // LLM이 "파일 경로를 알려주세요" 등 불필요한 질문을 과도하게 생성하는 문제 방어
            let hasIntakeData = rooms[idx].clarifyContext.intakeData != nil
            let hasURL = actualTask.range(of: "https?://", options: .regularExpression) != nil
            if hasExplicitIntent && brief.needsClarification && (hasImageAttachment || hasURL || hasIntakeData) {
                brief = TaskBrief(
                    goal: brief.goal, constraints: brief.constraints,
                    successCriteria: brief.successCriteria, nonGoals: brief.nonGoals,
                    overallRisk: brief.overallRisk, outputType: brief.outputType,
                    needsClarification: false, questions: []
                )
            }
            rooms[idx].setTaskBrief(brief)
        } else {
            print("[DOUGLAS] ⚠️ TaskBrief 생성 실패 — 키워드 기반 fallback으로 진행")
        }
        scheduleSave()

        // 4) needsClarification이면 질문 최대 2회 → 자동 진행 (Plan C)
        //    ※ 문서 생성(autoDocOutput)은 추가 질문 없이 바로 진행
        var currentBrief: TaskBrief? = rooms[idx].taskBrief ?? brief
        var enrichedTask = actualTask
        let maxQuestions = 3
        let isDocTask = rooms.first(where: { $0.id == roomID })?.workflowState.autoDocOutput == true

        for questionRound in 1...maxQuestions {
            guard !isDocTask,
                  let cb = currentBrief, cb.needsClarification, !cb.questions.isEmpty else { break }
            guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            let questionText = (currentBrief?.questions ?? []).joined(separator: "\n")
            let questionMsg = ChatMessage(
                role: .assistant,
                content: "추가 확인이 필요합니다:\n\n\(questionText)",
                agentName: masterAgentName,
                messageType: .userQuestion
            )
            appendMessage(questionMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.awaitingUserInput)
            }
            scheduleSave()

            // 사용자 응답 대기 (타임아웃 없음 — awaitingUserInput 상태로 무한 대기)
            let answer: String = await approvalGates.waitForUserInput(roomID: roomID)

            guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            if !answer.isEmpty {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                }
                enrichedTask = "\(enrichedTask)\n\n추가 정보: \(answer)"
                let currentClarifySummary = rooms.first(where: { $0.id == roomID })?.clarifyContext.clarifySummary
                if let updatedBrief = await IntentClassifier.generateTaskBrief(
                    task: enrichedTask,
                    intakeContext: intakeContext,
                    clarifySummary: currentClarifySummary,
                    userHasExplicitIntent: true,
                    provider: provider,
                    model: lightModel
                ) {
                    currentBrief = updatedBrief
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].setTaskBrief(updatedBrief)
                    }
                } else {
                    break  // 재생성 실패 시 기존 brief로 진행
                }
            } else {
                break  // 빈 응답 → 현재 정보로 진행
            }
        }

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].transitionTo(.planning)
        }
        scheduleSave()
    }

}
