import Foundation

/// 도구 호출 루프 실행 + smartSend 유틸리티
enum ToolExecutor {
    static let maxIterations = 10

    /// 테스트에서 교체 가능한 URLSession (web_fetch용)
    nonisolated(unsafe) static var urlSession: URLSession = .shared

    /// 도구 사용 가능한 경우 도구 루프 실행, 아니면 기존 sendMessage 폴백
    static func smartSend(
        provider: AIProvider,
        agent: Agent,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        context: ToolExecutionContext = .empty,
        onToolActivity: ((String) -> Void)? = nil
    ) async throws -> String {
        let toolIDs = agent.resolvedToolIDs

        // 도구 없거나 프로바이더가 도구 미지원 → 기존 경로
        guard !toolIDs.isEmpty, provider.supportsToolCalling else {
            onToolActivity?("API 요청: \(agent.providerName) (\(agent.modelName))")
            let result: String
            if let claudeProvider = provider as? ClaudeCodeProvider {
                result = try await claudeProvider.sendMessage(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: messages,
                    workingDirectory: context.projectPaths.first
                )
            } else {
                result = try await provider.sendMessage(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: messages
                )
            }
            onToolActivity?("응답 수신 성공 (\(result.count)자)")
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
        onToolActivity: ((String) -> Void)? = nil
    ) async throws -> String {
        let toolIDs = agent.resolvedToolIDs

        // 이미지가 있으면 sendMessageWithTools 경로 사용 (Vision 지원)
        let hasAttachments = conversationMessages.contains { $0.attachments != nil && !($0.attachments?.isEmpty ?? true) }

        guard hasAttachments || (!toolIDs.isEmpty && provider.supportsToolCalling) else {
            // 이미지도 도구도 없으면 기존 sendMessage
            let simple = conversationMessages.compactMap { msg -> (role: String, content: String)? in
                guard let content = msg.content else { return nil }
                return (role: msg.role, content: content)
            }
            onToolActivity?("API 요청: \(agent.providerName) (\(agent.modelName))")
            let result: String
            if let claudeProvider = provider as? ClaudeCodeProvider {
                result = try await claudeProvider.sendMessage(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: simple,
                    workingDirectory: context.projectPaths.first
                )
            } else {
                result = try await provider.sendMessage(
                    model: agent.modelName,
                    systemPrompt: systemPrompt,
                    messages: simple
                )
            }
            onToolActivity?("응답 수신 성공 (\(result.count)자)")
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
        onToolActivity: ((String) -> Void)? = nil
    ) async throws -> String {
        var messages = initialMessages

        for _ in 0..<maxIterations {
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
                for call in calls {
                    onToolActivity?("도구 호출: \(call.toolName)")
                    let result = await executeSingleTool(call, context: context)
                    onToolActivity?("도구 결과: \(call.toolName) → \(result.isError ? "오류" : "성공")")
                    messages.append(.toolResult(callID: result.callID, content: result.content, isError: result.isError))
                }

            case .mixed(let text, let calls):
                messages.append(.assistantToolCalls(calls, text: text))
                for call in calls {
                    onToolActivity?("도구 호출: \(call.toolName)")
                    let result = await executeSingleTool(call, context: context)
                    onToolActivity?("도구 결과: \(call.toolName) → \(result.isError ? "오류" : "성공")")
                    messages.append(.toolResult(callID: result.callID, content: result.content, isError: result.isError))
                }
            }
        }

        throw AIProviderError.apiError("도구 호출 반복 횟수 초과 (최대 \(maxIterations)회)")
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

    private static func executeSingleTool(_ call: ToolCall, context: ToolExecutionContext = .empty) async -> ToolResult {
        switch call.toolName {
        case "file_read":
            return await executeFileRead(call, context: context)
        case "file_write":
            return await executeFileWrite(call, context: context)
        case "shell_exec":
            return await executeShellExec(call, context: context)
        case "web_search":
            return ToolResult(callID: call.id, content: "웹 검색 기능은 아직 구현되지 않았습니다.", isError: true)
        case "web_fetch":
            return await executeWebFetch(call)
        case "invite_agent":
            return await executeInviteAgent(call, context: context)
        case "list_agents":
            return await executeListAgents(call, context: context)
        case "suggest_agent_creation":
            return await executeSuggestAgentCreation(call, context: context)
        case "jira_create_subtask":
            return await executeJiraCreateSubtask(call)
        case "jira_update_status":
            return await executeJiraUpdateStatus(call)
        case "jira_add_comment":
            return await executeJiraAddComment(call)
        case "ask_user":
            return await executeAskUser(call, context: context)
        default:
            return ToolResult(callID: call.id, content: "알 수 없는 도구: \(call.toolName)", isError: true)
        }
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

    // MARK: - shell_exec

    private static func executeShellExec(_ call: ToolCall, context: ToolExecutionContext = .empty) async -> ToolResult {
        guard let command = call.arguments["command"]?.stringValue else {
            return ToolResult(callID: call.id, content: "command 파라미터가 필요합니다.", isError: true)
        }
        // working_directory 미지정 시 projectPath를 기본값으로 사용
        let workDir = call.arguments["working_directory"]?.stringValue ?? context.projectPaths.first

        // 환경 변수 구성
        var env = ProcessInfo.processInfo.environment
        let homePath = env["HOME"] ?? "/Users/\(NSUserName())"

        var additionalPaths: [String] = []
        let nvmDir = "\(homePath)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                additionalPaths.append("\(nvmDir)/\(version)/bin")
            }
        }
        additionalPaths.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin"])

        if let existingPath = env["PATH"] {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath
        }

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
}
