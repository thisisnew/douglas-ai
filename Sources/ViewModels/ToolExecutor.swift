import Foundation

/// 도구 호출 루프 실행 + smartSend 유틸리티
enum ToolExecutor {
    static let maxIterations = 10

    /// 테스트에서 교체 가능한 URLSession (web_fetch용)
    /// @TaskLocal로 병렬 테스트 간 세션 충돌 방지.
    @TaskLocal static var urlSession: URLSession = .shared

    /// 테스트에서 mock URLSession을 태스크 격리 방식으로 주입
    static func withSession(
        _ session: URLSession,
        body: () async throws -> Void
    ) async rethrows {
        try await $urlSession.withValue(session, operation: body)
    }

    /// 앱 tool ID → Claude Code CLI tool name 매핑
    private static func cliToolName(for toolID: String) -> String? {
        switch toolID {
        case "web_search":  return "WebSearch"
        case "web_fetch":   return "WebFetch"
        case "file_read":   return "Read"
        case "file_write":  return "Write"
        case "shell_exec":  return "Bash"
        case "code_search": return "Grep"
        default:            return nil
        }
    }

    /// 도구 사용 가능한 경우 도구 루프 실행, 아니면 기존 sendMessage 폴백
    static func smartSend(
        provider: AIProvider,
        agent: Agent,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        context: ToolExecutionContext = .empty,
        onToolActivity: ((String, ToolActivityDetail?) -> Void)? = nil,
        onStreamChunk: (@Sendable (String) -> Void)? = nil,
        useTools: Bool = true,
        allowedToolIDs: [String]? = nil
    ) async throws -> String {
        let toolIDs = allowedToolIDs ?? agent.resolvedToolIDs

        // 도구 없거나 프로바이더가 도구 미지원 또는 명시적 비활성화 → 기존 경로
        guard useTools, !toolIDs.isEmpty, provider.supportsToolCalling else {
            let result: String
            if let claudeProvider = provider as? ClaudeCodeProvider {
                // ClaudeCodeProvider: 도구 활동 + 텍스트 스트리밍 동시 지원
                result = try await claudeProvider.sendMessage(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: messages,
                    workingDirectory: context.projectPaths.first,
                    onToolActivity: onToolActivity,
                    onTextChunk: onStreamChunk
                )
            } else if let onStreamChunk, provider.supportsStreaming {
                result = try await provider.sendMessageStreaming(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: messages,
                    onChunk: onStreamChunk
                )
            } else {
                result = try await provider.sendMessage(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: messages
                )
                if let onStreamChunk { onStreamChunk(result) }
            }
            return result
        }

        // 단순 메시지를 ConversationMessage로 변환
        let convMessages = messages.map { msg -> ConversationMessage in
            switch msg.role {
            case "assistant": return .assistant(msg.content)
            case "system":    return .system(msg.content)
            default:          return .user(msg.content)
            }
        }
        let tools = ToolRegistry.tools(for: toolIDs)

        return try await executeWithTools(
            provider: provider,
            model: agent.modelName,
            systemPrompt: systemPrompt,
            initialMessages: convMessages,
            tools: tools,
            context: context,
            onToolActivity: onToolActivity
        )
    }

    /// ConversationMessage 배열을 직접 받는 smartSend (이미지 첨부 지원)
    static func smartSend(
        provider: AIProvider,
        agent: Agent,
        systemPrompt: String,
        conversationMessages: [ConversationMessage],
        context: ToolExecutionContext = .empty,
        onToolActivity: ((String, ToolActivityDetail?) -> Void)? = nil,
        onStreamChunk: (@Sendable (String) -> Void)? = nil,
        useTools: Bool = true,
        allowedToolIDs: [String]? = nil
    ) async throws -> String {
        let toolIDs = allowedToolIDs ?? agent.resolvedToolIDs

        // 이미지가 있으면 sendMessageWithTools 경로 사용 (Vision 지원)
        let hasAttachments = conversationMessages.contains { $0.attachments != nil && !($0.attachments?.isEmpty ?? true) }

        guard hasAttachments || (useTools && !toolIDs.isEmpty && provider.supportsToolCalling) else {
            // 이미지도 도구도 없으면 기존 sendMessage
            let simple = conversationMessages.compactMap { msg -> (role: String, content: String)? in
                guard let content = msg.content else { return nil }
                return (role: msg.role, content: content)
            }
            let result: String
            // ClaudeCodeProvider: 도구 활동 + 텍스트 스트리밍 동시 지원
            if let claudeProvider = provider as? ClaudeCodeProvider, let allowedToolIDs {
                let cliTools = allowedToolIDs.compactMap { Self.cliToolName(for: $0) }
                if !cliTools.isEmpty {
                    result = try await claudeProvider.sendMessageStreamingWithTools(
                        model: agent.modelName,
                        systemPrompt: systemPrompt,
                        messages: simple,
                        allowedTools: cliTools,
                        onToolActivity: onToolActivity,
                        onChunk: onStreamChunk ?? { _ in }
                    )
                } else {
                    result = try await claudeProvider.sendMessage(
                        model: agent.modelName,
                        systemPrompt: systemPrompt,
                        messages: simple,
                        workingDirectory: context.projectPaths.first,
                        onToolActivity: onToolActivity,
                        onTextChunk: onStreamChunk
                    )
                }
            } else if let claudeProvider = provider as? ClaudeCodeProvider {
                result = try await claudeProvider.sendMessage(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: simple,
                    workingDirectory: context.projectPaths.first,
                    onToolActivity: onToolActivity,
                    onTextChunk: onStreamChunk
                )
            } else if let onStreamChunk, provider.supportsStreaming {
                result = try await provider.sendMessageStreaming(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: simple,
                    onChunk: onStreamChunk
                )
            } else {
                result = try await provider.sendMessage(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: simple
                )
                if let onStreamChunk { onStreamChunk(result) }
            }
            return result
        }

        let tools = ToolRegistry.tools(for: toolIDs)

        return try await executeWithTools(
            provider: provider,
            model: agent.modelName,
            systemPrompt: systemPrompt,
            initialMessages: conversationMessages,
            tools: tools,
            context: context,
            onToolActivity: onToolActivity
        )
    }

    /// 도구 호출 루프: 모델이 도구를 요청하면 실행하고 결과를 반환, 텍스트 응답까지 반복
    static func executeWithTools(
        provider: AIProvider,
        model: String,
        systemPrompt: String,
        initialMessages: [ConversationMessage],
        tools: [AgentTool],
        context: ToolExecutionContext = .empty,
        onToolActivity: ((String, ToolActivityDetail?) -> Void)? = nil
    ) async throws -> String {
        var messages = initialMessages

        for _ in 0..<maxIterations {
            // 도구 라운드 사이에서 사용자 메시지 실시간 반영
            if let fetch = context.fetchPendingUserMessages {
                let newMsgs = await fetch()
                if !newMsgs.isEmpty {
                    messages.append(contentsOf: newMsgs)
                }
            }

            let response = try await provider.sendMessageWithTools(
                model: model,
                systemPrompt: systemPrompt,
                messages: messages,
                tools: tools
            )

            switch response {
            case .text(let finalText):
                return finalText

            case .toolCalls(let calls):
                messages.append(.assistantToolCalls(calls, text: nil))
                // 도구 호출 시작 활동 로깅
                for call in calls {
                    let detail = buildCallStartDetail(call: call)
                    onToolActivity?(detail.displayName + (detail.subject.map { " → \($0)" } ?? ""), detail)
                }
                let results = await executeToolCallsInParallel(calls, context: context)
                for result in results {
                    let call = calls.first(where: { $0.id == result.callID })
                    if result.isError {
                        let detail = buildActivityDetail(call: call, result: result)
                        let toolLabel = call?.toolName ?? result.callID
                        onToolActivity?("도구 오류: \(toolLabel)", detail)
                    }
                    messages.append(.toolResult(callID: result.callID, content: result.content, isError: result.isError))
                }

            case .mixed(let text, let calls):
                messages.append(.assistantToolCalls(calls, text: text))
                // 도구 호출 시작 활동 로깅
                for call in calls {
                    let detail = buildCallStartDetail(call: call)
                    onToolActivity?(detail.displayName + (detail.subject.map { " → \($0)" } ?? ""), detail)
                }
                let results = await executeToolCallsInParallel(calls, context: context)
                for result in results {
                    let call = calls.first(where: { $0.id == result.callID })
                    if result.isError {
                        let detail = buildActivityDetail(call: call, result: result)
                        let toolLabel = call?.toolName ?? result.callID
                        onToolActivity?("도구 오류: \(toolLabel)", detail)
                    }
                    messages.append(.toolResult(callID: result.callID, content: result.content, isError: result.isError))
                }
            }
        }

        throw AIProviderError.apiError("도구 호출 반복 횟수 초과 (최대 \(maxIterations)회)")
    }

    /// 도구 호출 병렬 실행: 결과를 원래 호출 순서대로 반환
    private static func executeToolCallsInParallel(
        _ calls: [ToolCall],
        context: ToolExecutionContext
    ) async -> [ToolResult] {
        await withTaskGroup(of: (Int, ToolResult).self, returning: [ToolResult].self) { group in
            for (idx, call) in calls.enumerated() {
                group.addTask {
                    let result = await executeSingleTool(call, context: context)
                    return (idx, result)
                }
            }
            var collected: [(Int, ToolResult)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: - 경로 검증

    /// 파일 접근이 허용된 경로인지 확인. $HOME, /tmp, 시스템 임시 디렉토리, projectPaths 허용.
    static func isPathAllowed(_ path: String, projectPaths: [String] = []) -> Bool {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath).resolvingSymlinksInPath()
        let resolved = url.path

        let homePath = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        let tempDir = NSTemporaryDirectory()
        var allowedPrefixes = [homePath, "/tmp", "/private/tmp", tempDir, "/var/folders"]
        for proj in projectPaths {
            let normalizedProj = URL(fileURLWithPath: proj).resolvingSymlinksInPath().path
            allowedPrefixes.append(normalizedProj)
        }
        let blockedPrefixes = [
            "\(homePath)/Library/Keychains",
            "\(homePath)/.ssh",
            "\(homePath)/.gnupg"
        ]

        // 차단 목록 먼저 확인 (디렉토리 단위 매칭)
        for blocked in blockedPrefixes {
            let prefix = blocked.hasSuffix("/") ? blocked : blocked + "/"
            if resolved == blocked || resolved.hasPrefix(prefix) { return false }
        }

        // 허용 목록 확인 (디렉토리 단위 매칭)
        for allowed in allowedPrefixes {
            let prefix = allowed.hasSuffix("/") ? allowed : allowed + "/"
            if resolved == allowed || resolved.hasPrefix(prefix) { return true }
        }

        return false
    }

    /// 상대 경로를 첫 번째 projectPath 기준으로 절대 경로로 변환
    static func resolvePath(_ path: String, projectPaths: [String]) -> String {
        if path.hasPrefix("/") || path.hasPrefix("~") { return path }
        guard let base = projectPaths.first else { return path }
        return (base as NSString).appendingPathComponent(path)
    }

    // MARK: - 개별 도구 실행

    static func executeSingleTool(_ call: ToolCall, context: ToolExecutionContext = .empty) async -> ToolResult {
        // 플러그인 인터셉트 훅
        let argStrings = call.arguments.mapValues { arg -> String in
            switch arg {
            case .string(let s): return s
            case .integer(let i): return "\(i)"
            case .boolean(let b): return "\(b)"
            case .array(let a): return a.joined(separator: ", ")
            }
        }
        let intercept = await context.interceptTool(call.toolName, argStrings)
        switch intercept {
        case .override(let content, let isError):
            return ToolResult(callID: call.id, content: content, isError: isError)
        case .block(let reason):
            return ToolResult(callID: call.id, content: "도구 차단됨: \(reason)", isError: true)
        case .passthrough:
            break
        }

        // Layer 1: 에이전트 권한 검사 (actionPermissions가 비어있으면 모두 허용 — 역호환)
        if !context.agentPermissions.isEmpty,
           let tool = ToolRegistry.allTools.first(where: { $0.id == call.toolName }),
           let requiredScope = tool.requiredActionScope,
           !context.agentPermissions.contains(requiredScope) {
            return ToolResult(
                callID: call.id,
                content: "권한 부족: \(context.currentAgentName ?? "에이전트")에게 '\(requiredScope.rawValue)' 권한이 없습니다.",
                isError: true
            )
        }

        // Layer 2 (제거됨): restrictions는 actionPermissions로 통합 — workModes에서 자동 추론

        // Layer 3: Plan C — high-risk 도구 지연 실행 (Build 단계에서 external 도구 defer)
        if context.deferHighRiskTools,
           let tool = ToolRegistry.allTools.first(where: { $0.id == call.toolName }),
           tool.risk == .external {
            let deferred = DeferredAction(
                id: UUID(),
                toolName: call.toolName,
                arguments: argStrings.mapValues { ToolArgumentValue.string($0) },
                description: "\(call.toolName): \(argStrings.values.joined(separator: ", ").prefix(100))",
                riskLevel: .high,
                previewContent: argStrings.map { "\($0.key): \($0.value)" }.joined(separator: "\n"),
                status: .pending
            )
            context.collectDeferred(deferred)
            return ToolResult(
                callID: call.id,
                content: "⏸ 이 작업은 high-risk로 분류되어 Deliver 단계에서 승인 후 실행됩니다: \(call.toolName)",
                isError: false
            )
        }

        // 도구 실행 시작 이벤트
        context.dispatchPluginEvent(.toolExecutionStarted(
            roomID: context.roomID,
            toolName: call.toolName,
            arguments: argStrings
        ))

        let result: ToolResult
        switch call.toolName {
        case "file_read":
            result = await executeFileRead(call, context: context)
        case "file_write":
            result = await executeFileWrite(call, context: context)
        case "shell_exec":
            result = await executeShellExec(call, context: context)
        case "web_search":
            result = await executeWebSearch(call)
        case "web_fetch":
            result = await executeWebFetch(call)
        case "invite_agent":
            result = await executeInviteAgent(call, context: context)
        case "list_agents":
            result = await executeListAgents(call, context: context)
        case "suggest_agent_creation":
            result = await executeSuggestAgentCreation(call, context: context)
        case "jira_create_subtask":
            result = await executeJiraCreateSubtask(call)
        case "jira_update_status":
            result = await executeJiraUpdateStatus(call)
        case "jira_add_comment":
            result = await executeJiraAddComment(call)
        case "ask_user":
            result = await executeAskUser(call, context: context)
        case "code_search":
            result = await executeCodeSearch(call, context: context)
        case "code_symbols":
            result = await executeCodeSymbols(call, context: context)
        case "code_diagnostics":
            result = await executeCodeDiagnostics(call, context: context)
        case "code_outline":
            result = await executeCodeOutline(call, context: context)
        default:
            result = ToolResult(callID: call.id, content: "알 수 없는 도구: \(call.toolName)", isError: true)
        }

        // 도구 실행 완료 이벤트
        context.dispatchPluginEvent(.toolExecutionCompleted(
            roomID: context.roomID,
            toolName: call.toolName,
            result: String(result.content.prefix(500)),
            isError: result.isError
        ))

        // 파일 I/O 이벤트
        switch call.toolName {
        case "file_write":
            if let path = call.arguments["path"]?.stringValue {
                context.dispatchPluginEvent(.fileWritten(path: path, agentName: context.currentAgentName))
            }
        case "file_read":
            if let path = call.arguments["path"]?.stringValue {
                context.dispatchPluginEvent(.fileRead(path: path, agentName: context.currentAgentName))
            }
        default:
            break
        }

        return result
    }

    // MARK: - invite_agent

    private static func executeInviteAgent(_ call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        guard context.roomID != nil else {
            return ToolResult(callID: call.id, content: "이 도구는 방 안에서만 사용할 수 있습니다.", isError: true)
        }
        guard let agentName = call.arguments["agent_name"]?.stringValue else {
            return ToolResult(callID: call.id, content: "agent_name 파라미터가 필요합니다.", isError: true)
        }
        guard let agentID = context.agentsByName[agentName] else {
            let available = context.agentsByName.keys.sorted().joined(separator: ", ")
            return ToolResult(
                callID: call.id,
                content: "'\(agentName)' 에이전트를 찾을 수 없습니다. 사용 가능한 에이전트: \(available.isEmpty ? "(없음)" : available)",
                isError: true
            )
        }

        let success = await context.inviteAgent(agentID)
        if success {
            let reason = call.arguments["reason"]?.stringValue ?? ""
            return ToolResult(
                callID: call.id,
                content: "'\(agentName)' 에이전트를 방에 초대했습니다.\(reason.isEmpty ? "" : " 사유: \(reason)")",
                isError: false
            )
        } else {
            return ToolResult(callID: call.id, content: "에이전트 초대에 실패했습니다.", isError: true)
        }
    }

    // MARK: - list_agents

    private static func executeListAgents(_ call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        if context.agentListString.isEmpty {
            return ToolResult(callID: call.id, content: "사용 가능한 에이전트가 없습니다.", isError: false)
        }
        return ToolResult(callID: call.id, content: "사용 가능한 에이전트:\n\(context.agentListString)", isError: false)
    }

    // MARK: - suggest_agent_creation

    private static func executeSuggestAgentCreation(_ call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        guard context.roomID != nil else {
            return ToolResult(callID: call.id, content: "이 도구는 방 안에서만 사용할 수 있습니다.", isError: true)
        }
        guard let name = call.arguments["name"]?.stringValue, !name.isEmpty else {
            return ToolResult(callID: call.id, content: "name 파라미터가 필요합니다.", isError: true)
        }
        guard let persona = call.arguments["persona"]?.stringValue, !persona.isEmpty else {
            return ToolResult(callID: call.id, content: "persona 파라미터가 필요합니다.", isError: true)
        }

        // 이미 존재하는 에이전트 이름 체크
        if context.agentsByName[name] != nil {
            return ToolResult(callID: call.id, content: "'\(name)' 이름의 에이전트가 이미 존재합니다. invite_agent를 사용하세요.", isError: true)
        }

        let suggestion = RoomAgentSuggestion(
            name: name,
            persona: persona,
            recommendedPreset: call.arguments["recommended_preset"]?.stringValue,
            recommendedProvider: call.arguments["recommended_provider"]?.stringValue,
            recommendedModel: call.arguments["recommended_model"]?.stringValue,
            reason: call.arguments["reason"]?.stringValue ?? "",
            suggestedBy: context.currentAgentName ?? "알 수 없음"
        )

        let success = await context.suggestAgentCreation(suggestion)
        if success {
            return ToolResult(
                callID: call.id,
                content: "'\(name)' 에이전트 생성을 제안했습니다. 사용자 승인을 기다립니다.",
                isError: false
            )
        } else {
            return ToolResult(callID: call.id, content: "에이전트 생성 제안에 실패했습니다.", isError: true)
        }
    }

    // MARK: - file_read

    private static func executeFileRead(_ call: ToolCall, context: ToolExecutionContext = .empty) async -> ToolResult {
        guard let rawPath = call.arguments["path"]?.stringValue else {
            return ToolResult(callID: call.id, content: "path 파라미터가 필요합니다.", isError: true)
        }
        let path = resolvePath(rawPath, projectPaths: context.projectPaths)
        guard isPathAllowed(path, projectPaths: context.projectPaths) else {
            return ToolResult(callID: call.id, content: "접근이 허용되지 않은 경로입니다: \(path)", isError: true)
        }
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            // 큰 파일은 잘라서 반환
            let maxLen = 50_000
            if content.count > maxLen {
                return ToolResult(
                    callID: call.id,
                    content: String(content.prefix(maxLen)) + "\n\n... (파일이 \(content.count)자로 잘렸습니다)",
                    isError: false
                )
            }
            return ToolResult(callID: call.id, content: content, isError: false)
        } catch {
            return ToolResult(callID: call.id, content: "파일 읽기 실패: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - file_write

    private static func executeFileWrite(_ call: ToolCall, context: ToolExecutionContext = .empty) async -> ToolResult {
        guard let rawPath = call.arguments["path"]?.stringValue else {
            return ToolResult(callID: call.id, content: "path 파라미터가 필요합니다.", isError: true)
        }
        let path = resolvePath(rawPath, projectPaths: context.projectPaths)
        guard isPathAllowed(path, projectPaths: context.projectPaths) else {
            return ToolResult(callID: call.id, content: "접근이 허용되지 않은 경로입니다: \(path)", isError: true)
        }
        guard let content = call.arguments["content"]?.stringValue else {
            return ToolResult(callID: call.id, content: "content 파라미터가 필요합니다.", isError: true)
        }

        // 파일 쓰기 승인: 자동 허용 (모든 모델 호환)
        // 충돌 추적은 FileWriteTracker가 별도로 수행

        do {
            // 상위 디렉토리 생성
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try content.write(toFile: path, atomically: true, encoding: .utf8)

            // 파일 쓰기 충돌 추적
            var conflictWarning = ""
            if let tracker = context.fileWriteTracker, let agentID = context.currentAgentID {
                let hasConflict = await tracker.recordWrite(path: path, agentID: agentID)
                if hasConflict {
                    conflictWarning = "\n⚠️ 다른 에이전트가 이미 이 파일을 수정했습니다. 충돌 가능성 있음."
                }
            }

            return ToolResult(callID: call.id, content: "파일 저장 완료: \(path) (\(content.count)자)\(conflictWarning)", isError: false)
        } catch {
            return ToolResult(callID: call.id, content: "파일 쓰기 실패: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - web_search

    private static func executeWebSearch(_ call: ToolCall) async -> ToolResult {
        guard let query = call.arguments["query"]?.stringValue, !query.isEmpty else {
            return ToolResult(callID: call.id, content: "query 파라미터가 필요합니다.", isError: true)
        }

        // DuckDuckGo HTML 검색 (API 키 불필요)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return ToolResult(callID: call.id, content: "검색 쿼리 인코딩 실패", isError: true)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await urlSession.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            guard (200..<400).contains(httpResponse?.statusCode ?? 0) else {
                return ToolResult(callID: call.id, content: "검색 요청 실패 (HTTP \(httpResponse?.statusCode ?? 0))", isError: true)
            }

            guard let html = String(data: data, encoding: .utf8) else {
                return ToolResult(callID: call.id, content: "응답 디코딩 실패", isError: true)
            }

            let results = parseDuckDuckGoResults(html)
            if results.isEmpty {
                return ToolResult(callID: call.id, content: "검색 결과가 없습니다: \(query)", isError: false)
            }

            let formatted = results.prefix(8).enumerated().map { i, r in
                "\(i + 1). \(r.title)\n   \(r.url)\n   \(r.snippet)"
            }.joined(separator: "\n\n")

            return ToolResult(callID: call.id, content: "검색 결과 (\(query)):\n\n\(formatted)", isError: false)
        } catch {
            return ToolResult(callID: call.id, content: "검색 오류: \(error.localizedDescription)", isError: true)
        }
    }

    private static func parseDuckDuckGoResults(_ html: String) -> [(title: String, url: String, snippet: String)] {
        var results: [(title: String, url: String, snippet: String)] = []

        // DuckDuckGo HTML 결과에서 result__a (제목+링크) + result__snippet (요약) 추출
        let blocks = html.components(separatedBy: "class=\"result__body")
        for block in blocks.dropFirst() {
            // 제목 + URL
            var title = ""
            var url = ""
            if let aStart = block.range(of: "class=\"result__a\""),
               let hrefStart = block[..<aStart.lowerBound].range(of: "href=\"", options: .backwards) {
                let hrefContent = block[hrefStart.upperBound...]
                if let hrefEnd = hrefContent.range(of: "\"") {
                    let rawURL = String(hrefContent[..<hrefEnd.lowerBound])
                    // DuckDuckGo 리다이렉트 URL에서 실제 URL 추출
                    if let udParam = rawURL.range(of: "uddg=") {
                        let encoded = String(rawURL[udParam.upperBound...]).components(separatedBy: "&").first ?? ""
                        url = encoded.removingPercentEncoding ?? encoded
                    } else {
                        url = rawURL
                    }
                }
                // 제목: <a> 태그 내부 텍스트
                if let tagEnd = block[aStart.upperBound...].range(of: ">"),
                   let closeTag = block[tagEnd.upperBound...].range(of: "</a>") {
                    title = String(block[tagEnd.upperBound..<closeTag.lowerBound])
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // 스니펫
            var snippet = ""
            if let snippetStart = block.range(of: "class=\"result__snippet\"") {
                if let tagEnd = block[snippetStart.upperBound...].range(of: ">"),
                   let closeTag = block[tagEnd.upperBound...].range(of: "</") {
                    snippet = String(block[tagEnd.upperBound..<closeTag.lowerBound])
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if !title.isEmpty && !url.isEmpty {
                results.append((title: title, url: url, snippet: snippet))
            }
        }
        return results
    }

    // MARK: - web_fetch

    private static func executeWebFetch(_ call: ToolCall) async -> ToolResult {
        guard let urlString = call.arguments["url"]?.stringValue,
              let url = URL(string: urlString) else {
            return ToolResult(callID: call.id, content: "유효한 url 파라미터가 필요합니다.", isError: true)
        }

        let method = call.arguments["method"]?.stringValue?.uppercased() ?? "GET"
        let body = call.arguments["body"]?.stringValue

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        // Jira URL 감지 → 자동 인증 + API URL 변환
        let jiraConfig = JiraConfig.shared
        if jiraConfig.isConfigured && jiraConfig.isJiraURL(urlString) {
            // 브라우저 URL → REST API URL 변환
            let apiURLString = jiraConfig.apiURL(from: urlString)
            if apiURLString != urlString, let apiURL = URL(string: apiURLString) {
                request.url = apiURL
            }
            if let auth = jiraConfig.authHeader() {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }

        if let body, method == "POST" {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            guard (200..<400).contains(statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "(응답 없음)"
                return ToolResult(
                    callID: call.id,
                    content: "HTTP \(statusCode) 오류\n\(String(body.prefix(2000)))",
                    isError: true
                )
            }

            guard var text = String(data: data, encoding: .utf8) else {
                return ToolResult(callID: call.id, content: "응답을 텍스트로 변환할 수 없습니다.", isError: true)
            }

            // Jira JSON 응답이면 읽기 쉬운 포맷으로 변환
            if jiraConfig.isConfigured && jiraConfig.isJiraURL(urlString),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["fields"] != nil {
                text = formatJiraIssue(json)
            }

            // 크기 제한
            let maxLen = 50_000
            if text.count > maxLen {
                text = String(text.prefix(maxLen)) + "\n\n... (응답이 \(text.count)자로 잘렸습니다)"
            }

            return ToolResult(callID: call.id, content: text, isError: false)
        } catch {
            return ToolResult(callID: call.id, content: "요청 실패: \(error.localizedDescription)", isError: true)
        }
    }

    /// Jira 이슈 JSON을 읽기 쉬운 텍스트로 변환
    private static func formatJiraIssue(_ json: [String: Any]) -> String {
        let key = json["key"] as? String ?? "?"
        let fields = json["fields"] as? [String: Any] ?? [:]

        let summary = fields["summary"] as? String ?? "(제목 없음)"
        let status = (fields["status"] as? [String: Any])?["name"] as? String ?? "?"
        let assignee = (fields["assignee"] as? [String: Any])?["displayName"] as? String ?? "미배정"
        let priority = (fields["priority"] as? [String: Any])?["name"] as? String ?? "?"
        let issueType = (fields["issuetype"] as? [String: Any])?["name"] as? String ?? "?"

        // 설명 (Atlassian Document Format → 텍스트 추출)
        var descriptionText = ""
        if let description = fields["description"] as? [String: Any] {
            descriptionText = extractADFText(description)
        } else if let desc = fields["description"] as? String {
            descriptionText = desc
        }

        // 댓글
        var commentLines: [String] = []
        if let commentObj = fields["comment"] as? [String: Any],
           let comments = commentObj["comments"] as? [[String: Any]] {
            for comment in comments.suffix(5) {
                let author = (comment["author"] as? [String: Any])?["displayName"] as? String ?? "?"
                let created = (comment["created"] as? String)?.prefix(10) ?? "?"
                let body: String
                if let adf = comment["body"] as? [String: Any] {
                    body = extractADFText(adf)
                } else {
                    body = (comment["body"] as? String) ?? ""
                }
                commentLines.append("- \(author) (\(created)): \(body.prefix(300))")
            }
        }

        var result = """
        [\(key)] \(summary)
        유형: \(issueType) | 상태: \(status) | 담당자: \(assignee) | 우선순위: \(priority)
        """

        if !descriptionText.isEmpty {
            result += "\n---\n설명:\n\(descriptionText)"
        }

        if !commentLines.isEmpty {
            result += "\n---\n댓글 (\(commentLines.count)개):\n\(commentLines.joined(separator: "\n"))"
        }

        return result
    }

    /// Atlassian Document Format (ADF) JSON에서 텍스트 추출
    private static func extractADFText(_ adf: [String: Any]) -> String {
        var texts: [String] = []
        if let content = adf["content"] as? [[String: Any]] {
            for block in content {
                if let innerContent = block["content"] as? [[String: Any]] {
                    let line = innerContent.compactMap { node -> String? in
                        if node["type"] as? String == "text" {
                            return node["text"] as? String
                        }
                        // 재귀: 인라인 노드 안의 텍스트
                        if let nested = node["content"] as? [[String: Any]] {
                            return nested.compactMap { $0["text"] as? String }.joined()
                        }
                        return nil
                    }.joined()
                    if !line.isEmpty { texts.append(line) }
                } else if block["type"] as? String == "text",
                          let text = block["text"] as? String {
                    texts.append(text)
                }
            }
        }
        return texts.joined(separator: "\n")
    }

    // MARK: - Jira 도구 공통 헬퍼

    /// Jira REST API 요청 생성 + 인증 헤더 + JSON 콘텐츠 타입
    private static func makeJiraRequest(path: String, method: String = "GET", body: Data? = nil) -> (URLRequest, JiraConfig)? {
        let config = JiraConfig.shared
        guard config.isConfigured else { return nil }
        guard let url = URL(string: "\(config.baseURL)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let auth = config.authHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return (request, config)
    }

    // MARK: - jira_create_subtask

    private static func executeJiraCreateSubtask(_ call: ToolCall) async -> ToolResult {
        guard let parentKey = call.arguments["parent_key"]?.stringValue else {
            return ToolResult(callID: call.id, content: "parent_key 파라미터가 필요합니다.", isError: true)
        }
        guard let summary = call.arguments["summary"]?.stringValue else {
            return ToolResult(callID: call.id, content: "summary 파라미터가 필요합니다.", isError: true)
        }
        let projectKey = call.arguments["project_key"]?.stringValue
            ?? parentKey.components(separatedBy: "-").first ?? ""

        let fields: [String: Any] = [
            "project": ["key": projectKey],
            "parent": ["key": parentKey],
            "summary": summary,
            "issuetype": ["name": "Sub-task"]
        ]
        let payload: [String: Any] = ["fields": fields]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return ToolResult(callID: call.id, content: "JSON 직렬화 실패", isError: true)
        }
        guard let (request, _) = makeJiraRequest(path: "/rest/api/3/issue", method: "POST", body: body) else {
            return ToolResult(callID: call.id, content: "Jira가 설정되지 않았습니다. 설정 → Jira에서 도메인과 API 토큰을 입력하세요.", isError: true)
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                let errBody = String(data: data, encoding: .utf8) ?? "(응답 없음)"
                return ToolResult(callID: call.id, content: "Jira API 오류 (HTTP \(statusCode)): \(String(errBody.prefix(2000)))", isError: true)
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let key = json["key"] as? String {
                return ToolResult(callID: call.id, content: "서브태스크 생성 완료: \(key) — \(summary)", isError: false)
            }
            return ToolResult(callID: call.id, content: "서브태스크 생성 완료 (응답 파싱 실패)", isError: false)
        } catch {
            return ToolResult(callID: call.id, content: "Jira 요청 실패: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - jira_update_status

    private static func executeJiraUpdateStatus(_ call: ToolCall) async -> ToolResult {
        guard let issueKey = call.arguments["issue_key"]?.stringValue else {
            return ToolResult(callID: call.id, content: "issue_key 파라미터가 필요합니다.", isError: true)
        }
        guard let statusName = call.arguments["status_name"]?.stringValue else {
            return ToolResult(callID: call.id, content: "status_name 파라미터가 필요합니다.", isError: true)
        }

        // 1) 사용 가능한 전이 목록 조회
        guard let (getRequest, _) = makeJiraRequest(path: "/rest/api/3/issue/\(issueKey)/transitions") else {
            return ToolResult(callID: call.id, content: "Jira가 설정되지 않았습니다. 설정 → Jira에서 도메인과 API 토큰을 입력하세요.", isError: true)
        }

        do {
            let (getData, getResponse) = try await urlSession.data(for: getRequest)
            let getStatus = (getResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(getStatus) else {
                let errBody = String(data: getData, encoding: .utf8) ?? ""
                return ToolResult(callID: call.id, content: "전이 목록 조회 실패 (HTTP \(getStatus)): \(String(errBody.prefix(1000)))", isError: true)
            }

            guard let json = try? JSONSerialization.jsonObject(with: getData) as? [String: Any],
                  let transitions = json["transitions"] as? [[String: Any]] else {
                return ToolResult(callID: call.id, content: "전이 목록 파싱 실패", isError: true)
            }

            // 2) 대소문자 무시 매칭
            let targetLower = statusName.lowercased()
            guard let matched = transitions.first(where: {
                ($0["name"] as? String)?.lowercased() == targetLower
            }), let transitionID = matched["id"] as? String else {
                let available = transitions.compactMap { $0["name"] as? String }.joined(separator: ", ")
                return ToolResult(callID: call.id, content: "'\(statusName)' 상태를 찾을 수 없습니다. 사용 가능한 전이: \(available.isEmpty ? "(없음)" : available)", isError: true)
            }

            // 3) 전이 실행
            let payload: [String: Any] = ["transition": ["id": transitionID]]
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
                return ToolResult(callID: call.id, content: "JSON 직렬화 실패", isError: true)
            }
            guard let (postRequest, _) = makeJiraRequest(path: "/rest/api/3/issue/\(issueKey)/transitions", method: "POST", body: body) else {
                return ToolResult(callID: call.id, content: "Jira 요청 생성 실패", isError: true)
            }

            let (postData, postResponse) = try await urlSession.data(for: postRequest)
            let postStatus = (postResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(postStatus) else {
                let errBody = String(data: postData, encoding: .utf8) ?? ""
                return ToolResult(callID: call.id, content: "상태 변경 실패 (HTTP \(postStatus)): \(String(errBody.prefix(1000)))", isError: true)
            }

            return ToolResult(callID: call.id, content: "\(issueKey) 상태가 '\(statusName)'(으)로 변경되었습니다.", isError: false)
        } catch {
            return ToolResult(callID: call.id, content: "Jira 요청 실패: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - jira_add_comment

    private static func executeJiraAddComment(_ call: ToolCall) async -> ToolResult {
        guard let issueKey = call.arguments["issue_key"]?.stringValue else {
            return ToolResult(callID: call.id, content: "issue_key 파라미터가 필요합니다.", isError: true)
        }
        guard let comment = call.arguments["comment"]?.stringValue else {
            return ToolResult(callID: call.id, content: "comment 파라미터가 필요합니다.", isError: true)
        }

        // Atlassian Document Format (ADF) body
        let adfBody: [String: Any] = [
            "body": [
                "version": 1,
                "type": "doc",
                "content": [
                    [
                        "type": "paragraph",
                        "content": [
                            ["type": "text", "text": comment]
                        ]
                    ]
                ]
            ]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: adfBody) else {
            return ToolResult(callID: call.id, content: "JSON 직렬화 실패", isError: true)
        }
        guard let (request, _) = makeJiraRequest(path: "/rest/api/3/issue/\(issueKey)/comment", method: "POST", body: body) else {
            return ToolResult(callID: call.id, content: "Jira가 설정되지 않았습니다. 설정 → Jira에서 도메인과 API 토큰을 입력하세요.", isError: true)
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                let errBody = String(data: data, encoding: .utf8) ?? ""
                return ToolResult(callID: call.id, content: "코멘트 추가 실패 (HTTP \(statusCode)): \(String(errBody.prefix(1000)))", isError: true)
            }
            return ToolResult(callID: call.id, content: "\(issueKey)에 코멘트가 추가되었습니다.", isError: false)
        } catch {
            return ToolResult(callID: call.id, content: "Jira 요청 실패: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - ask_user

    private static func executeAskUser(_ call: ToolCall, context: ToolExecutionContext = .empty) async -> ToolResult {
        // Clarify 단계에서만 허용
        guard context.currentPhase == .clarify else {
            return ToolResult(
                callID: call.id,
                content: "ask_user 도구는 Clarify 단계에서만 사용할 수 있습니다. 현재 단계: \(context.currentPhase?.rawValue ?? "없음")",
                isError: true
            )
        }

        guard let question = call.arguments["question"]?.stringValue else {
            return ToolResult(callID: call.id, content: "question 파라미터가 필요합니다.", isError: true)
        }

        let questionContext = call.arguments["context"]?.stringValue
        let options: [String]? = call.arguments["options"]?.arrayValue

        let answer = await context.askUser(question, questionContext, options)
        if answer.isEmpty {
            return ToolResult(callID: call.id, content: "(사용자가 응답하지 않았습니다. 이 항목에 대해 가정을 선언하세요.)", isError: false)
        }
        return ToolResult(callID: call.id, content: "사용자 답변: \(answer)", isError: false)
    }

    // MARK: - 도구 활동 상세 생성

    /// 도구 호출 시작 시 UI 표시용 상세 정보 생성 (결과 없이 호출 정보만)
    private static func buildCallStartDetail(call: ToolCall) -> ToolActivityDetail {
        let toolName = call.toolName
        let subject: String?
        switch toolName {
        case "file_read":
            subject = call.arguments["path"]?.stringValue ?? call.arguments["file_path"]?.stringValue
        case "file_write":
            subject = call.arguments["path"]?.stringValue ?? call.arguments["file_path"]?.stringValue
        case "shell_exec":
            let cmd = call.arguments["command"]?.stringValue ?? ""
            subject = cmd.count > 80 ? String(cmd.prefix(77)) + "..." : cmd
        case "web_fetch":
            subject = call.arguments["url"]?.stringValue
        case "web_search":
            subject = call.arguments["query"]?.stringValue
        case "code_search":
            subject = call.arguments["pattern"]?.stringValue
        case "code_symbols":
            subject = call.arguments["query"]?.stringValue ?? call.arguments["kind"]?.stringValue
        case "code_diagnostics":
            subject = call.arguments["command"]?.stringValue ?? call.arguments["path"]?.stringValue
        case "code_outline":
            subject = call.arguments["path"]?.stringValue
        default:
            subject = nil
        }
        return ToolActivityDetail(toolName: toolName, subject: subject, contentPreview: nil, isError: false)
    }

    /// 도구 호출 결과에서 UI 표시용 상세 정보 생성
    private static func buildActivityDetail(call: ToolCall?, result: ToolResult) -> ToolActivityDetail {
        let toolName = call?.toolName ?? "unknown"
        let subject: String?
        let preview: String?
        let maxPreview = 2000

        switch toolName {
        case "file_write":
            subject = call?.arguments["path"]?.stringValue
            let written = call?.arguments["content"]?.stringValue ?? ""
            preview = truncatePreview(written, max: maxPreview)
        case "file_read":
            subject = call?.arguments["path"]?.stringValue
            preview = truncatePreview(result.content, max: maxPreview)
        case "shell_exec":
            subject = call?.arguments["command"]?.stringValue
            preview = truncatePreview(result.content, max: maxPreview)
        case "web_fetch":
            subject = call?.arguments["url"]?.stringValue
            preview = truncatePreview(result.content, max: maxPreview)
        default:
            subject = nil
            preview = result.content.isEmpty ? nil : truncatePreview(result.content, max: maxPreview)
        }

        return ToolActivityDetail(
            toolName: toolName,
            subject: subject,
            contentPreview: preview,
            isError: result.isError
        )
    }

    /// 긴 텍스트를 앞/뒤 보존하고 중간 생략
    private static func truncatePreview(_ text: String, max: Int) -> String? {
        guard !text.isEmpty else { return nil }
        if text.count <= max { return text }
        let headLen = max * 3 / 4
        let tailLen = max / 4
        let head = String(text.prefix(headLen))
        let tail = String(text.suffix(tailLen))
        let omitted = text.count - headLen - tailLen
        return "\(head)\n\n... (\(omitted)자 생략) ...\n\n\(tail)"
    }

    // MARK: - shell_exec

    private static func executeShellExec(_ call: ToolCall, context: ToolExecutionContext = .empty) async -> ToolResult {
        guard let command = call.arguments["command"]?.stringValue else {
            return ToolResult(callID: call.id, content: "command 파라미터가 필요합니다.", isError: true)
        }
        // working_directory 미지정 시 projectPath를 기본값으로 사용
        let workDir = call.arguments["working_directory"]?.stringValue ?? context.projectPaths.first

        // 환경 변수 구성 (캐싱된 PATH 사용)
        let env = ShellEnvironment.mergedEnvironment()

        let result = await ProcessRunner.run(
            executable: "/bin/zsh",
            args: ["-c", command],
            env: env,
            workDir: workDir
        )

        let exitCode = result.exitCode
        var output = ""
        if !result.stdout.isEmpty { output += result.stdout }
        if !result.stderr.isEmpty { output += (output.isEmpty ? "" : "\n") + "stderr: " + result.stderr }
        if output.isEmpty { output = "(출력 없음)" }

        // 출력 크기 제한
        let maxLen = 30_000
        if output.count > maxLen {
            output = String(output.prefix(maxLen)) + "\n... (출력이 잘렸습니다)"
        }

        output += "\n[종료 코드: \(exitCode)]"

        return ToolResult(
            callID: call.id,
            content: output,
            isError: exitCode != 0
        )
    }

    // MARK: - 코드 인텔리전스 도구

    /// ripgrep 바이너리 경로 (Homebrew → 시스템 순으로 탐색)
    private static let rgPath: String = {
        let candidates = [
            "/opt/homebrew/bin/rg",
            "/usr/local/bin/rg",
            "/usr/bin/rg"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "rg"
    }()

    // MARK: - code_search

    private static func executeCodeSearch(_ call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        guard let pattern = call.arguments["pattern"]?.stringValue, !pattern.isEmpty else {
            return ToolResult(callID: call.id, content: "pattern 파라미터가 필요합니다.", isError: true)
        }

        let searchPath: String
        if let p = call.arguments["path"]?.stringValue {
            searchPath = resolvePath(p, projectPaths: context.projectPaths)
        } else {
            searchPath = context.projectPaths.first ?? "."
        }

        guard isPathAllowed(searchPath, projectPaths: context.projectPaths) else {
            return ToolResult(callID: call.id, content: "접근이 허용되지 않은 경로입니다: \(searchPath)", isError: true)
        }

        var maxResults = 30
        if case .integer(let n) = call.arguments["max_results"] {
            maxResults = min(max(n, 1), 100)
        }

        var contextLines = 0
        if case .integer(let n) = call.arguments["context_lines"] {
            contextLines = min(max(n, 0), 5)
        }

        let caseSensitive: Bool
        if case .boolean(let b) = call.arguments["case_sensitive"] {
            caseSensitive = b
        } else {
            caseSensitive = true
        }

        var args = [
            "--no-heading", "--line-number", "--column",
            "--max-count", "\(maxResults)",
            "--max-columns", "200",
            "--max-columns-preview"
        ]
        if contextLines > 0 {
            args += ["-C", "\(contextLines)"]
        }
        if !caseSensitive {
            args.append("-i")
        }
        if let glob = call.arguments["file_glob"]?.stringValue, !glob.isEmpty {
            args += ["-g", glob]
        }
        args += [pattern, searchPath]

        let result = await ProcessRunner.run(
            executable: rgPath,
            args: args,
            env: ShellEnvironment.mergedEnvironment(),
            workDir: context.projectPaths.first
        )

        // rg exit code: 0=matches, 1=no matches, 2=error
        if result.exitCode == 2 {
            let errMsg = result.stderr.isEmpty ? result.stdout : result.stderr
            return ToolResult(callID: call.id, content: "검색 오류: \(errMsg)", isError: true)
        }

        if result.exitCode == 1 || result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolResult(callID: call.id, content: "검색 결과 없음: \(pattern)", isError: false)
        }

        var output = result.stdout
        let maxLen = 40_000
        if output.count > maxLen {
            output = String(output.prefix(maxLen)) + "\n\n... (결과가 잘렸습니다)"
        }

        // 매치 수 카운트
        let matchCount = output.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("--") }.count
        return ToolResult(
            callID: call.id,
            content: "검색 결과 (\(matchCount)건, 패턴: \(pattern)):\n\n\(output)",
            isError: false
        )
    }

    // MARK: - code_symbols

    /// 언어별 심볼 정의 패턴
    private static let symbolPatterns: [(kind: String, langs: String, pattern: String)] = [
        // Swift
        ("class",    "*.swift", "^\\s*(public |private |internal |open |fileprivate )?\\s*(final )?class\\s+\\w+"),
        ("struct",   "*.swift", "^\\s*(public |private |internal )?struct\\s+\\w+"),
        ("enum",     "*.swift", "^\\s*(public |private |internal )?enum\\s+\\w+"),
        ("protocol", "*.swift", "^\\s*(public |private |internal )?protocol\\s+\\w+"),
        ("function", "*.swift", "^\\s*(public |private |internal |open |fileprivate |static |class )?\\s*(override )?func\\s+\\w+"),
        ("property", "*.swift", "^\\s*(public |private |internal |static |lazy )?\\s*(var|let)\\s+\\w+"),
        // TypeScript / JavaScript
        ("class",    "*.{ts,tsx,js,jsx}", "^\\s*(export\\s+)?(default\\s+)?class\\s+\\w+"),
        ("interface","*.{ts,tsx}", "^\\s*(export\\s+)?interface\\s+\\w+"),
        ("type",     "*.{ts,tsx}", "^\\s*(export\\s+)?type\\s+\\w+\\s*="),
        ("function", "*.{ts,tsx,js,jsx}", "^\\s*(export\\s+)?(default\\s+)?(async\\s+)?function\\s+\\w+"),
        ("function", "*.{ts,tsx,js,jsx}", "^\\s*(export\\s+)?(const|let|var)\\s+\\w+\\s*=\\s*(async\\s+)?\\("),
        // Python
        ("class",    "*.py", "^class\\s+\\w+"),
        ("function", "*.py", "^\\s*def\\s+\\w+"),
        // Go
        ("struct",   "*.go", "^type\\s+\\w+\\s+struct"),
        ("interface","*.go", "^type\\s+\\w+\\s+interface"),
        ("function", "*.go", "^func\\s+(\\(\\w+\\s+\\*?\\w+\\)\\s+)?\\w+"),
        // Rust
        ("struct",   "*.rs", "^\\s*(pub\\s+)?struct\\s+\\w+"),
        ("enum",     "*.rs", "^\\s*(pub\\s+)?enum\\s+\\w+"),
        ("function", "*.rs", "^\\s*(pub\\s+)?(async\\s+)?fn\\s+\\w+"),
    ]

    private static func executeCodeSymbols(_ call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        let searchPath: String
        if let p = call.arguments["path"]?.stringValue {
            searchPath = resolvePath(p, projectPaths: context.projectPaths)
        } else {
            searchPath = context.projectPaths.first ?? "."
        }

        guard isPathAllowed(searchPath, projectPaths: context.projectPaths) else {
            return ToolResult(callID: call.id, content: "접근이 허용되지 않은 경로입니다: \(searchPath)", isError: true)
        }

        var maxResults = 50
        if case .integer(let n) = call.arguments["max_results"] {
            maxResults = min(max(n, 1), 200)
        }

        let queryFilter = call.arguments["query"]?.stringValue
        let kindFilter = call.arguments["kind"]?.stringValue
        let fileGlob = call.arguments["file_glob"]?.stringValue

        // 적용할 패턴 필터링
        var patterns = symbolPatterns
        if let kind = kindFilter {
            patterns = patterns.filter { $0.kind == kind }
        }
        if let glob = fileGlob {
            // 사용자가 파일 글로브를 지정하면 해당 글로브의 패턴만 남기거나, 모든 패턴을 해당 글로브에 적용
            patterns = symbolPatterns.map { (kind: $0.kind, langs: glob, pattern: $0.pattern) }
            if let kind = kindFilter {
                patterns = patterns.filter { $0.kind == kind }
            }
        }

        if patterns.isEmpty {
            return ToolResult(callID: call.id, content: "지정된 kind '\(kindFilter ?? "")'에 해당하는 패턴이 없습니다.", isError: true)
        }

        // 각 패턴별로 rg 실행 후 결과 합산
        struct SymbolMatch: Comparable {
            let kind: String
            let name: String
            let file: String
            let line: Int
            let text: String

            static func < (lhs: SymbolMatch, rhs: SymbolMatch) -> Bool {
                if lhs.file != rhs.file { return lhs.file < rhs.file }
                return lhs.line < rhs.line
            }
        }

        var allMatches: [SymbolMatch] = []

        for pat in patterns {
            var args = [
                "--no-heading", "--line-number",
                "-g", pat.langs,
                "--max-count", "200",
                "--max-columns", "200",
                pat.pattern, searchPath
            ]
            // 쿼리 필터가 있으면 심볼 이름에 추가 필터
            if queryFilter != nil {
                // rg에서 직접 필터링은 어려우므로 결과에서 후처리
            }
            _ = args // suppress unused warning

            let result = await ProcessRunner.run(
                executable: rgPath,
                args: [
                    "--no-heading", "--line-number",
                    "-g", pat.langs,
                    "--max-count", "200",
                    "--max-columns", "200",
                    pat.pattern, searchPath
                ],
                env: ShellEnvironment.mergedEnvironment(),
                workDir: context.projectPaths.first
            )

            guard result.exitCode != 2 else { continue }

            for line in result.stdout.components(separatedBy: "\n") where !line.isEmpty {
                // 형식: file:line:text
                let parts = line.split(separator: ":", maxSplits: 2)
                guard parts.count >= 3,
                      let lineNum = Int(parts[1]) else { continue }
                let file = String(parts[0])
                let text = String(parts[2]).trimmingCharacters(in: .whitespaces)

                // 심볼 이름 추출 (선언 키워드 뒤의 첫 단어)
                let namePattern = "(?:class|struct|enum|protocol|interface|func|function|def|type|fn)\\s+(\\w+)"
                let name: String
                if let range = text.range(of: namePattern, options: .regularExpression),
                   let nameRange = text[range].split(separator: " ").last {
                    name = String(nameRange).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                } else {
                    name = text.prefix(40).trimmingCharacters(in: .whitespaces)
                }

                // 쿼리 필터 적용
                if let query = queryFilter, !query.isEmpty {
                    let lowerName = name.lowercased()
                    let lowerText = text.lowercased()
                    let lowerQuery = query.lowercased()
                    // 정규식 매칭 시도, 실패하면 단순 포함 검사
                    let matches: Bool
                    if let regex = try? NSRegularExpression(pattern: query, options: .caseInsensitive) {
                        let nameRange = NSRange(name.startIndex..., in: name)
                        matches = regex.firstMatch(in: name, range: nameRange) != nil
                    } else {
                        matches = lowerName.contains(lowerQuery) || lowerText.contains(lowerQuery)
                    }
                    guard matches else { continue }
                }

                allMatches.append(SymbolMatch(kind: pat.kind, name: name, file: file, line: lineNum, text: text))
            }
        }

        // 중복 제거 (같은 파일, 같은 줄)
        var seen = Set<String>()
        allMatches = allMatches.filter { seen.insert("\($0.file):\($0.line)").inserted }
        allMatches.sort()

        if allMatches.isEmpty {
            let desc = [kindFilter, queryFilter].compactMap { $0 }.joined(separator: ", ")
            return ToolResult(callID: call.id, content: "심볼을 찾을 수 없습니다\(desc.isEmpty ? "" : " (\(desc))")", isError: false)
        }

        // 프로젝트 루트 기준 상대 경로로 변환
        let basePrefix = (searchPath.hasSuffix("/") ? searchPath : searchPath + "/")

        let truncated = Array(allMatches.prefix(maxResults))
        var output = "심볼 \(truncated.count)개"
        if allMatches.count > maxResults {
            output += " (전체 \(allMatches.count)개 중 상위 \(maxResults)개)"
        }
        output += ":\n\n"

        for m in truncated {
            let relPath = m.file.hasPrefix(basePrefix) ? String(m.file.dropFirst(basePrefix.count)) : m.file
            output += "[\(m.kind)] \(m.name)  — \(relPath):\(m.line)\n"
        }

        return ToolResult(callID: call.id, content: output, isError: false)
    }

    // MARK: - code_diagnostics

    private static func executeCodeDiagnostics(_ call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        let projectPath: String
        if let p = call.arguments["path"]?.stringValue {
            projectPath = resolvePath(p, projectPaths: context.projectPaths)
        } else {
            projectPath = context.projectPaths.first ?? "."
        }

        guard isPathAllowed(projectPath, projectPaths: context.projectPaths) else {
            return ToolResult(callID: call.id, content: "접근이 허용되지 않은 경로입니다: \(projectPath)", isError: true)
        }

        let severityFilter = call.arguments["severity"]?.stringValue ?? "all"

        // 사용자 지정 명령 또는 프로젝트 유형 자동 감지
        let command: String
        if let customCmd = call.arguments["command"]?.stringValue, !customCmd.isEmpty {
            command = customCmd
        } else {
            command = detectDiagnosticCommand(projectPath: projectPath)
        }

        let env = ShellEnvironment.mergedEnvironment()
        let result = await ProcessRunner.run(
            executable: "/bin/zsh",
            args: ["-c", command],
            env: env,
            workDir: projectPath
        )

        var output = result.stdout
        if !result.stderr.isEmpty {
            output += (output.isEmpty ? "" : "\n") + result.stderr
        }

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolResult(callID: call.id, content: "진단 결과: 문제 없음 ✓", isError: false)
        }

        // severity 필터링
        if severityFilter == "error" {
            let lines = output.components(separatedBy: "\n")
            let filtered = lines.filter { line in
                let lower = line.lowercased()
                return lower.contains("error") || lower.contains("오류")
            }
            if filtered.isEmpty {
                return ToolResult(callID: call.id, content: "에러 없음 (경고가 있을 수 있음). 전체 보기: severity=all", isError: false)
            }
            output = filtered.joined(separator: "\n")
        } else if severityFilter == "warning" {
            let lines = output.components(separatedBy: "\n")
            let filtered = lines.filter { line in
                let lower = line.lowercased()
                return lower.contains("warning") || lower.contains("error") || lower.contains("경고") || lower.contains("오류")
            }
            output = filtered.isEmpty ? output : filtered.joined(separator: "\n")
        }

        // 크기 제한
        let maxLen = 40_000
        if output.count > maxLen {
            output = String(output.prefix(maxLen)) + "\n\n... (출력이 잘렸습니다)"
        }

        // 에러/경고 수 카운트
        let errorCount = output.lowercased().components(separatedBy: "error").count - 1
        let warningCount = output.lowercased().components(separatedBy: "warning").count - 1
        let summary = "진단 결과: 에러 \(errorCount)건, 경고 \(warningCount)건 (명령: \(command))\n\n"

        return ToolResult(
            callID: call.id,
            content: summary + output,
            isError: errorCount > 0
        )
    }

    /// 프로젝트 디렉토리에서 빌드 시스템 자동 감지
    private static func detectDiagnosticCommand(projectPath: String) -> String {
        let fm = FileManager.default
        let exists = { (name: String) -> Bool in
            fm.fileExists(atPath: (projectPath as NSString).appendingPathComponent(name))
        }

        if exists("Package.swift") {
            return "swift build 2>&1 | tail -100"
        } else if exists("tsconfig.json") {
            return "npx tsc --noEmit 2>&1 | tail -100"
        } else if exists("package.json") {
            // eslint이 있으면 사용
            let packagePath = (projectPath as NSString).appendingPathComponent("package.json")
            if let data = fm.contents(atPath: packagePath),
               let content = String(data: data, encoding: .utf8),
               content.contains("eslint") {
                return "npx eslint . --max-warnings=50 2>&1 | tail -100"
            }
            return "npx tsc --noEmit 2>&1 || echo 'tsc not available' | tail -100"
        } else if exists("Cargo.toml") {
            return "cargo check 2>&1 | tail -100"
        } else if exists("go.mod") {
            return "go vet ./... 2>&1 | tail -100"
        } else if exists("requirements.txt") || exists("pyproject.toml") || exists("setup.py") {
            return "python -m py_compile $(find . -name '*.py' -maxdepth 3 | head -20) 2>&1 | tail -100"
        } else if exists("Makefile") || exists("makefile") {
            return "make -n 2>&1 | head -20; echo '--- dry run above ---'"
        }

        return "echo '빌드 시스템을 감지할 수 없습니다. command 파라미터로 명령을 직접 지정하세요.'"
    }

    // MARK: - code_outline

    private static func executeCodeOutline(_ call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        guard let rawPath = call.arguments["path"]?.stringValue else {
            return ToolResult(callID: call.id, content: "path 파라미터가 필요합니다.", isError: true)
        }
        let path = resolvePath(rawPath, projectPaths: context.projectPaths)
        guard isPathAllowed(path, projectPaths: context.projectPaths) else {
            return ToolResult(callID: call.id, content: "접근이 허용되지 않은 경로입니다: \(path)", isError: true)
        }

        var maxDepth = 3
        if case .integer(let n) = call.arguments["depth"] {
            maxDepth = min(max(n, 1), 10)
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ToolResult(callID: call.id, content: "파일을 읽을 수 없습니다: \(path)", isError: true)
        }

        let ext = (path as NSString).pathExtension.lowercased()
        let outline = buildOutline(content: content, extension: ext, maxDepth: maxDepth)

        if outline.isEmpty {
            return ToolResult(callID: call.id, content: "구조를 추출할 수 없습니다 (지원 확장자: swift, ts, tsx, js, py, go, rs)", isError: false)
        }

        let fileName = (path as NSString).lastPathComponent
        let lineCount = content.components(separatedBy: "\n").count
        return ToolResult(
            callID: call.id,
            content: "파일 구조: \(fileName) (\(lineCount)줄)\n\n\(outline)",
            isError: false
        )
    }

    /// 소스 파일의 구조적 아웃라인을 생성
    private static func buildOutline(content: String, extension ext: String, maxDepth: Int) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []

        // 언어별 선언 패턴 정의
        let patterns: [(regex: NSRegularExpression, kind: String, extractName: Bool)]
        switch ext {
        case "swift":
            patterns = compilePatterns([
                ("^(\\s*)(public |private |internal |open |fileprivate )?(final )?(class|struct|enum|protocol|extension|actor)\\s+(\\w+)", "decl", true),
                ("^(\\s*)(public |private |internal |open |fileprivate |static |class )?(override )?func\\s+(\\w+)", "func", true),
                ("^(\\s*)(public |private |internal |static |lazy )?\\s*(?:var|let)\\s+(\\w+)\\s*[:=]", "prop", true),
                ("^(\\s*)// MARK: -?\\s*(.+)", "mark", true),
            ])
        case "ts", "tsx", "js", "jsx":
            patterns = compilePatterns([
                ("^(\\s*)(export\\s+)?(default\\s+)?class\\s+(\\w+)", "decl", true),
                ("^(\\s*)(export\\s+)?interface\\s+(\\w+)", "decl", true),
                ("^(\\s*)(export\\s+)?type\\s+(\\w+)\\s*=", "decl", true),
                ("^(\\s*)(export\\s+)?(default\\s+)?(async\\s+)?function\\s+(\\w+)", "func", true),
                ("^(\\s*)(export\\s+)?(const|let|var)\\s+(\\w+)\\s*=\\s*(async\\s+)?[\\(\\[]", "func", true),
            ])
        case "py":
            patterns = compilePatterns([
                ("^(\\s*)class\\s+(\\w+)", "decl", true),
                ("^(\\s*)def\\s+(\\w+)", "func", true),
            ])
        case "go":
            patterns = compilePatterns([
                ("^type\\s+(\\w+)\\s+(struct|interface)", "decl", true),
                ("^func\\s+(\\(\\w+\\s+\\*?\\w+\\)\\s+)?(\\w+)", "func", true),
            ])
        case "rs":
            patterns = compilePatterns([
                ("^(\\s*)(pub\\s+)?struct\\s+(\\w+)", "decl", true),
                ("^(\\s*)(pub\\s+)?enum\\s+(\\w+)", "decl", true),
                ("^(\\s*)(pub\\s+)?trait\\s+(\\w+)", "decl", true),
                ("^(\\s*)(pub\\s+)?(async\\s+)?fn\\s+(\\w+)", "func", true),
                ("^(\\s*)impl\\s+(\\w+)", "decl", true),
            ])
        default:
            return ""
        }

        for (lineNum, line) in lines.enumerated() {
            for pat in patterns {
                let nsLine = line as NSString
                let range = NSRange(location: 0, length: nsLine.length)
                guard let match = pat.regex.firstMatch(in: line, range: range) else { continue }

                // 들여쓰기 깊이 계산
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                let depth = indent / (ext == "py" ? 4 : 4)  // 4-space indent 기준
                guard depth < maxDepth else { continue }

                let prefix = String(repeating: "  ", count: depth)
                let kindIcon: String
                switch pat.kind {
                case "decl": kindIcon = "◆"
                case "func": kindIcon = "▸"
                case "prop": kindIcon = "·"
                case "mark": kindIcon = "━"
                default: kindIcon = " "
                }

                // 줄 내용을 정리해서 표시
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let display: String
                if trimmed.count > 80 {
                    display = String(trimmed.prefix(77)) + "..."
                } else {
                    display = trimmed
                }

                result.append("\(String(format: "%4d", lineNum + 1)) │ \(prefix)\(kindIcon) \(display)")
                break  // 한 줄에 하나의 패턴만 매칭
            }
        }

        return result.joined(separator: "\n")
    }

    /// 정규식 패턴을 컴파일 (실패 시 무시)
    private static func compilePatterns(_ defs: [(pattern: String, kind: String, extractName: Bool)]) -> [(regex: NSRegularExpression, kind: String, extractName: Bool)] {
        defs.compactMap { def in
            guard let regex = try? NSRegularExpression(pattern: def.pattern, options: []) else { return nil }
            return (regex: regex, kind: def.kind, extractName: def.extractName)
        }
    }
}
