import Foundation

// MARK: - 문서 처리 (RoomManager 본체에서 분리)

extension RoomManager {

    // MARK: - 문서 파일 저장

    /// documentType이 설정된 방에서 자동 파일 저장 (NSSavePanel)
    /// - 1차: 에이전트가 실제 생성한 문서 파일이 있으면 해당 경로 링크
    /// - 2차: 메시지 콘텐츠 추출 후 MD 파일 저장
    func offerDocumentSave(roomID: UUID, task: String? = nil) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              room.workflowState.documentType != nil,
              room.status != .failed else { return }

        // 1차: 에이전트가 실제 생성한 문서 파일 확인 (바이너리 포맷: xlsx, pptx 등)
        if let docURL = DocumentExporter.findActualDocumentFile(from: room) {
            // 바이너리 파일 유효성 검사 — 너무 작거나 비어있으면 깨진 파일
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: docURL.path)[.size] as? Int) ?? 0
            if fileSize > 100 {
                let doneMsg = ChatMessage(
                    role: .system,
                    content: "문서가 저장되었습니다\n\(docURL.lastPathComponent)\n\(docURL.path)",
                    messageType: .phaseTransition,
                    documentURL: docURL.absoluteString
                )
                appendMessage(doneMsg, to: roomID)
                return
            } else {
                // 깨진 파일 → 삭제 후 md로 fallback
                try? FileManager.default.removeItem(at: docURL)
                let fallbackMsg = ChatMessage(
                    role: .system,
                    content: "파일 생성에 실패하여 Markdown으로 대체 저장합니다.",
                    messageType: .phaseTransition
                )
                appendMessage(fallbackMsg, to: roomID)
                // 아래 2차 로직으로 계속 진행 → md로 저장
            }
        }

        // 2차: 메시지에서 콘텐츠 추출 후 파일 저장
        guard let content = DocumentExporter.extractDocumentContent(from: room) else { return }

        let suggestedName = DocumentExporter.suggestedFilename(room: room, content: content)

        // 요청 포맷 감지 (task 우선, 없으면 마지막 user 메시지)
        let userTask = (task ?? room.messages.last(where: { $0.role == .user })?.content ?? "").lowercased()
        let format = DocumentExporter.detectRequestedFormat(userTask)

        if format == "pdf" {
            let pdfMsg = ChatMessage(role: .system, content: "Markdown → PDF 변환 중…", messageType: .phaseTransition)
            appendMessage(pdfMsg, to: roomID)
            let url = await DocumentExporter.exportToPDF(markdownContent: content, suggestedName: suggestedName)
            if let url {
                let doneMsg = ChatMessage(
                    role: .system,
                    content: "문서가 저장되었습니다\n\(url.lastPathComponent)\n\(url.path)",
                    messageType: .phaseTransition,
                    documentURL: url.absoluteString
                )
                appendMessage(doneMsg, to: roomID)
            }
        } else {
            let savingMsg = ChatMessage(role: .system, content: "문서를 파일로 저장합니다…", messageType: .phaseTransition)
            appendMessage(savingMsg, to: roomID)
            let result = DocumentExporter.saveDocumentWithResult(
                content: content, suggestedName: suggestedName, defaultExtension: format
            )
            switch result {
            case .saved(let url, let usedFallback):
                var msg = "문서가 저장되었습니다\n\(url.lastPathComponent)\n\(url.path)"
                if usedFallback {
                    msg += "\n\n(설정된 폴더에 접근할 수 없어 기본 폴더에 저장했습니다. 설정에서 저장 폴더를 다시 지정해주세요.)"
                }
                let doneMsg = ChatMessage(
                    role: .system,
                    content: msg,
                    messageType: .phaseTransition,
                    documentURL: url.absoluteString
                )
                appendMessage(doneMsg, to: roomID)
            case .failed(let reason):
                let errMsg = ChatMessage(
                    role: .system,
                    content: "문서 저장에 실패했습니다: \(reason)",
                    messageType: .phaseTransition
                )
                appendMessage(errMsg, to: roomID)
            }
        }
    }

    // MARK: - 문서화 요청 처리

    /// 사용자의 명시적 문서화 요청 처리 (토론 히스토리 기반 문서 작성 + 자동 저장)
    func handleDocumentOutput(roomID: UUID, task: String, suggestedType: DocumentType?, isFormatConversion: Bool = false) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let docType = suggestedType ?? .freeform
        rooms[idx].workflowState.setDocumentType(docType)
        rooms[idx].startExecution()

        let phaseMsg = ChatMessage(
            role: .system,
            content: "문서 작성을 시작합니다…",
            messageType: .phaseTransition
        )
        appendMessage(phaseMsg, to: roomID)
        scheduleSave()

        // 기존 에이전트로 토론 히스토리 기반 문서 작성
        let docMsgID = await executeDocumentWritingStep(roomID: roomID, docType: docType, task: task, isFormatConversion: isFormatConversion)

        // 자동 저장
        await offerDocumentSave(roomID: roomID, task: task)

        // 저장 성공 후 본문 메시지 숨김 (채팅에 문서 전문이 표시되는 것 방지)
        if let docMsgID,
           let i = rooms.firstIndex(where: { $0.id == roomID }),
           let mi = rooms[i].messages.firstIndex(where: { $0.id == docMsgID }) {
            rooms[i].messages[mi].messageType = .discussion
        }

        // 완료
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed {
            rooms[i].complete()
        }
        scheduleSave()
    }

    /// 토론 히스토리 기반 문서 작성 실행. 반환값: 스트리밍 메시지 ID (저장 후 숨김 용도)
    @discardableResult
    func executeDocumentWritingStep(roomID: UUID, docType: DocumentType, task: String, isFormatConversion: Bool = false) async -> UUID? {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return nil }

        // 에이전트 선택: 전용 문서 에이전트 우선 → docType keywords 폴백 → 첫 번째 전문가
        let specialistIDs = executingAgentIDs(in: roomID)
        let agentID: UUID? = {
            // 1. 전역 풀에서 전용 문서 에이전트 탐색
            let allSubAgents = agentStore?.subAgents ?? []
            let docNameKWs: Set<String> = ["문서", "리서치", "작성"]
            let nonDocKWs: Set<String> = ["개발", "jira", "프론트", "백엔드"]
            if let docAgent = allSubAgents.first(where: { sub in
                let nameL = sub.name.lowercased()
                return docNameKWs.contains(where: { nameL.contains($0) })
                    && !nonDocKWs.contains(where: { nameL.contains($0) })
            }) {
                if let i = rooms.firstIndex(where: { $0.id == roomID }),
                   !rooms[i].assignedAgentIDs.contains(docAgent.id) {
                    addAgent(docAgent.id, to: roomID, silent: false)
                }
                return docAgent.id
            }

            // 2. docType preferredKeywords 기반 폴백
            let preferredKWs = docType.preferredKeywords
            if !preferredKWs.isEmpty {
                let candidates = specialistIDs.isEmpty ? Array(room.assignedAgentIDs) : specialistIDs
                let scored = candidates.compactMap { id -> (UUID, Int)? in
                    guard let a = agentStore?.agents.first(where: { $0.id == id }) else { return nil }
                    let text = "\(a.name) \(a.persona)".lowercased()
                    let score = preferredKWs.filter { text.contains($0.lowercased()) }.count
                    return (id, score)
                }
                if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 {
                    return best.0
                }
            }
            return specialistIDs.first ?? room.assignedAgentIDs.first
        }()
        guard let id = agentID,
              let agent = agentStore?.agents.first(where: { $0.id == id }),
              let provider = providerManager?.provider(named: agent.providerName) else { return nil }

        speakingAgentIDByRoom[roomID] = id

        let templateBlock = docType != .freeform ? "\n" + docType.templatePromptBlock() : ""
        let history = buildRoomHistory(roomID: roomID)

        // 이전 분석 결과를 프롬프트에 명시적 주입 (buildRoomHistory의 20개 제한 보완)
        var previousContext = ""
        if let rb = room.discussion.researchBriefing {
            previousContext += "\n\n[이전 조사 결과 — 이 내용을 기반으로 문서를 작성하세요]\n" + rb.asContextString()
        } else if let briefing = room.discussion.briefing {
            previousContext += "\n\n[이전 토론 결과 — 이 내용을 기반으로 문서를 작성하세요]\n" + briefing.asContextString()
        }
        if let plan = room.plan, !plan.stepResultsFull.isEmpty {
            let results = plan.stepResultsFull.suffix(3).joined(separator: "\n---\n")
            previousContext += "\n\n[이전 작업 결과]\n" + String(results.prefix(3000))
        }
        if let log = room.discussion.fullDiscussionLog, !log.isEmpty {
            // 토론 원문 중 핵심 부분만 (앞뒤 각 1000자)
            let head = String(log.prefix(1000))
            let tail = String(log.suffix(1000))
            if log.count > 2000 {
                previousContext += "\n\n[토론 원문 발췌]\n\(head)\n…(중략)…\n\(tail)"
            } else {
                previousContext += "\n\n[토론 원문]\n\(log)"
            }
        }

        var requestedFormat = DocumentExporter.detectRequestedFormat(task.lowercased())

        let isBinaryFormat = DocumentExporter.unsupportedBinaryFormats.contains(requestedFormat)

        // 포맷 변환: 원본 내용을 추출하여 프롬프트에 직접 포함
        let formatConversionBlock: String
        if isFormatConversion {
            // 이전 대화에서 가장 최근의 실질적 응답을 원본으로 사용
            let originalContent = room.messages.reversed()
                .first(where: { $0.role == .assistant && $0.messageType == .text && $0.content.count >= 100 })?
                .content ?? ""
            let contentBlock = originalContent.isEmpty ? "" : """

            [원본 내용 — 아래 내용을 빠짐없이 문서화하세요]
            \(originalContent)
            """
            formatConversionBlock = """

            ⚠️ 이것은 "포맷 변환" 요청입니다.
            이전 대화에서 이미 작성된 답변 내용을 문서 형태로 정리하는 것이 목적입니다.
            기존 내용을 충실히 보존하면서 문서 구조(제목, 섹션, 표 등)를 적용하세요.
            새로운 내용을 추가하거나 기존 내용을 임의로 생략하지 마세요.
            링크나 참조만 나열하지 말고, 각 항목의 실제 내용을 본문에 포함하세요.
            \(contentBlock)
            """
        } else {
            formatConversionBlock = ""
        }

        let docPrompt: String
        if isBinaryFormat {
            // 바이너리 포맷 (xlsx, pptx, docx): LLM이 file_write로 직접 생성
            let saveDir = DocumentExporter.resolvedSaveDirectoryPath()
            let suggestedName = DocumentExporter.suggestedFilename(room: room)
            let targetPath = "\(saveDir)/\(DocumentExporter.sanitizeFilename(suggestedName, ext: requestedFormat))"
            docPrompt = """
            \(systemPrompt(for: agent, roomID: roomID))

            ⚠️ 당신은 지금 "파일 생성 모드"입니다.
            이전 대화와 분석 내용을 바탕으로 \(requestedFormat) 파일을 생성합니다.
            \(previousContext)\(formatConversionBlock)

            [작업]
            \(task)

            [파일 저장]
            file_write 도구를 사용하여 다음 경로에 파일을 저장하세요:
            \(targetPath)

            [절대 규칙 — 위반 시 실패로 간주]
            1. 반드시 한국어로 작성하세요.
            2. file_write 도구로 파일을 반드시 생성하세요.
            3. 모르는 주제나 최신 정보가 필요하면 web_search로 검색한 후 작성하세요.
            4. 사용자에게 추가 질문을 하지 마세요.
            5. 파일 생성 완료 후 간단히 결과만 알려주세요.
            """
        } else {
            // 텍스트 포맷 (md, csv, json, txt, pdf): Markdown/텍스트 출력 → 시스템 저장
            docPrompt = """
            \(systemPrompt(for: agent, roomID: roomID))

            ⚠️ 당신은 지금 "문서 작성 모드"입니다.
            할 일은 딱 하나: 본문을 텍스트로 출력하는 것.
            파일 저장은 시스템이 자동으로 처리합니다. 당신은 텍스트만 출력하면 됩니다.

            이전 대화와 분석 내용을 바탕으로 문서를 작성합니다.
            \(previousContext)\(templateBlock)\(formatConversionBlock)

            [작업]
            \(task)
            ※ 위 작업에서 파일 형식(PDF, MD 등)이 언급되어도 신경 쓰지 마세요.
            시스템이 알아서 처리합니다. 당신은 텍스트만 출력하면 됩니다.

            [절대 규칙 — 위반 시 실패로 간주]
            1. 반드시 한국어로 작성하세요. 영어로 응답하지 마세요.
            2. 서론, 인사말, 설명 없이 바로 문서 본문을 출력하세요.
            3. 도구 호출 없이 텍스트만 출력하세요. 시스템이 파일 저장을 대신합니다.
            4. 파일 저장, 권한, 도구, 스크립트, 설치 명령에 대해 일절 언급하지 마세요.
            5. 모르는 주제나 최신 정보가 필요하면 web_search로 검색한 후 작성하세요.
            6. 사용자에게 추가 질문을 하지 마세요.
            7. 완전한 문서를 처음부터 끝까지 빠짐없이 출력하세요.

            [문서 포맷]
            - 제목은 # (H1)으로 시작
            - 주요 섹션은 ## (H2), 하위 섹션은 ### (H3) 사용
            - 핵심 정보는 표(테이블)로 요약
            - 출처가 있으면 문서 마지막에 "## 참고 자료" 섹션으로 정리
            - Markdown 문법을 일관되게 사용하세요
            """
        }

        let context = makeToolContext(roomID: roomID, currentAgentID: id)
        let msgID = UUID()

        // 도구 활동 추적용 progress 메시지
        let progressMsg = ChatMessage(
            role: .system,
            content: "문서 작성 중…",
            messageType: .progress
        )
        appendMessage(progressMsg, to: roomID)

        do {
            let placeholder = ChatMessage(id: msgID, role: .assistant, content: "", agentName: agent.name)
            appendMessage(placeholder, to: roomID)

            let buffer = StreamBuffer()
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: docPrompt,
                conversationMessages: history,
                context: context,
                onToolActivity: { [weak self] activity, detail in
                    guard let self else { return }
                    Task { @MainActor in
                        let toolMsg = ChatMessage(
                            role: .assistant,
                            content: activity,
                            agentName: agent.name,
                            messageType: .toolActivity,
                            activityGroupID: progressMsg.id,
                            toolDetail: detail
                        )
                        self.insertMessage(toolMsg, to: roomID, beforeMessageID: msgID)
                    }
                },
                onStreamChunk: { [weak self] chunk in
                    guard let self else { return }
                    let current = buffer.append(chunk)
                    Task { @MainActor in
                        self.updateMessageContent(msgID, newContent: current, in: roomID)
                    }
                },
                allowedToolIDs: isBinaryFormat ? ["web_search", "file_write", "shell_exec"] : ["web_search"]
            )
            updateMessageContent(msgID, newContent: response, in: roomID)
        } catch {
            let errMsg = ChatMessage(role: .system, content: "문서 작성 중 오류: \(error.localizedDescription)", messageType: .error)
            appendMessage(errMsg, to: roomID)
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
        return msgID
    }

    // MARK: - clarify 후 문서 신호 재감지

    /// 사용자 피드백 메시지에서 문서 출력 신호 감지 (clarify 이후 실행)
    func detectDocumentSignalFromMessages(roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              !rooms[idx].workflowState.autoDocOutput else { return }

        let recentUserMessages = rooms[idx].messages
            .filter { $0.role == .user }
            .suffix(3)
            .map { $0.content }
            .joined(separator: " ")

        if let docResult = DocumentRequestDetector.quickDetect(recentUserMessages),
           docResult.isDocumentRequest {
            rooms[idx].workflowState.setAutoDocOutput(true)
            rooms[idx].workflowState.setDocumentType(docResult.suggestedDocType ?? .freeform)
        }
    }

    /// 사용자가 방에 메시지 보내기
    func sendUserMessage(_ text: String, to roomID: UUID, attachments: [FileAttachment]? = nil) async {
        let userMsg = ChatMessage(role: .user, content: text, attachments: attachments)
        appendMessage(userMsg, to: roomID)

        guard let room = rooms.first(where: { $0.id == roomID }) else { return }

        // 작업 진행 중: 워크플로우를 취소하지 않음 (승인 대기·입력 대기·실행 중 모두 포함)
        if room.isActive {
            approvalGates.provideUserInput(roomID: roomID, input: text)
            scheduleSave()
            return
        }

        // 완료/실패 → 새 후속 사이클 시작
        roomTasks[roomID]?.cancel()
        roomTasks[roomID] = Task { [weak self] in
            await self?.launchFollowUpCycle(roomID: roomID, task: text)
            self?.roomTasks.removeValue(forKey: roomID)
        }
    }

    /// 후속 사이클: 완료/실패 방에서 후속 질문 시 assemble부터 경량 워크플로우 재실행
    func launchFollowUpCycle(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // 즉시 타이핑 인디케이터 표시 (사용자에게 "반응 중" 피드백)
        if let firstAgentID = rooms[idx].assignedAgentIDs.first {
            speakingAgentIDByRoom[roomID] = firstAgentID
        }

        // 이전 사이클 문서 플래그 리셋
        rooms[idx].workflowState.setAutoDocOutput(false)
        rooms[idx].workflowState.setDocumentType(nil)

        // 문서 요청 감지 → 플래그만 설정 (숏컷 제거 — assemble 경유로 적합 에이전트 판단)
        var detectedDocType: DocumentType? = nil
        if let docResult = DocumentRequestDetector.quickDetect(task), docResult.isDocumentRequest {
            detectedDocType = docResult.suggestedDocType ?? .freeform
        } else if task.count >= 8,
           let firstAgentID = rooms[idx].assignedAgentIDs.first,
           let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
           let provider = providerManager?.provider(named: agent.providerName) {
            let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
            let llmResult = await DocumentRequestDetector.detectWithLLM(
                text: task, provider: provider, model: lightModel
            )
            if llmResult.isDocumentRequest {
                detectedDocType = llmResult.suggestedDocType ?? .freeform
            }
        }

        if let docType = detectedDocType {
            rooms[idx].workflowState.setDocumentType(docType)
            rooms[idx].workflowState.setAutoDocOutput(true)
        }

        // 타이핑 인디케이터 해제 (이후 각 phase에서 개별 설정)
        speakingAgentIDByRoom.removeValue(forKey: roomID)

        // 이전 작업 컨텍스트는 LLM에 직접 전달 (executeFollowUpAgentTurn에서 workLog 주입)
        // UI에는 표시하지 않음

        // 방 재활성화
        rooms[idx].resumeWorkflow()

        // 순수 포맷 변환 감지: 기존 대화 내용을 문서로 변환하는 요청 (새 작업 없음)
        // "md파일로 만들어줘", "문서로 정리해줘" 등 — LLM이 기존 내용을 정리하여 문서 출력
        let isFormatConversion = detectedDocType != nil && DocumentRequestDetector.isFormatConversionOnly(task)
        if isFormatConversion {
            // 문서 에이전트 배정 후 LLM 문서 작성
            let allSubAgents = agentStore?.subAgents ?? []
            let docNameKWs: Set<String> = ["문서", "리서치", "작성"]
            let nonDocKWs: Set<String> = ["개발", "jira", "프론트", "백엔드"]
            if let docAgent = allSubAgents.first(where: { sub in
                let nameL = sub.name.lowercased()
                return docNameKWs.contains(where: { nameL.contains($0) })
                    && !nonDocKWs.contains(where: { nameL.contains($0) })
            }) {
                if let i = rooms.firstIndex(where: { $0.id == roomID }),
                   !rooms[i].assignedAgentIDs.contains(docAgent.id) {
                    addAgent(docAgent.id, to: roomID, silent: false)
                }
            }

            let specialists = executingAgentIDs(in: roomID)
            if !specialists.isEmpty {
                previousCycleAgentCount[roomID] = specialists.count
                await handleDocumentOutput(roomID: roomID, task: task, suggestedType: detectedDocType, isFormatConversion: isFormatConversion)

                // handleDocumentOutput이 .completed를 설정하지 못한 경우 보완
                if let i = rooms.firstIndex(where: { $0.id == roomID }),
                   rooms[i].status != .failed && rooms[i].status != .completed {
                    rooms[i].complete()
                    pluginEventDelegate?(.roomCompleted(roomID: roomID, title: rooms[i].title))
                }
                syncAgentStatuses()
                scheduleSave()

                // 작업일지
                let hasSpec = !executingAgentIDs(in: roomID).isEmpty
                if hasSpec, let room = rooms.first(where: { $0.id == roomID }), room.workLog == nil {
                    await generateWorkLog(roomID: roomID, task: task)
                }
                if hasSpec { detectPlaybookOverrides(roomID: roomID) }
                return
            }
        }

        // --- FollowUpClassifier: 결정론적 후속 의도 분류 ---
        let previousIntent = rooms[idx].workflowState.intent
        let previousStatus = rooms[idx].status
        let previousState: FollowUpClassifier.PreviousState = {
            if previousStatus == .failed { return .failed }
            if previousIntent == .discussion || previousIntent == .research { return .discussionCompleted }
            return .implementCompleted
        }()
        let hasActionItems = rooms[idx].discussion.actionItems?.isEmpty == false
        let hasBriefing = rooms[idx].discussion.briefing != nil || rooms[idx].discussion.researchBriefing != nil
        let hasWorkLog = rooms[idx].workLog != nil

        let followUpDecision = FollowUpClassifier.classify(
            message: task,
            previousState: previousState,
            hasActionItems: hasActionItems,
            hasBriefing: hasBriefing,
            hasWorkLog: hasWorkLog
        )

        // ContextCarryoverPolicy 적용: 리셋 대상 컨텍스트 정리
        let carryover = followUpDecision.contextPolicy
        if !carryover.keepBriefing, let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].discussion.resetBriefings()
        }
        if !carryover.keepActionItems, let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].discussion.setActionItems(nil)
        }
        if !carryover.keepDecisionLog, let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].discussion.resetDecisionLog()
        }
        if !carryover.keepWorkLog, let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].clearWorkLog()
        }

        // Intent 재분류 (후속 사이클 특화)
        // FollowUpClassifier 결과를 우선 사용, 기존 로직으로 폴백
        let ruleBasedIntent = IntentClassifier.quickClassify(task)
        var resolvedIntent: WorkflowIntent?

        // FollowUpClassifier가 명확한 의도를 결정한 경우 우선 적용
        switch followUpDecision.intent {
        case .implementAll, .implementPartial, .retryExecution:
            resolvedIntent = followUpDecision.resolvedWorkflowIntent  // .task
        case .continueDiscussion, .modifyAndDiscuss, .restartDiscussion:
            resolvedIntent = followUpDecision.resolvedWorkflowIntent  // .discussion
        case .reviewResult:
            resolvedIntent = followUpDecision.resolvedWorkflowIntent  // .discussion
        case .documentResult:
            resolvedIntent = followUpDecision.resolvedWorkflowIntent  // .documentation
        case .newTask:
            resolvedIntent = nil  // 기존 로직으로 폴백
        }

        // FollowUpClassifier가 newTask이거나 기존 quickClassify가 더 구체적인 경우 폴백
        if resolvedIntent == nil {
            resolvedIntent = ruleBasedIntent
        }
        if resolvedIntent == nil {
            if task.count < 60 && detectedDocType == nil {
                // 짧은 후속 메시지: LLM 분류 없이 quickAnswer (pr해, 커밋해, 수정해줘 등)
                resolvedIntent = .quickAnswer
            } else if let firstAgentID = rooms[idx].assignedAgentIDs.first,
               let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
               let provider = providerManager?.provider(named: agent.providerName) {
                let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
                resolvedIntent = await IntentClassifier.classifyWithLLM(
                    task: task, provider: provider, model: lightModel
                )
            }
        }
        rooms[idx].workflowState.setIntent(resolvedIntent ?? .quickAnswer)

        // quickAnswer로 확정된 경우 문서 오탐 리셋 (단순 질문은 문서 요청이 아님)
        if rooms[idx].workflowState.intent == .quickAnswer && detectedDocType != nil {
            detectedDocType = nil
            rooms[idx].workflowState.setAutoDocOutput(false)
            rooms[idx].workflowState.setDocumentType(nil)
        }

        syncAgentStatuses()

        // 후속 사이클 스킵 범위 결정:
        // FollowUpClassifier의 skipPhases를 기반으로 하되, 기존 로직도 보완
        var completedPhases: Set<WorkflowPhase> = [.intake, .intent]

        // FollowUpClassifier의 skipPhases 적용
        completedPhases.formUnion(followUpDecision.skipPhases)

        // 후속 메시지에 새 외부 참조(URL/Jira 키)가 없고 기존 intakeData가 있으면
        // understand 스킵 (intakeData 덮어쓰기 + TaskBrief 유실 방지)
        if rooms[idx].clarifyContext.intakeData != nil
            && !IntakeURLExtractor.containsExternalReferences(in: task) {
            completedPhases.insert(.understand)
        }
        let specialists = executingAgentIDs(in: roomID)
        let previousAgentCount = previousCycleAgentCount[roomID] ?? specialists.count
        let agentsChanged = specialists.count != previousAgentCount
        let hasDocRequest = detectedDocType != nil
        if !specialists.isEmpty && !agentsChanged &&
           (resolvedIntent == .quickAnswer || hasDocRequest) {
            completedPhases.insert(.assemble)
        }
        // 문서 후속 요청: clarify 불필요 (사용자 의도가 명확함)
        if hasDocRequest {
            completedPhases.insert(.clarify)
        }
        // Room에 동기화
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            for phase in completedPhases {
                rooms[i].workflowState.completePhase(phase)
            }
        }
        // 현재 에이전트 수 기록 (다음 후속 사이클 비교용)
        previousCycleAgentCount[roomID] = specialists.count

        while true {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive,
                  let currentIntent = currentRoom.workflowState.intent else { break }

            let phases = currentIntent.requiredPhases
            guard let nextPhase = phases.first(where: { !completedPhases.contains($0) }) else { break }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].workflowState.advanceToPhase(nextPhase)
            }
            scheduleSave()

            switch nextPhase {
            case .intake, .intent:
                break
            case .clarify:
                await executeClarifyPhase(roomID: roomID, task: task)
            case .understand:
                await executeUnderstandPhase(roomID: roomID, task: task)
            case .assemble:
                await executeAssemblePhase(roomID: roomID, task: task)
            case .design:
                await executeDesignPhase(roomID: roomID, task: task)
            case .plan:
                let intent = rooms.first(where: { $0.id == roomID })?.workflowState.intent ?? .quickAnswer
                await executePlanPhase(roomID: roomID, task: task, intent: intent)
            case .build:
                await executeBuildPhase(roomID: roomID, task: task)
            case .execute:
                let intent = rooms.first(where: { $0.id == roomID })?.workflowState.intent ?? .quickAnswer
                await executeExecutePhase(roomID: roomID, task: task, intent: intent)
            case .review:
                await executeReviewPhase(roomID: roomID, task: task)
            case .deliver:
                await executeDeliverPhase(roomID: roomID, task: task)
            }

            completedPhases.insert(nextPhase)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].workflowState.completePhase(nextPhase)
            }
        }

        // 완료
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed && rooms[i].status != .completed {
            rooms[i].complete()
            pluginEventDelegate?(.roomCompleted(roomID: roomID, title: rooms[i].title))
        }
        syncAgentStatuses()
        scheduleSave()

        // 작업일지 + 플레이북 감지 (완료 후 비동기)
        // 전문가 없이 취소된 경우 스킵 (실질적 작업 없음)
        let hasSpecialists1 = !executingAgentIDs(in: roomID).isEmpty
        if hasSpecialists1, let room = rooms.first(where: { $0.id == roomID }), room.workLog == nil {
            await generateWorkLog(roomID: roomID, task: task)
        }
        if hasSpecialists1 { detectPlaybookOverrides(roomID: roomID) }
    }
}
