import Foundation
import os.log

private let intakeLogger = Logger(subsystem: "com.douglas.app", category: "Intake")

// MARK: - 워크플로우 실행 (Phase 6 분리)

extension RoomManager {

    // MARK: - 규칙 기반 시스템 프롬프트

    /// 방의 활성 규칙 기반으로 에이전트 시스템 프롬프트 생성 (캐시 적용)
    func systemPrompt(for agent: Agent, roomID: UUID) -> String {
        let room = rooms.first(where: { $0.id == roomID })
        let activeRuleIDs = room?.workflowState.activeRuleIDs
        if let cached = systemPromptCache.get(agentID: agent.id, activeRuleIDs: activeRuleIDs) {
            return cached
        }
        // 플러그인 규칙 주입
        let pluginRules = pluginRulesProvider?(agent) ?? []
        var prompt = PromptCompositionService.compose(
            persona: agent.persona,
            workRules: agent.workRules,
            legacyRules: agent.workingRules,
            activeRuleIDs: activeRuleIDs,
            pluginRules: pluginRules
        )

        // WorkflowPosition 지시 주입
        if let position = room?.agentPositions[agent.id] {
            prompt += "\n\n[포지션] 이번 작업에서 당신의 포지션: **\(position.displayName)** (\(position.rawValue)). 이 포지션에 맞는 관점과 전문성으로 발언하세요."
        }

        systemPromptCache.set(prompt, agentID: agent.id, activeRuleIDs: activeRuleIDs)
        return prompt
    }

    // MARK: - 방 워크플로우

    /// 워크플로우 진입점: 항상 Intent 기반 Phase 워크플로우
    func startRoomWorkflow(roomID: UUID, task: String) async {
        // worktree 격리 (동일 projectPath 동시 사용 시)
        await createWorktreeIfNeeded(roomID: roomID)

        // intent 미설정 → quickClassify 시도 (nil이면 executeIntentPhase에서 사용자 선택)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].classifyIntent(
                IntentClassifier.quickClassify(task),
                modifiers: IntentClassifier.extractModifiers(from: task)
            )
            // classifyIntent: nil intent 무시, 이미 분류됐으면 무시
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

    // MARK: - WorkflowError 처리

    /// 구조화된 워크플로우 에러 → 방 상태 전이 + 사용자 메시지
    func handleWorkflowError(_ error: WorkflowError, roomID: UUID) {
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].fail()
        }
        let msg = ChatMessage(
            role: .system,
            content: error.userFacingMessage,
            messageType: .error
        )
        appendMessage(msg, to: roomID)
        syncAgentStatuses()
        scheduleSave()
    }

    // MARK: - Phase 워크플로우 (새 7단계)

    /// 새 워크플로우: intent.requiredPhases 동적 순회
    /// intent 단계에서 LLM 재분류 후 남은 단계가 자동으로 재계산됨
    private func executePhaseWorkflow(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        rooms[idx].transitionTo(.planning)
        syncAgentStatuses()

        var workflowStart = Date()
        var completedPhases: Set<WorkflowPhase> = []
        // 파일만 업로드된 경우 understand 단계에서 사용자 입력으로 task가 갱신됨
        var resolvedTask = task

        while true {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive else { break }

            // 타임아웃 체크 (PhaseRouter 위임)
            if PhaseRouter.isTimedOut(since: workflowStart) {
                handleWorkflowError(.workflowTimeout, roomID: roomID)
                return
            }

            let currentIntent = currentRoom.workflowState.intent ?? .quickAnswer
            // 다음 미완료 phase 결정 (PhaseRouter 위임)
            guard let nextPhase = PhaseRouter.nextPhase(
                intent: currentIntent,
                modifiers: currentRoom.workflowState.modifiers,
                completedPhases: completedPhases
            ) else { break }

            // 현재 단계 기록 + 전이 감사 기록 (내부 상태만, UI 메시지 없음)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].workflowState.advanceToPhase(nextPhase)
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
                        rooms[i].workflowState.setNeedsPlan(planNeeded)
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
                rooms[i].workflowState.completePhase(nextPhase)
                // 페이즈 완료 시 요약 저장 — 다음 페이즈에서 전체 히스토리 대신 참조 (토큰 최적화)
                let summary = PhaseContextSummarizer.summarize(phase: nextPhase, room: rooms[i])
                if !summary.isEmpty {
                    rooms[i].workflowState.recordPhaseSummary(phase: nextPhase, summary: summary)
                }
            }
            workflowStart = Date() // 단계 완료 후 타이머 리셋 (사용자 대기 시간으로 인한 타임아웃 방지)
        }

        // 워크플로우 완료
        // Task.isCancelled (completeRoom 등 외부 완료) 시 이미 completed 상태이므로 중복 처리 방지
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed && rooms[i].status != .completed {
            rooms[i].complete()
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
    func executeIntentPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // intent 미설정 → quickClassify 재시도 → LLM 폴백 (선택 UI 없이 자동 결정)
        if rooms[idx].workflowState.intent == nil {
            // 1) quickClassify 시도 (명확한 경우 즉시 결정)
            if let quick = IntentClassifier.quickClassify(task) {
                rooms[idx].workflowState.setIntent(quick)
                scheduleSave()
            } else {
                // 2) LLM 분류 폴백 — 자동 적용, 사용자 선택 없음
                guard let firstAgentID = rooms[idx].assignedAgentIDs.first,
                      let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
                      let provider = providerManager?.provider(named: agent.providerName) else {
                    rooms[idx].workflowState.setIntent(.task)
                    return
                }

                let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
                let classified = await IntentClassifier.classifyWithLLM(
                    task: task,
                    provider: provider,
                    model: lightModel
                )
                rooms[idx].workflowState.setIntent(classified)
                scheduleSave()
            }
        }

        // 초기 메시지에서 문서 요청 감지 → autoDocOutput 플래그 설정
        if let resolvedIdx = rooms.firstIndex(where: { $0.id == roomID }) {
            let currentTask = task
            if let docResult = DocumentRequestDetector.quickDetect(currentTask), docResult.isDocumentRequest {
                rooms[resolvedIdx].workflowState.setAutoDocOutput(true, documentType: docResult.suggestedDocType ?? .freeform)
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
    func executeIntakePhase(roomID: UUID, task: String) async {
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

            // Jira 자동 할당: 첫 번째 티켓에 내 계정을 작업자로 설정
            if let firstKey = jiraKeys.first {
                Task {
                    var config = JiraConfig.shared
                    guard config.isConfigured else { return }
                    do {
                        let accountId = try await config.fetchMyAccountId()
                        JiraConfig.shared = config
                        // PUT /rest/api/3/issue/{key}/assignee
                        let body = try JSONSerialization.data(withJSONObject: ["accountId": accountId])
                        let url = URL(string: "\(config.baseURL)/rest/api/3/issue/\(firstKey)/assignee")!
                        var req = URLRequest(url: url)
                        req.httpMethod = "PUT"
                        req.httpBody = body
                        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                        if let auth = config.authHeader() { req.addValue(auth, forHTTPHeaderField: "Authorization") }
                        _ = try? await URLSession.shared.data(for: req)
                        intakeLogger.info("Jira \(firstKey, privacy: .public) 작업자 자동 할당 완료")
                    } catch {
                        intakeLogger.warning("Jira 자동 할당 실패: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
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
        rooms[idx].clarifyContext.setIntakeData(intakeData)

        // 4) 플레이북 로드 (내부 데이터만, UI 메시지 없음)
        if let projectPath = rooms[idx].primaryProjectPath {
            if let playbook = PlaybookManager.load(from: projectPath) {
                rooms[idx].clarifyContext.setPlaybook(playbook)
            }
        }

        // 5) 업무 규칙 매칭 (에이전트 workRules 기반)
        if let firstAgentID = rooms[idx].assignedAgentIDs.first,
           let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
           !agent.workRules.isEmpty {
            let activeIDs = WorkRuleMatcher.match(rules: agent.workRules, taskText: task)
            rooms[idx].workflowState.setActiveRuleIDs(activeIDs)
        }

        scheduleSave()
    }

    /// Clarify 단계: 복명복창 — DOUGLAS가 이해한 내용을 요약하고 사용자 컨펌까지 무한 루프
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
    func requestPlan(roomID: UUID, task: String, previousPlan: RoomPlan? = nil, feedback: String? = nil, designOutput: String? = nil) async -> RoomPlan? {
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
                if let rb = room.discussion.researchBriefing {
                    let head = String(fullLog.prefix(1000))
                    let tail = String(fullLog.suffix(1000))
                    briefingContext = rb.asContextString() + "\n\n[조사 원문 발췌]\n…\(head)\n…(중략)…\n\(tail)…"
                } else if let briefing = room.discussion.briefing {
                    // briefing 요약 + 원문 핵심 부분 (앞뒤 각 1000자)
                    let head = String(fullLog.prefix(1000))
                    let tail = String(fullLog.suffix(1000))
                    briefingContext = briefing.asContextString() + "\n\n[토론 원문 발췌]\n…\(head)\n…(중략)…\n\(tail)…"
                } else {
                    briefingContext = String(briefingContext.prefix(4000)) + "…(이하 생략)"
                }
            }
        } else if let rb = room.discussion.researchBriefing {
            briefingContext = rb.asContextString()
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
            let workflowErr = WorkflowError.llmFailure(agentID: firstAgentID, detail: error.userFacingMessage)
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "계획 수립 실패: \(workflowErr.userFacingMessage)",
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
    func executeRoomWork(roomID: UUID, task: String) async {
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
                rooms[i].complete()
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

        // 2. 브리핑 (2000자 캡) — research/discussion 구분
        if let rb = room?.discussion.researchBriefing {
            let ctx = rb.asContextString()
            let capped = ctx.count > 2000 ? String(ctx.prefix(2000)) + "…" : ctx
            history.append(ConversationMessage.user("조사 브리핑:\n\(capped)"))
        } else if let briefing = room?.discussion.briefing {
            let ctx = briefing.asContextString()
            let capped = ctx.count > 2000 ? String(ctx.prefix(2000)) + "…" : ctx
            history.append(ConversationMessage.user("작업 브리핑:\n\(capped)"))
        }

        // 2.5. 페이즈 요약 컨텍스트 — 이전 페이즈 산출물 참조 (토큰 최적화)
        if let room = room {
            let phaseContext = PhaseContextSummarizer.buildContextForPhase(.build, room: room)
            if !phaseContext.isEmpty {
                history.append(ConversationMessage.user("[이전 페이즈 요약]\n\(phaseContext)"))
            }
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
