import Foundation
import os.log

private let intakeLogger = Logger(subsystem: "com.douglas.app", category: "Intake")

// MARK: - 워크플로우 실행 (Phase 6 분리)

extension RoomManager {

    // MARK: - 규칙 기반 시스템 프롬프트

    /// 방의 활성 규칙 기반으로 에이전트 시스템 프롬프트 생성
    func systemPrompt(for agent: Agent, roomID: UUID) -> String {
        let activeRuleIDs = rooms.first(where: { $0.id == roomID })?.workflowState.activeRuleIDs
        return agent.resolvedSystemPrompt(activeRuleIDs: activeRuleIDs)
    }

    // MARK: - 방 워크플로우

    /// 워크플로우 진입점: 항상 Intent 기반 Phase 워크플로우
    func startRoomWorkflow(roomID: UUID, task: String) async {
        // worktree 격리 (동일 projectPath 동시 사용 시)
        await createWorktreeIfNeeded(roomID: roomID)

        // intent 미설정 → quickClassify 시도 (nil이면 executeIntentPhase에서 사용자 선택)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }), rooms[idx].workflowState.intent == nil {
            rooms[idx].workflowState.intent = IntentClassifier.quickClassify(task)
            // quickClassify 실패 시 nil 유지 → executeIntentPhase에서 처리
        }
        await executePhaseWorkflow(roomID: roomID, task: task)
    }

    // legacyStartRoomWorkflow 삭제됨 — 모든 워크플로우는 executePhaseWorkflow를 통해 Intent 기반으로 실행

    /// 실행 대상 에이전트 (마스터 제외)
    func executingAgentIDs(in roomID: UUID) -> [UUID] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.assignedAgentIDs.filter { id in
            let agent = agentStore?.agents.first(where: { $0.id == id })
            return !(agent?.isMaster ?? false)
        }
    }

    // MARK: - Phase 워크플로우 (새 7단계)

    /// 새 워크플로우: intent.requiredPhases 동적 순회
    /// intent 단계에서 LLM 재분류 후 남은 단계가 자동으로 재계산됨
    /// 워크플로우 전체 타임아웃 (초)
    private static let workflowTimeoutSeconds: TimeInterval = 600 // 10분

    private func executePhaseWorkflow(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        rooms[idx].status = .planning
        syncAgentStatuses()

        var workflowStart = Date()
        var completedPhases: Set<WorkflowPhase> = []
        // 파일만 업로드된 경우 understand 단계에서 사용자 입력으로 task가 갱신됨
        var resolvedTask = task

        while true {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive else { break }

            // 타임아웃 체크
            if Date().timeIntervalSince(workflowStart) > Self.workflowTimeoutSeconds {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                let timeoutMsg = ChatMessage(
                    role: .system,
                    content: "워크플로우가 제한 시간(10분)을 초과하여 자동 종료되었습니다.",
                    messageType: .error
                )
                appendMessage(timeoutMsg, to: roomID)
                syncAgentStatuses()
                scheduleSave()
                return
            }

            let currentIntent = currentRoom.workflowState.intent ?? .quickAnswer
            // 현재 intent 기준으로 다음 미완료 phase 찾기
            let phases = currentIntent.requiredPhases
            guard let nextPhase = phases.first(where: { !completedPhases.contains($0) }) else { break }

            // 현재 단계 기록 + 전이 감사 기록 (내부 상태만, UI 메시지 없음)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                let previousPhase = rooms[i].workflowState.currentPhase
                rooms[i].workflowState.currentPhase = nextPhase
                rooms[i].workflowState.phaseTransitions.append(
                    PhaseTransition(from: previousPhase, to: nextPhase)
                )
            }
            scheduleSave()

            switch nextPhase {
            case .intake:
                await executeIntakePhase(roomID: roomID, task: resolvedTask)
            case .intent:
                await executeIntentPhase(roomID: roomID, task: resolvedTask)
            case .clarify:
                await executeClarifyPhase(roomID: roomID, task: resolvedTask)
                // clarify 후 문서 요청 재감지 (사용자 피드백에 문서 신호 있을 수 있음)
                detectDocumentSignalFromMessages(roomID: roomID)
            case .assemble:
                await executeAssemblePhase(roomID: roomID, task: resolvedTask)

                // assemble 완료 후: task intent이면 needsPlan 플래그 설정
                // (실제 계획 생성+승인은 design 단계에서 수행 — 중복 방지)
                if let currentRoom2 = rooms.first(where: { $0.id == roomID }),
                   currentRoom2.workflowState.intent == .task {
                    let planNeeded = await classifyNeedsPlan(roomID: roomID, task: resolvedTask)
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].workflowState.needsPlan = planNeeded
                    }
                    scheduleSave()
                }
            case .plan:
                // requiredPhases에 .plan이 없으므로 여기에 오지 않음 (안전장치)
                let intent = rooms.first(where: { $0.id == roomID })?.workflowState.intent ?? .quickAnswer
                await executePlanPhase(roomID: roomID, task: resolvedTask, intent: intent)
            case .execute:
                let intent = rooms.first(where: { $0.id == roomID })?.workflowState.intent ?? .quickAnswer
                await executeExecutePhase(roomID: roomID, task: resolvedTask, intent: intent)
            case .understand:
                // Plan C: Understand 통합 단계 — intake+intent+clarify+TaskBrief
                await executeUnderstandPhase(roomID: roomID, task: resolvedTask)
                // understand 후 사용자가 입력한 실제 task로 갱신 (파일만 업로드 등)
                if resolvedTask.isEmpty, let room = rooms.first(where: { $0.id == roomID }) {
                    resolvedTask = room.taskBrief?.goal ?? room.title
                }
                detectDocumentSignalFromMessages(roomID: roomID)
            case .design:
                // Plan C: 3턴 고정 프로토콜 (Propose → Critique → Revise)
                await executeDesignPhase(roomID: roomID, task: resolvedTask)
            case .build:
                // Plan C: Creator 단계별 실행 (riskLevel별 정책)
                await executeBuildPhase(roomID: roomID, task: resolvedTask)
            case .review:
                // Plan C: Reviewer 검토
                await executeReviewPhase(roomID: roomID, task: resolvedTask)
            case .deliver:
                // Plan C: 최종 전달 (high = Draft 프리뷰 + 명시 승인)
                await executeDeliverPhase(roomID: roomID, task: resolvedTask)
            }

            completedPhases.insert(nextPhase)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].workflowState.completedPhases = completedPhases
            }
            workflowStart = Date() // 단계 완료 후 타이머 리셋 (사용자 대기 시간으로 인한 타임아웃 방지)
        }

        // 워크플로우 완료
        // Task.isCancelled (completeRoom 등 외부 완료) 시 이미 completed 상태이므로 중복 처리 방지
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed && rooms[i].status != .completed {
            rooms[i].workflowState.currentPhase = nil
            rooms[i].status = .completed
            rooms[i].completedAt = Date()
            pluginEventDelegate?(.roomCompleted(roomID: roomID, title: rooms[i].title))
        }
        syncAgentStatuses()
        scheduleSave()

        // 작업일지 + 플레이북 감지 (완료 후 비동기)
        // Task.isCancelled 시 workLog 생성 스킵 (completeRoom이 이미 처리)
        guard !Task.isCancelled else { return }
        let hasSpecialists2 = !executingAgentIDs(in: roomID).isEmpty
        if hasSpecialists2, let room = rooms.first(where: { $0.id == roomID }), room.workLog == nil {
            // 완료 상태 확정 후 fire-and-forget (UI 지연 방지)
            Task { [weak self] in
                await self?.generateWorkLog(roomID: roomID, task: task)
            }
        }
        if hasSpecialists2 { detectPlaybookOverrides(roomID: roomID) }
    }

    /// Intent 단계: quickClassify 결과에 따라 LLM 재분류 또는 사용자 선택
    private func executeIntentPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // intent 미설정 → quickClassify 재시도 → LLM 폴백 (선택 UI 없이 자동 결정)
        if rooms[idx].workflowState.intent == nil {
            // 1) quickClassify 시도 (명확한 경우 즉시 결정)
            if let quick = IntentClassifier.quickClassify(task) {
                rooms[idx].workflowState.intent = quick
                scheduleSave()
            } else {
                // 2) LLM 분류 폴백 — 자동 적용, 사용자 선택 없음
                guard let firstAgentID = rooms[idx].assignedAgentIDs.first,
                      let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
                      let provider = providerManager?.provider(named: agent.providerName) else {
                    rooms[idx].workflowState.intent = .task
                    return
                }

                let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
                let classified = await IntentClassifier.classifyWithLLM(
                    task: task,
                    provider: provider,
                    model: lightModel
                )
                rooms[idx].workflowState.intent = classified
                scheduleSave()
            }
        }

        // 초기 메시지에서 문서 요청 감지 → autoDocOutput 플래그 설정
        if let resolvedIdx = rooms.firstIndex(where: { $0.id == roomID }) {
            let currentTask = task
            if let docResult = DocumentRequestDetector.quickDetect(currentTask), docResult.isDocumentRequest {
                rooms[resolvedIdx].workflowState.autoDocOutput = true
                rooms[resolvedIdx].workflowState.documentType = docResult.suggestedDocType ?? .freeform
            }
        }
    }

    /// Intent 확정 후 사용자에게 워크플로우 설명 메시지 표시
    private func postIntentExplanation(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let intent = room.workflowState.intent else { return }

        let msg = ChatMessage(
            role: .system,
            content: "[\(intent.displayName)] \(intent.subtitle)\n진행: \(intent.phaseSummary)",
            messageType: .phaseTransition
        )
        appendMessage(msg, to: roomID)
    }

    /// clarify 완료 후 동적으로 실행 계획 필요 여부 판별
    /// 1단계: 키워드 기반 즉시 판별 (확실한 경우)
    /// 2단계: LLM 폴백 (애매한 경우만)
    private func classifyNeedsPlan(roomID: UUID, task: String) async -> Bool {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            return false
        }

        let clarifySummary = room.clarifyContext.clarifySummary ?? task

        // 1단계: 키워드 기반 즉시 판별
        if let keywordResult = classifyNeedsPlanByKeywords(clarifySummary: clarifySummary, task: task) {
            return keywordResult
        }

        // 2단계: 애매한 경우 LLM 폴백
        let assignedAgents = room.assignedAgentIDs.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })?.name
        }.joined(separator: ", ")

        let systemPrompt = """
        사용자의 작업 요청을 보고, **실행 계획(plan)**이 필요한지 판별하세요.

        계획이 **필요한** 경우:
        - 코드 생성 또는 수정 (쿼리 변경, 함수 구현, 버그 수정 포함)
        - 여러 단계를 순차적으로 실행해야 하는 작업
        - 파일시스템 변경 (파일 생성/수정/삭제)
        - 빌드, 배포, 테스트 실행

        계획이 **불필요한** 경우:
        - 분석/리서치 (결과를 정리하여 보여주면 끝)
        - 브레인스토밍/토론
        - 문서 작성 (단일 출력물)
        - 상담/자문
        - 요약/변환

        YES 또는 NO만 출력하세요.
        """

        let userMessage = """
        [작업 요약]
        \(clarifySummary)

        [참여 에이전트]
        \(assignedAgents)

        [원본 작업]
        \(task)
        """

        let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName

        do {
            let response = try await provider.sendMessage(
                model: lightModel,
                systemPrompt: systemPrompt,
                messages: [("user", userMessage)]
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return trimmed.hasPrefix("YES")
        } catch {
            return false
        }
    }

    /// 키워드 기반 needsPlan 즉시 판별. 확실하면 Bool 반환, 애매하면 nil
    private func classifyNeedsPlanByKeywords(clarifySummary: String, task: String) -> Bool? {
        let text = "\(clarifySummary) \(task)".lowercased()

        // 구현/수정 계열 키워드 (가중치)
        let planKeywords: [(String, Int)] = [
            // 코드 수정/생성
            ("수정", 3), ("구현", 4), ("코딩", 5), ("coding", 5),
            ("fix", 5), ("implement", 4), ("리팩토", 4), ("refactor", 4),
            ("버그", 5), ("bug", 5),
            // 빌드/배포
            ("빌드", 4), ("build", 4), ("배포", 4), ("deploy", 4),
            // 파일 변경
            ("마이그레이션", 4), ("migration", 4),
            // 코드 관련 신호
            ("코드", 3), ("쿼리", 3), ("query", 3),
            ("서브쿼리", 4), ("subquery", 4),
            ("인덱스", 3), ("index", 3),
            ("from절", 4), ("where절", 4), ("join", 3),
            ("커밋", 3), ("commit", 3), ("pr", 2), ("push", 2),
            ("개선", 2), ("변경", 2),
        ]

        // 분석/리서치 계열 키워드
        let noPlanKeywords: [(String, Int)] = [
            ("리서치", 3), ("research", 3),
            ("요약", 3), ("summarize", 3), ("summary", 3),
            ("설명", 3), ("번역", 4), ("translate", 4),
            ("자문", 3), ("상담", 3), ("의견", 3),
            ("브레인스토밍", 4), ("brainstorm", 4),
        ]

        var planScore = 0
        var noPlanScore = 0

        for (keyword, weight) in planKeywords {
            if text.contains(keyword) { planScore += weight }
        }
        for (keyword, weight) in noPlanKeywords {
            if text.contains(keyword) { noPlanScore += weight }
        }

        // 확실한 구현 작업
        if planScore >= 5 { return true }
        // 확실한 분석 작업 (구현 신호 미약)
        if noPlanScore >= 5 && planScore < 3 { return false }
        // 애매 → LLM 폴백
        return nil
    }

    /// Intake 단계: 입력 파싱, Jira fetch, IntakeData 저장, 플레이북 로드
    private func executeIntakePhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // 0) URL 오타 자동 교정 (ttps:// → https:// 등)
        let correctedTask = IntakeURLCorrector.correct(task)

        // 1) URL 감지
        let urls = extractURLs(from: correctedTask)

        // 2) Jira URL 감지 + fetch
        let jiraConfig = JiraConfig.shared
        var sourceType: InputSourceType = .text
        var jiraKeys: [String] = []
        var jiraDataList: [JiraTicketSummary] = []

        // 개별 URL 단위로 Jira 판별 (전체 텍스트가 아닌 추출된 URL 사용)
        var jiraURLs = urls.filter { jiraConfig.isJiraURL($0) }

        // Jira 키(PROJ-123 패턴)만 입력한 경우에도 URL 생성하여 fetch
        if jiraConfig.isConfigured {
            jiraKeys = extractJiraKeys(from: correctedTask)
            // URL에서 이미 감지된 키 제외하고, 키만 입력된 것에 대해 URL 생성
            let keysFromURLs = Set(jiraURLs.flatMap { extractJiraKeys(from: $0) })
            let keyOnlyKeys = jiraKeys.filter { !keysFromURLs.contains($0) }
            let keyBasedURLs = keyOnlyKeys.map { jiraConfig.buildBrowseURL(forKey: $0) }
            jiraURLs += keyBasedURLs
        }

        if jiraConfig.isConfigured, !jiraURLs.isEmpty {
            sourceType = .jira
            intakeLogger.info("Jira intake: keys=\(jiraKeys, privacy: .public), urls=\(jiraURLs.count) 건")
            // 각 Jira URL에서 티켓 요약 fetch (최대 10건)
            jiraDataList = await fetchJiraTicketSummaries(urls: Array(jiraURLs.prefix(10)))
            intakeLogger.info("Jira fetch 완료: \(jiraDataList.count)/\(jiraURLs.prefix(10).count) 건 성공")
        } else if !urls.isEmpty {
            sourceType = .url
        } else if !jiraKeys.isEmpty, !jiraConfig.isConfigured {
            intakeLogger.warning("Jira 키 감지(\(jiraKeys, privacy: .public))되었으나 JiraConfig 미설정")
        }

        // 3) IntakeData 저장
        let intakeData = IntakeData(
            sourceType: sourceType,
            rawInput: task,
            jiraKeys: jiraKeys,
            jiraDataList: jiraDataList,
            urls: urls
        )
        rooms[idx].clarifyContext.intakeData = intakeData

        // 4) 플레이북 로드 (내부 데이터만, UI 메시지 없음)
        if let projectPath = rooms[idx].primaryProjectPath {
            if let playbook = PlaybookManager.load(from: projectPath) {
                rooms[idx].clarifyContext.playbook = playbook
            }
        }

        // 5) 업무 규칙 매칭 (에이전트 workRules 기반)
        if let firstAgentID = rooms[idx].assignedAgentIDs.first,
           let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
           !agent.workRules.isEmpty {
            let activeIDs = WorkRuleMatcher.match(rules: agent.workRules, taskText: task)
            rooms[idx].workflowState.activeRuleIDs = activeIDs
        }

        scheduleSave()
    }

    /// Clarify 단계: 복명복창 — DOUGLAS가 이해한 내용을 요약하고 사용자 컨펌까지 무한 루프
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
                        rooms[i].title = refined
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
                rooms[i].awaitingType = .clarification
                rooms[i].transitionTo(.awaitingApproval)
            }
            syncAgentStatuses()
            scheduleSave()

            let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                approvalContinuations[roomID] = continuation
            }
            approvalContinuations.removeValue(forKey: roomID)
            guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            if approved {
                // 승인됨 → clarify 요약 저장 + delegation 분리 + planning 복귀
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].clarifyContext.delegationInfo = parseDelegationBlock(currentSummary)
                    rooms[i].clarifyContext.clarifySummary = stripDelegationBlock(currentSummary)
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

                let _ = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                    userInputContinuations[roomID] = continuation
                }
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
               let soloName = agentStore?.agents.first(where: { $0.id == solo })?.name,
               let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].agentRoles[soloName] = .creator
            }

            // 참여 메시지 표시
            let masterName = agentStore?.masterAgent?.name ?? "DOUGLAS"
            let docDescs = executingAgentIDs(in: roomID).compactMap { id -> String? in
                guard let name = agentStore?.agents.first(where: { $0.id == id })?.name else { return nil }
                if let role = rooms.first(where: { $0.id == roomID })?.agentRoles[name] {
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
                let tags = agent.skillTags.isEmpty ? "" : " (전문: \(agent.skillTags.joined(separator: ", ")))"
                return "- \(agent.name)\(tags)"
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
                : "불확실하면 적게 요청하세요 (1~2명이면 충분한 경우가 많습니다)."
        case .discussion:
            maxAgentHint = "이 작업은 토론/의견 교환이므로 **2명 이상** 요청하세요. 다양한 관점이 필요합니다."
        default:
            maxAgentHint = "불확실하면 적게 요청하세요 (1~2명이면 충분한 경우가 많습니다)."
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
        - [필수] 역할이름: 이 역할이 필요한 이유
        - [선택] 역할이름: 이 역할이 필요한 이유
        ```

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
        // AgentMatcher.koreanStripSuffixes 공용 리스트 사용 (중복 제거)
        let taskWords = taskLowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .map { word -> String in
                for particle in AgentMatcher.koreanStripSuffixes {
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

            // 2) 시스템 매칭 (Plan C: 3단 가중치 + 신뢰도 임계값)
            let subAgents = agentStore?.subAgents ?? []
            let taskBrief = rooms.first(where: { $0.id == roomID })?.taskBrief
            let matched = AgentMatcher.matchRoles(
                requirements: requirements,
                agents: subAgents,
                intent: intent,
                documentType: rooms.first(where: { $0.id == roomID })?.workflowState.documentType,
                taskBrief: taskBrief
            )

            // 3) [필수] matched(0.7+) 에이전트 자동 초대
            for req in matched where req.status == .matched && req.priority == .required {
                if let agentID = req.matchedAgentID,
                   let room = rooms.first(where: { $0.id == roomID }),
                   !room.assignedAgentIDs.contains(agentID) {
                    addAgent(agentID, to: roomID, silent: true)
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
                    rooms[i].awaitingType = .agentConfirmation
                    rooms[i].pendingAgentConfirmationID = agentID
                    rooms[i].transitionTo(.awaitingApproval)
                }
                syncAgentStatuses()
                scheduleSave()

                let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = cont
                }
                approvalContinuations.removeValue(forKey: roomID)
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

            // 5) RuntimeRole 사전 배정 (Plan C: Assemble에서 배정)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                let specialists = executingAgentIDs(in: roomID)
                if specialists.count >= 2 {
                    let (creatorID, reviewerID, plannerID) = assignDesignRoles(specialists: specialists)
                    if let creatorName = agentStore?.agents.first(where: { $0.id == creatorID })?.name {
                        rooms[i].agentRoles[creatorName] = .creator
                    }
                    if let reviewerName = agentStore?.agents.first(where: { $0.id == reviewerID })?.name {
                        rooms[i].agentRoles[reviewerName] = .reviewer
                    }
                    if let plannerID, let plannerName = agentStore?.agents.first(where: { $0.id == plannerID })?.name {
                        rooms[i].agentRoles[plannerName] = .planner
                    }
                } else if let solo = specialists.first, let name = agentStore?.agents.first(where: { $0.id == solo })?.name {
                    rooms[i].agentRoles[name] = .creator
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
            let answer: String = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                self.userInputContinuations[roomID] = continuation
            }

            guard !answer.isEmpty else {
                userInputContinuations.removeValue(forKey: roomID)
                return
            }
            let userAnswer = answer

            // 사용자 응답을 actualTask로 설정
            // (URL/Jira 데이터는 이미 intakeData에 저장되어 있으므로 별도 보존 불필요)
            actualTask = userAnswer
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
                let titleText = userAnswer.prefix(30).components(separatedBy: "\n").first ?? String(userAnswer.prefix(30))
                rooms[i].title = String(titleText)
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
            rooms[idx].taskBrief = TaskBrief(
                goal: actualTask,
                outputType: inferredOutput,
                needsClarification: false
            )
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
                brief.needsClarification = false
                brief.questions = []
            }
            rooms[idx].taskBrief = brief
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
            let answer: String = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                self.userInputContinuations[roomID] = continuation
            }

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
                        rooms[i].taskBrief = updatedBrief
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

    /// Design 단계 (Plan C): outputType에 따라 토론 모드 / 계획 모드 분기
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
            if room.workflowState.intent == .discussion {
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
        let debateMode = DebateClassifier.classify(topic: task, agentRoles: agentRoles, modifiers: modifiers)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].discussion.debateMode = debateMode
        }

        await executeDiscussionDesign(roomID: roomID, task: task, briefContext: briefContext, specialists: specialists)

        // task intent: 토론 결과를 바탕으로 실행 계획 생성 + 승인
        if room.workflowState.intent != .discussion {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            let discussionOutput = rooms.first(where: { $0.id == roomID })?.clarifyContext.clarifySummary ?? ""

            if rooms.first(where: { $0.id == roomID })?.plan == nil {
                let plan = await requestPlan(roomID: roomID, task: task, designOutput: discussionOutput)
                if let plan, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].plan = plan
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
    private func assignDesignRoles(specialists: [UUID]) -> (creator: UUID, reviewer: UUID, planner: UUID?) {
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

        let userFeedback1: String = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            userInputContinuations[roomID] = cont
        }

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
                // 피드백 실패는 무시하고 계속 진행
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

        let userFeedback2: String = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            userInputContinuations[roomID] = cont
        }

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
            rooms[i].clarifyContext.clarifySummary = (rooms[i].clarifyContext.clarifySummary ?? "") + "\n\n[토론 결과]\n" + discussionSummary
        }

        let masterAgent = agentStore?.masterAgent
        let masterProvider = masterAgent.flatMap { providerManager?.provider(named: $0.providerName) }

        if let master = masterAgent, let provider = masterProvider {
            let synthesisProgressMsg = ChatMessage(role: .system, content: "토론 결과를 종합합니다.", messageType: .progress)
            appendMessage(synthesisProgressMsg, to: roomID)

            let synthesisPrompt = """
            당신은 DOUGLAS, 이 토론의 진행자입니다.
            전문가들의 의견과 피드백을 종합하여 실행 가능한 결론을 도출하세요.

            규칙:
            - 반드시 아래 순서로 정리하세요: 결론(추천안) → 대안 → 트레이드오프 → 미해결 쟁점.
            - 결론에서는 어떤 방향이 왜 더 적합한지 근거와 함께 명확히 추천하세요.
            - 마크다운 헤더(##, ###) 최소화. 읽기 좋은 문단 형식으로.
            - 전체 길이는 원본 의견의 절반 이하로 압축하세요.
            """

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

            let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                approvalContinuations[roomID] = cont
            }
            approvalContinuations.removeValue(forKey: roomID)
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
                        rooms[i].plan!.version += 1
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
                    // 재생성 실패 → 워크플로우 중단 (.failed로 전환하여 phase loop 탈출)
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.failed)
                        rooms[i].completedAt = Date()
                    }
                    let failMsg = ChatMessage(
                        role: .system,
                        content: "계획 재수립에 실패했습니다. 새 요청으로 다시 시도해주세요.",
                        messageType: .error
                    )
                    appendMessage(failMsg, to: roomID)
                    syncAgentStatuses()
                    scheduleSave()
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
        let reviewerName = room.agentRoles.first(where: { $0.value == .reviewer })?.key
        let reviewerAgent: Agent?
        if let name = reviewerName {
            reviewerAgent = agentStore?.agents.first(where: { $0.name == name })
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
        let creatorName = room.agentRoles.first(where: { $0.value == .creator })?.key
        let creatorAgent = creatorName.flatMap { name in agentStore?.agents.first(where: { $0.name == name }) }
            ?? executingAgentIDs(in: roomID).first.flatMap { id in agentStore?.agents.first(where: { $0.id == id }) }

        let briefContext: String
        if let brief = room.taskBrief {
            briefContext = "목표: \(brief.goal)\n성공기준: \(brief.successCriteria.joined(separator: ", "))"
        } else {
            briefContext = room.clarifyContext.clarifySummary ?? task
        }

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

            \(briefContext)

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

        // discussion: 토론 완료 (종합은 Design에서 이미 완료)
        if room.workflowState.intent == .discussion {
            let doneMsg = ChatMessage(
                role: .system,
                content: "토론이 마무리되었습니다.",
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

    // MARK: - Intake 헬퍼

    /// 텍스트에서 URL 추출 (오타 자동 교정 후)
    private func extractURLs(from text: String) -> [String] {
        IntakeURLExtractor.extractURLs(from: text)
    }

    /// 텍스트에서 모든 Jira 키 추출 (중복 제거, 순서 유지)
    private func extractJiraKeys(from text: String) -> [String] {
        IntakeURLExtractor.extractJiraKeys(from: text)
    }

    /// 여러 Jira URL에서 티켓 요약을 동시 fetch
    private func fetchJiraTicketSummaries(urls: [String]) async -> [JiraTicketSummary] {
        await withTaskGroup(of: JiraTicketSummary?.self, returning: [JiraTicketSummary].self) { group in
            for urlString in urls {
                group.addTask { [self] in
                    await self.fetchSingleJiraTicket(urlString: urlString)
                }
            }
            var results: [JiraTicketSummary] = []
            for await result in group {
                if let ticket = result { results.append(ticket) }
            }
            return results
        }
    }

    /// 단일 Jira URL에서 티켓 요약 fetch
    private func fetchSingleJiraTicket(urlString: String) async -> JiraTicketSummary? {
        let jiraConfig = JiraConfig.shared
        let apiURLString = jiraConfig.apiURL(from: urlString)
        guard let apiURL = URL(string: apiURLString),
              let auth = jiraConfig.authHeader() else {
            intakeLogger.warning("Jira fetch 실패: URL 파싱 불가 또는 인증 헤더 없음 (\(urlString, privacy: .public))")
            return nil
        }

        var request = URLRequest(url: apiURL)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                intakeLogger.warning("Jira fetch HTTP \(status) — \(apiURLString, privacy: .public)")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                intakeLogger.warning("Jira fetch JSON 파싱 실패 — \(apiURLString, privacy: .public)")
                return nil
            }

            let fields = json["fields"] as? [String: Any] ?? [:]
            let key = json["key"] as? String ?? ""
            let summary = fields["summary"] as? String ?? ""
            let issueType = (fields["issuetype"] as? [String: Any])?["name"] as? String ?? ""
            let statusName = (fields["status"] as? [String: Any])?["name"] as? String ?? ""
            let description = extractDescription(from: fields["description"])

            intakeLogger.info("Jira fetch 성공: \(key, privacy: .public) — \(summary, privacy: .public)")

            return JiraTicketSummary(
                key: key,
                summary: summary,
                issueType: issueType,
                status: statusName,
                description: description
            )
        } catch {
            intakeLogger.error("Jira fetch 네트워크 에러: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Jira ADF(Atlassian Document Format) 또는 일반 텍스트에서 설명 추출 (최대 1000자)
    private func extractDescription(from value: Any?) -> String {
        let raw: String
        if let text = value as? String {
            raw = text
        } else if let adf = value as? [String: Any],
                  let content = adf["content"] as? [[String: Any]] {
            raw = content.compactMap { node -> String? in
                guard let innerContent = node["content"] as? [[String: Any]] else { return nil }
                return innerContent.compactMap { inner -> String? in
                    inner["text"] as? String
                }.joined()
            }.joined(separator: "\n")
        } else {
            return ""
        }
        return raw.count > 1000 ? String(raw.prefix(1000)) + "…" : raw
    }

    /// 에이전트에게 계획 수립 요청
    private func requestPlan(roomID: UUID, task: String, previousPlan: RoomPlan? = nil, feedback: String? = nil, designOutput: String? = nil) async -> RoomPlan? {
        guard let room = rooms.first(where: { $0.id == roomID }) else {
            return nil
        }
        // 전문가(마스터 제외)를 계획 생성자로 선택
        let specialistID = room.assignedAgentIDs.first { id in
            guard let a = agentStore?.agents.first(where: { $0.id == id }) else { return false }
            return !(a.isMaster)
        } ?? room.assignedAgentIDs.first
        guard let firstAgentID = specialistID,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            let errorMsg = ChatMessage(
                role: .system,
                content: "에이전트 또는 API 연결을 찾을 수 없습니다."
            )
            appendMessage(errorMsg, to: roomID)
            return nil
        }

        // intake 데이터 (Jira 트리거 제거된 중립 버전)
        let intakeContext: String
        if let intakeData = room.clarifyContext.intakeData {
            intakeContext = "\n" + intakeData.asClarifyContextString()
        } else {
            intakeContext = ""
        }

        // 브리핑 + 산출물 기반 컨텍스트 구성 (토큰 예산 제한)
        // Context Archive 패턴: 토론 원문 아카이브 → 예산 내 활용 → 초과 시 briefing 폴백
        var briefingContext: String
        if let fullLog = room.discussion.fullDiscussionLog, !fullLog.isEmpty {
            // 토론 원문 아카이브 사용 (축소 전 기록된 전문)
            briefingContext = "[토론 원문]\n" + fullLog
            // 예산 초과 시 단계적 축소: 원문 4000자 → 초과하면 briefing 폴백
            if briefingContext.count > 4000 {
                if let briefing = room.discussion.briefing {
                    // briefing 요약 + 원문 핵심 부분 (앞뒤 각 1000자)
                    let head = String(fullLog.prefix(1000))
                    let tail = String(fullLog.suffix(1000))
                    briefingContext = briefing.asContextString() + "\n\n[토론 원문 발췌]\n…\(head)\n…(중략)…\n\(tail)…"
                } else {
                    briefingContext = String(briefingContext.prefix(4000)) + "…(이하 생략)"
                }
            }
        } else if let briefing = room.discussion.briefing {
            briefingContext = briefing.asContextString()
        } else {
            // 폴백: 기존 토론 히스토리에서 요약 생성
            let history = buildDiscussionHistory(roomID: roomID, currentAgentName: agent.name)
            briefingContext = history.map { "[\($0.role)] \($0.content)" }.suffix(10).joined(separator: "\n")
        }
        // 최종 안전장치: 최대 4000자
        if briefingContext.count > 4000 {
            briefingContext = String(briefingContext.prefix(4000)) + "…(이하 생략)"
        }

        var artifactContext: String
        if !room.discussion.artifacts.isEmpty {
            // 계획 수립용: 산출물 프리뷰만 전달 (토큰 절감, 전체 내용은 실행 단계에서 사용)
            artifactContext = "\n\n[참고 산출물]\n" + room.discussion.artifacts.map {
                let preview = $0.content.prefix(100)
                let suffix = $0.content.count > 100 ? "... (\($0.content.count)자)" : ""
                return "[\($0.type.displayName)] \($0.title) (v\($0.version)):\n\(preview)\(suffix)"
            }.joined(separator: "\n---\n")
            // 산출물 전체 최대 1000자
            if artifactContext.count > 1000 {
                artifactContext = String(artifactContext.prefix(1000)) + "…"
            }
        } else {
            artifactContext = ""
        }

        // 플레이북 컨텍스트 주입
        let playbookContext: String
        if let playbook = room.clarifyContext.playbook {
            playbookContext = "\n\n[프로젝트 플레이북]\n" + playbook.asContextString()
        } else {
            playbookContext = ""
        }

        // 방 내 전문가 목록 (마스터 제외)
        let specialistNames: String
        let specialists = room.assignedAgentIDs.compactMap { id -> String? in
            guard let agent = agentStore?.agents.first(where: { $0.id == id }) else { return nil }
            if agent.isMaster { return nil }
            return agent.name
        }
        specialistNames = specialists.isEmpty ? "(없음)" : specialists.joined(separator: ", ")

        // 원래 사용자 요청 앵커링
        let clarifyContext: String
        if let summary = room.clarifyContext.clarifySummary {
            clarifyContext = "\n[원래 사용자 요청]\n\(summary)\n"
        } else {
            clarifyContext = ""
        }

        // 문서 유형 템플릿 주입
        let docTemplateContext = room.workflowState.documentType?.templatePromptBlock() ?? ""

        // 프로젝트 경로
        let projectPathsContext = room.effectiveProjectPaths.isEmpty ? "" : "\n[프로젝트 경로]\n" + room.effectiveProjectPaths.map { "- \($0)" }.joined(separator: "\n")

        // 토큰 예산: 시스템 프롬프트 합산이 8000자 초과 시 briefing/artifact 추가 절단
        let basePromptSize = systemPrompt(for: agent, roomID: roomID).count
            + intakeContext.count + clarifyContext.count + docTemplateContext.count + playbookContext.count + projectPathsContext.count
        let contextBudget = max(0, 8000 - basePromptSize)
        if briefingContext.count + artifactContext.count > contextBudget {
            let briefingBudget = contextBudget * 2 / 3
            let artifactBudget = contextBudget - briefingBudget
            if briefingContext.count > briefingBudget {
                briefingContext = String(briefingContext.prefix(briefingBudget)) + "…"
            }
            if artifactContext.count > artifactBudget {
                artifactContext = String(artifactContext.prefix(artifactBudget)) + "…"
            }
            print("[DOUGLAS] ⚠️ requestPlan 토큰 예산 초과 — briefing/artifact 절단 (base=\(basePromptSize), budget=\(contextBudget))")
        }

        let planSystemPrompt = """
        \(systemPrompt(for: agent, roomID: roomID))
        \(intakeContext)\(clarifyContext)\(projectPathsContext)\(docTemplateContext.isEmpty ? "" : "\n\(docTemplateContext)\n")
        현재 작업방에 배정되었습니다. 팀원들과의 토론이 완료되었습니다.
        **사용자의 원래 요청을 반드시 충족하는** 실행 계획을 제출하세요.
        토론에서 우려사항이 나왔더라도, 사용자가 명시적으로 요청한 작업(구현, PR, 배포 등)은 계획에 포함해야 합니다.
        토론 의견은 구현 방식의 참고 자료로만 활용하세요. 사용자 요청 범위를 축소하지 마세요.

        {"plan": {"summary": "전체 계획 요약", "estimated_minutes": 5, "steps": [{"text": "단계 설명", "agent": "담당 에이전트 이름", "working_directory": "/프로젝트/경로"}, ...]}}

        방 내 전문가: \(specialistNames)

        규칙:
        - 각 단계는 **한 가지 명확한 산출물**을 가져야 합니다 (코드 작성, 테스트, PR 오픈 등).
        - 사용자 검수/승인이 필요한 지점마다 반드시 새 단계를 시작하세요.
        - 구현, PR 오픈, 코드 리뷰, 배포 등은 **반드시 별개 단계**로 분할하세요.
        - 번역, 요약, 분석 등 단일 작업은 1단계로 작성하세요.
        - 같은 에이전트가 연속 수행해도, 산출물이 다르면 단계를 나누세요.
        - estimated_minutes는 현실적으로 추정하세요 (1~30분)
        - 각 step에 "agent" 필드로 담당 전문가를 지정하세요 (위 목록에서 정확한 이름 사용)
        - 프로젝트 경로가 2개 이상이면, 각 step에 "working_directory" 필드로 해당 단계의 작업 디렉토리를 지정하세요 (위 프로젝트 경로 중 선택)
        - 마스터(진행자/오케스트레이터)는 실행 대상이 아닙니다. 마스터에게 step을 배정하지 마세요.
        - "requires_approval": true는 **외부에 영향을 미치거나 되돌리기 어려운 모든 작업**에 반드시 사용하세요. 예: 커밋, PR, push, 배포, DB 변경, API 호출, 메시지 전송, 파일 삭제 등. 코드 분석, 파일 읽기 등 읽기 전용 작업에는 불필요합니다.
        - 반드시 유효한 JSON으로만 응답하세요
        """

        // 첨부 파일 정보 포함 (첨부된 내용을 "확인하라"는 불필요한 단계 방지)
        let attachmentContext: String
        let fileAttachments = room.messages
            .compactMap { $0.attachments }
            .flatMap { $0 }
        if !fileAttachments.isEmpty {
            let imageCount = fileAttachments.filter { $0.isImage }.count
            let docCount = fileAttachments.count - imageCount
            var desc = "사용자 첨부 파일 \(fileAttachments.count)개"
            if imageCount > 0 && docCount > 0 {
                desc += " (이미지 \(imageCount)장, 문서 \(docCount)개)"
            } else if imageCount > 0 {
                desc += " (이미지 \(imageCount)장)"
            } else {
                desc += " (문서 \(docCount)개)"
            }
            attachmentContext = "\n\n[\(desc) — 이미 제공됨]\n" +
                "(파일이 이미 제공되었으므로, 사용자에게 다시 요청하지 마세요. 바로 작업하세요. 계획의 step에 파일 경로를 포함하지 마세요.)"
        } else {
            attachmentContext = ""
        }

        // 재계획 컨텍스트 (이전 계획이 거부된 경우)
        var replanContext = ""
        if let prev = previousPlan {
            let prevSteps = prev.steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
            replanContext = "\n\n[이전 계획 — 사용자가 거부함]\n\(prev.summary)\n단계:\n\(prevSteps)"
            if let fb = feedback, !fb.isEmpty {
                replanContext += "\n\n[사용자 피드백]\n\(fb)\n\n위 피드백을 반영하여 계획을 다시 수립하세요."
            } else {
                replanContext += "\n\n사용자가 이전 계획을 거부했습니다. 다른 접근 방식으로 계획을 다시 수립하세요."
            }
        }

        // Design 단계 결과가 있으면 참고 자료로 제공 (지시가 아닌 참고)
        let designContext = designOutput.map { "\n\n[Design 단계 결과 — 참고용]\n\($0)\n\n위 토론 결과는 참고 사항입니다. 계획은 반드시 사용자의 원래 요청을 충족해야 합니다." } ?? ""

        let planMessages: [(role: String, content: String)] = [
            ("user", "**[사용자 요청 — 최우선]**\n\(task)\n\n위 요청이 계획의 목표입니다. 사용자가 구현/PR/배포 등 구체적 작업을 요청했으면, 그 작업을 반드시 계획에 포함하세요. 토론에서 나온 우려사항은 참고하되, 사용자 요청 범위를 축소하지 마세요.\n\n브리핑:\n\(briefingContext)\(artifactContext)\(playbookContext)\(attachmentContext)\(replanContext)\(designContext)\n\n실행 계획을 JSON으로 작성해주세요.")
        ]

        speakingAgentIDByRoom[roomID] = firstAgentID

        do {
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "계획을 수립하는 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { _ in
                // sendRouterMessage: 도구 비활성화 (계획 수립 중 파일 수정/셸 실행 방지)
                try await provider.sendRouterMessage(
                    model: agent.modelName,
                    systemPrompt: planSystemPrompt,
                    messages: planMessages
                )
            }

            if let plan = parsePlan(from: response) {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
                return plan
            }

            // JSON 파싱 실패 → 1회 재시도 (JSON만 요청)
            let retryMessages: [(role: String, content: String)] = [
                ("user", planMessages[0].1),
                ("assistant", response),
                ("user", "위 내용을 반드시 유효한 JSON 형식으로 다시 작성하세요. {\"plan\": {\"summary\": \"...\", \"estimated_minutes\": N, \"steps\": [...]}} 형태만 응답하세요.")
            ]
            let (retryResponse, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "계획 형식을 정리하는 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { _ in
                try await provider.sendRouterMessage(
                    model: agent.modelName,
                    systemPrompt: planSystemPrompt,
                    messages: retryMessages
                )
            }

            speakingAgentIDByRoom.removeValue(forKey: roomID)
            return parsePlan(from: retryResponse)
        } catch {
            speakingAgentIDByRoom.removeValue(forKey: roomID)
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "계획 수립 실패: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            return nil
        }
    }

    /// 계획 JSON 파싱
    func parsePlan(from response: String) -> RoomPlan? {
        let jsonString = extractJSON(from: response)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let planDict = json["plan"] as? [String: Any],
              let summary = planDict["summary"] as? String,
              let estimatedMinutes = planDict["estimated_minutes"] as? Int,
              let rawSteps = planDict["steps"] as? [Any] else {
            return nil
        }

        // 에이전트 이름 → ID 매핑 (퍼지 매칭)
        let agentNameToID: [String: UUID] = {
            guard let agents = agentStore?.subAgents else { return [:] }
            var map: [String: UUID] = [:]
            for agent in agents {
                map[agent.name.lowercased()] = agent.id
            }
            return map
        }()

        func resolveAgentID(name: String?) -> UUID? {
            guard let name = name?.lowercased() else { return nil }
            if let id = agentNameToID[name] { return id }
            // 부분 매칭
            return agentNameToID.first(where: { $0.key.contains(name) || name.contains($0.key) })?.value
        }

        // steps: plain String과 {"text":"...", "agent":"...", "requires_approval": true} 혼합 지원
        var steps: [RoomStep] = []
        for raw in rawSteps {
            if let str = raw as? String {
                steps.append(RoomStep(text: str))
            } else if let dict = raw as? [String: Any], let text = dict["text"] as? String {
                let requiresApproval = dict["requires_approval"] as? Bool ?? false
                let agentName = dict["agent"] as? String
                let agentID = resolveAgentID(name: agentName)
                let riskLevel: RiskLevel
                if let rl = dict["risk_level"] as? String {
                    riskLevel = RiskLevel(rawValue: rl) ?? .low
                } else {
                    riskLevel = .low
                }
                let workingDir = dict["working_directory"] as? String
                steps.append(RoomStep(text: text, requiresApproval: requiresApproval, assignedAgentID: agentID, riskLevel: riskLevel, workingDirectory: workingDir))
            }
        }
        guard !steps.isEmpty else { return nil }

        return RoomPlan(
            summary: summary,
            estimatedSeconds: estimatedMinutes * 60,
            steps: steps
        )
    }

    /// JSON 추출 (ChatViewModel.extractJSON과 동일 로직)
    func extractJSON(from text: String) -> String {
        // 뒤에서부터 검색하여 중첩 코드블록(```json 안의 ```) 잘림 방지
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", options: .backwards, range: startRange.upperBound..<text.endIndex),
           endRange.lowerBound > startRange.upperBound {
            return String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startRange = text.range(of: "```\n"),
           let endRange = text.range(of: "\n```", options: .backwards, range: startRange.upperBound..<text.endIndex),
           endRange.lowerBound > startRange.upperBound {
            return String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    /// 방의 단계별 작업 실행
    private func executeRoomWork(roomID: UUID, task: String) async {
        guard rooms.first(where: { $0.id == roomID })?.plan != nil else { return }

        let engine = StepExecutionEngine(
            host: self, roomID: roomID, task: task, policy: .legacy
        )
        await engine.run()

        // 취소된 경우 후속 처리 중단 (completeRoom과의 race condition 방지)
        guard !Task.isCancelled else { return }

        // 완료: 상태 변경 + 작업일지 생성
        if rooms.first(where: { $0.id == roomID })?.status == .inProgress {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.completed)
                rooms[i].completedAt = Date()
            }
            previousCycleAgentCount[roomID] = executingAgentIDs(in: roomID).count
            syncAgentStatuses()

            let doneMsg = ChatMessage(role: .system, content: "모든 작업이 완료되었습니다.")
            appendMessage(doneMsg, to: roomID)
            scheduleSave()

            await generateWorkLog(roomID: roomID, task: task)
        } else {
            syncAgentStatuses()
            scheduleSave()
        }
    }

    /// 외부 영향(되돌리기 어려운) 키워드 감지 — 리뷰 게이트 강제 트리거
    static func hasExternalEffectKeywords(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = ["pr ", "pull request", "push", "배포", "deploy", "merge", "릴리스", "release", "git push"]
        return keywords.contains { lower.contains($0) }
    }

    /// step 텍스트를 짧은 "~하는 중" 스타일로 변환
    static func shortenStepLabel(_ text: String) -> String {
        // 핵심 키워드 추출: 첫 번째 의미 있는 동사/명사 구문
        let cleaned = text
            .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // 긴 텍스트면 첫 문장/절만 사용 (마침표, 쉼표, 줄바꿈 기준)
        let firstClause: String
        if let range = cleaned.rangeOfCharacter(from: CharacterSet(charactersIn: ".,\n")) {
            firstClause = String(cleaned[cleaned.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        } else {
            firstClause = cleaned
        }

        // 최대 40자로 자르고 "하는 중" 접미사
        let maxLen = 40
        let truncated: String
        if firstClause.count > maxLen {
            truncated = String(firstClause.prefix(maxLen)) + "…"
        } else {
            truncated = firstClause
        }

        // 이미 "~중" 으로 끝나면 그대로 반환
        if truncated.hasSuffix("중") {
            return truncated
        }

        return "\(truncated) 하는 중…"
    }

    /// 개별 에이전트의 단계 실행. 성공 시 true, 실패 시 false.
    @discardableResult
    func executeStep(
        step: String,
        fullTask: String,
        agentID: UUID,
        roomID: UUID,
        stepIndex: Int,
        totalSteps: Int,
        fileWriteTracker: FileWriteTracker? = nil,
        progressGroupID: UUID? = nil,
        workingDirectoryOverride: String? = nil
    ) async -> Bool {
        guard let baseAgent = agentStore?.agents.first(where: { $0.id == agentID }) else { return false }
        let agent = baseAgent
        guard let provider = providerManager?.provider(named: agent.providerName) else { return false }

        let room = rooms.first(where: { $0.id == roomID })

        // Step Journal 기반 context 구성 — 예측 가능한 고정 크기
        var history: [ConversationMessage] = []

        // 1. 첫 사용자 메시지 (이미지 첨부 보존)
        if let intakeData = room?.clarifyContext.intakeData, intakeData.sourceType != .text {
            history.append(ConversationMessage.user(intakeData.asClarifyContextString()))
        }

        // 2. 브리핑 (2000자 캡)
        if let briefing = room?.discussion.briefing {
            let ctx = briefing.asContextString()
            let capped = ctx.count > 2000 ? String(ctx.prefix(2000)) + "…" : ctx
            history.append(ConversationMessage.user("작업 브리핑:\n\(capped)"))
        }

        // 3. 첫 사용자 메시지(이미지 첨부 포함)를 항상 포함
        if let room = room,
           let firstUserMsg = room.messages.first(where: { $0.role == .user && $0.messageType == .text }),
           firstUserMsg.attachments != nil && !(firstUserMsg.attachments?.isEmpty ?? true) {
            history.append(ConversationMessage(
                role: "user", content: firstUserMsg.content,
                toolCalls: nil, toolCallID: nil, attachments: firstUserMsg.attachments,
                isError: false
            ))
        }

        // 4. Step Journal — Context Archive 패턴: 직전 단계 전문 + 나머지 요약
        if let plan = room?.plan {
            let fullResults = plan.stepResultsFull
            let journal = plan.stepJournal
            var parts: [String] = []

            // 이전 단계들 (0 ~ stepIndex-2): journal 요약 (300자)
            for i in 0..<max(0, stepIndex - 1) {
                if i < journal.count, !journal[i].isEmpty {
                    parts.append("Step \(i + 1): \(journal[i])")
                }
            }

            // 직전 단계 (stepIndex-1): 전문 아카이브 사용 (최대 3000자)
            let prevIndex = stepIndex - 1
            if prevIndex >= 0 {
                if prevIndex < fullResults.count, !fullResults[prevIndex].isEmpty {
                    let full = fullResults[prevIndex]
                    let capped = full.count > 3000 ? String(full.prefix(3000)) + "…" : full
                    parts.append("Step \(prevIndex + 1) (직전 단계 상세):\n\(capped)")
                } else if prevIndex < journal.count, !journal[prevIndex].isEmpty {
                    // 전문 없으면 journal 폴백
                    parts.append("Step \(prevIndex + 1): \(journal[prevIndex])")
                }
            }

            if !parts.isEmpty {
                let combined = parts.joined(separator: "\n")
                let capped = combined.count > 5000
                    ? String(combined.prefix(5000)) + "…"
                    : combined
                history.append(ConversationMessage.user("[이전 단계 진행 상황]\n\(capped)"))
            }
        }

        let sysPromptText = systemPrompt(for: agent, roomID: roomID)
        let artifactContext = "" // artifacts는 briefing + journal로 대체

        // 문서 유형 템플릿 (documentType 설정 시 섹션 가이드 주입)
        let docTemplateBlock: String
        if let docType = room?.workflowState.documentType, docType != .freeform {
            docTemplateBlock = "\n" + docType.templatePromptBlock()
        } else {
            docTemplateBlock = ""
        }
        let isDocumentation = room?.workflowState.documentType != nil

        // 현재 단계의 작업 디렉토리를 step prompt에 명시
        let workingDirContext: String
        if let dir = workingDirectoryOverride {
            workingDirContext = "\n[작업 디렉토리: \(dir)]"
        } else if let primary = room?.effectiveProjectPath {
            workingDirContext = "\n[작업 디렉토리: \(primary)]"
        } else {
            workingDirContext = ""
        }

        let isLastStep = stepIndex == totalSteps - 1
        var stepPrompt: String
        if isLastStep || totalSteps == 1 {
            let docWriteInstruction = isDocumentation ? """

            [중요 — 문서 작성 지침]
            이전 대화의 분석·요약은 참고 자료일 뿐입니다.
            완전한 문서를 처음부터 끝까지 빠짐없이 작성하세요.
            "이미 완성되었습니다", "추가 작업이 필요하신가요?" 등의 응답은 금지합니다.
            반드시 전체 문서 본문을 출력하세요.
            """ : ""

            stepPrompt = """
            [작업 \(stepIndex + 1)/\(totalSteps)] \(step)\(workingDirContext)
            \(artifactContext)\(docTemplateBlock)\(docWriteInstruction)

            이것이 최종 단계입니다. 사용자에게 전달할 완성된 결과물을 직접 작성하세요.
            과정 설명이나 단계 번호 없이, 결과물만 깔끔하게 출력하세요.
            """
        } else {
            stepPrompt = """
            [작업 \(stepIndex + 1)/\(totalSteps)] \(step)\(workingDirContext)
            \(artifactContext)\(docTemplateBlock)

            중간 단계입니다. 다음 단계에 필요한 핵심 데이터만 간결하게 출력하세요 (3줄 이내).
            전체 결과물은 마지막 단계에서 작성합니다.
            """
        }

        // Issue 1: 사용자 추가 지시를 stepPrompt에 주입
        stepPrompt = StepPromptBuilder.injectDirective(into: stepPrompt, from: fullTask)

        // catch에서도 접근 필요한 변수들을 do 블록 밖에 선언
        let streamPlaceholderID = UUID()
        let buffer = StreamBuffer()
        let context = makeToolContext(roomID: roomID, currentAgentID: agentID, fileWriteTracker: fileWriteTracker, workingDirectoryOverride: workingDirectoryOverride)

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)
            speakingAgentIDByRoom[roomID] = agentID

            // 실행 시작 시각 (완료 활동에서 소요 시간 계산용)
            let stepStartTime = Date()

            // 단계 시작 활동: 어떤 작업을 수행하는지 표시
            if let progressGroupID {
                let stepLabel = step.count > 60 ? String(step.prefix(57)) + "..." : step
                let startDetail = ToolActivityDetail(
                    toolName: "llm_call",
                    subject: "[\(stepIndex + 1)/\(totalSteps)] \(stepLabel)",
                    contentPreview: nil,
                    isError: false
                )
                let startMsg = ChatMessage(
                    role: .assistant,
                    content: stepLabel,
                    agentName: agent.name,
                    messageType: .toolActivity,
                    activityGroupID: progressGroupID,
                    toolDetail: startDetail
                )
                appendMessage(startMsg, to: roomID)

                // 작업 컨텍스트 정보 활동
                let ruleCount = room?.workflowState.activeRuleIDs?.count ?? agent.workRules.count
                let toolCount = agent.resolvedToolIDs.count
                let artifactCount = room?.discussion.artifacts.count ?? 0
                let contextSummary = StepPromptBuilder.buildContextSummary(
                    ruleCount: ruleCount, toolCount: toolCount, artifactCount: artifactCount
                )
                let contextDetail = ToolActivityDetail(
                    toolName: "context_info",
                    subject: contextSummary,
                    contentPreview: nil,
                    isError: false
                )
                let contextMsg = ChatMessage(
                    role: .assistant,
                    content: contextSummary,
                    agentName: agent.name,
                    messageType: .toolActivity,
                    activityGroupID: progressGroupID,
                    toolDetail: contextDetail
                )
                appendMessage(contextMsg, to: roomID)
            }

            // 스트리밍용 placeholder 메시지 (실시간 텍스트 업데이트)
            let streamPlaceholder = ChatMessage(id: streamPlaceholderID, role: .assistant, content: "", agentName: agent.name)
            appendMessage(streamPlaceholder, to: roomID)

            let messagesWithStep = history + [ConversationMessage.user(stepPrompt)]

            // Pre-flight 토큰 + 작업 디렉토리 로깅 (디버깅용)
            let sysTokens = TokenEstimator.estimate(sysPromptText)
            let msgTokens = TokenEstimator.estimate(messagesWithStep.compactMap(\.content))
            let resolvedDir = workingDirectoryOverride ?? room?.effectiveProjectPath ?? "(없음)"
            print("[DOUGLAS] 📊 Step \(stepIndex + 1)/\(totalSteps) 토큰 추정: sys=\(sysTokens) msg=\(msgTokens) total=\(sysTokens + msgTokens + 4_000) dir=\(resolvedDir)")

            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: sysPromptText,
                conversationMessages: messagesWithStep,
                context: context,
                onToolActivity: { [weak self] activity, detail in
                    guard let self else { return }
                    Task { @MainActor in
                        let toolMsg = ChatMessage(
                            role: .assistant,
                            content: activity,
                            agentName: agent.name,
                            messageType: .toolActivity,
                            activityGroupID: progressGroupID,
                            toolDetail: detail
                        )
                        self.appendMessage(toolMsg, to: roomID)
                    }
                },
                onStreamChunk: { [weak self] chunk in
                    guard let self else { return }
                    let current = buffer.append(chunk)
                    Task { @MainActor in
                        self.updateMessageContent(streamPlaceholderID, newContent: current, in: roomID)
                    }
                }
            )

            // 에이전트 응답 이벤트
            pluginEventDelegate?(.agentResponseReceived(
                roomID: roomID,
                agentName: agent.name,
                responsePreview: String(response.prefix(300))
            ))

            // llm_result 완료 활동
            if let progressGroupID {
                let stepDuration = Date().timeIntervalSince(stepStartTime)
                let durationStr = stepDuration < 60
                    ? String(format: "%.1f초", stepDuration)
                    : String(format: "%d분 %.0f초", Int(stepDuration) / 60, stepDuration.truncatingRemainder(dividingBy: 60))
                let resultDetail = ToolActivityDetail(
                    toolName: "llm_result",
                    subject: "\(durationStr) | \(response.count)자",
                    contentPreview: nil,
                    isError: false
                )
                let resultMsg = ChatMessage(
                    role: .assistant,
                    content: "실행 완료 (\(durationStr))",
                    agentName: agent.name,
                    messageType: .toolActivity,
                    activityGroupID: progressGroupID,
                    toolDetail: resultDetail
                )
                appendMessage(resultMsg, to: roomID)
            }

            if speakingAgentIDByRoom[roomID] == agentID {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
            }

            // 최종 정리된 응답으로 placeholder 업데이트 + 중간 단계는 접힘 처리
            let cleanedResponse = expandTildePaths(stripHallucinatedAuthLines(stripTrailingOptions(response)))
            updateMessageContent(streamPlaceholderID, newContent: cleanedResponse, in: roomID)
            // 타임스탬프를 실제 완료 시점으로 갱신 (도구 활동보다 앞에 정렬되는 문제 방지)
            if let i = rooms.firstIndex(where: { $0.id == roomID }),
               let mi = rooms[i].messages.firstIndex(where: { $0.id == streamPlaceholderID }) {
                rooms[i].messages[mi].timestamp = Date()
                if !(isLastStep || totalSteps == 1) {
                    rooms[i].messages[mi].messageType = .toolActivity
                }
            }
            return true
        } catch {
            // 토큰 한도 초과 감지 → 최소 context로 1회 재시도
            // ⚠️ 재시도 시 work rules 제거 — §12.1 activeRuleIDs 의무와 tradeoff.
            // 근거: (1) 초기 시도(full rules)가 토큰 한도로 실패 → 재시도 불가피
            //       (2) work rules는 텍스트 지시일 뿐, 도구 권한은 resolvedToolIDs로 별도 관리
            //       (3) 완전 실패보다 규칙 없는 실행이 나음 (langSuffix는 보존)
            if error.userFacingMessage.contains("토큰 한도") {
                print("[DOUGLAS] ⚠️ 토큰 한도 초과 감지 — persona만으로 재시도 (work rules 제거)")
                // 재시도: persona + langSuffix만 (work rules 제거 → 시스템 프롬프트 대폭 축소)
                let hasKoreanRule = agent.workRules.contains {
                    $0.name.contains("한국어") || $0.summary.contains("한국어")
                }
                let retryPrompt = agent.persona + (hasKoreanRule ? "\n\n[필수] 반드시 한국어로 응답하세요." : "")
                let previousWork = String(buffer.current.prefix(500))
                let previousSummary = previousWork.isEmpty ? "" : "\n\n[이전 시도 요약]\n\(previousWork)"
                let minimalMessages = [ConversationMessage.user("""
                    [작업 \(stepIndex + 1)/\(totalSteps)] \(step)\(previousSummary)

                    컨텍스트가 너무 큽니다. 이전 대화를 참고하지 않고, 위 단계 지시만으로 작업을 수행하세요.
                    """)]
                if let retryResponse = try? await ToolExecutor.smartSend(
                    provider: provider,
                    agent: agent,
                    systemPrompt: retryPrompt,
                    conversationMessages: minimalMessages,
                    context: context,
                    onToolActivity: { [weak self] activity, detail in
                        guard let self else { return }
                        Task { @MainActor in
                            let toolMsg = ChatMessage(
                                role: .assistant, content: activity,
                                agentName: agent.name, messageType: .toolActivity,
                                activityGroupID: progressGroupID, toolDetail: detail
                            )
                            self.appendMessage(toolMsg, to: roomID)
                        }
                    },
                    onStreamChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in
                            self.updateMessageContent(streamPlaceholderID, newContent: current, in: roomID)
                        }
                    }
                ) {
                    let cleanedRetry = expandTildePaths(stripHallucinatedAuthLines(stripTrailingOptions(retryResponse)))
                    updateMessageContent(streamPlaceholderID, newContent: cleanedRetry, in: roomID)
                    if let i = rooms.firstIndex(where: { $0.id == roomID }),
                       let mi = rooms[i].messages.firstIndex(where: { $0.id == streamPlaceholderID }) {
                        rooms[i].messages[mi].timestamp = Date()
                        if !(isLastStep || totalSteps == 1) {
                            rooms[i].messages[mi].messageType = .toolActivity
                        }
                    }
                    return true
                }
            }

            if speakingAgentIDByRoom[roomID] == agentID {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
            }
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "단계 실행 오류: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            return false
        }
    }

}
