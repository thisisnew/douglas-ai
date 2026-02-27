import Foundation

/// 도구 호출 루프 실행 + smartSend 유틸리티
enum ToolExecutor {
    static let maxIterations = 10

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
            return try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: systemPrompt,
                messages: messages
            )
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
            return try await provider.sendMessage(
                model: agent.modelName,
                systemPrompt: systemPrompt,
                messages: simple
            )
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

    /// 파일 접근이 허용된 경로인지 확인. $HOME, /tmp, 시스템 임시 디렉토리 허용.
    static func isPathAllowed(_ path: String) -> Bool {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath).standardized
        let resolved = url.path

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let tempDir = NSTemporaryDirectory()
        let allowedPrefixes = [homePath, "/tmp", "/private/tmp", tempDir, "/var/folders"]
        let blockedPrefixes = [
            "\(homePath)/Library/Keychains",
            "\(homePath)/.ssh",
            "\(homePath)/.gnupg"
        ]

        // 차단 목록 먼저 확인
        for blocked in blockedPrefixes {
            if resolved.hasPrefix(blocked) { return false }
        }

        // 허용 목록 확인
        for allowed in allowedPrefixes {
            if resolved.hasPrefix(allowed) { return true }
        }

        return false
    }

    // MARK: - 개별 도구 실행

    private static func executeSingleTool(_ call: ToolCall, context: ToolExecutionContext = .empty) async -> ToolResult {
        switch call.toolName {
        case "file_read":
            return await executeFileRead(call)
        case "file_write":
            return await executeFileWrite(call)
        case "shell_exec":
            return await executeShellExec(call)
        case "web_search":
            return ToolResult(callID: call.id, content: "웹 검색 기능은 아직 구현되지 않았습니다.", isError: true)
        case "invite_agent":
            return await executeInviteAgent(call, context: context)
        case "list_agents":
            return await executeListAgents(call, context: context)
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

    // MARK: - file_read

    private static func executeFileRead(_ call: ToolCall) async -> ToolResult {
        guard let path = call.arguments["path"]?.stringValue else {
            return ToolResult(callID: call.id, content: "path 파라미터가 필요합니다.", isError: true)
        }
        guard isPathAllowed(path) else {
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

    private static func executeFileWrite(_ call: ToolCall) async -> ToolResult {
        guard let path = call.arguments["path"]?.stringValue else {
            return ToolResult(callID: call.id, content: "path 파라미터가 필요합니다.", isError: true)
        }
        guard isPathAllowed(path) else {
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
            return ToolResult(callID: call.id, content: "파일 저장 완료: \(path) (\(content.count)자)", isError: false)
        } catch {
            return ToolResult(callID: call.id, content: "파일 쓰기 실패: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - shell_exec

    private static func executeShellExec(_ call: ToolCall) async -> ToolResult {
        guard let command = call.arguments["command"]?.stringValue else {
            return ToolResult(callID: call.id, content: "command 파라미터가 필요합니다.", isError: true)
        }
        let workDir = call.arguments["working_directory"]?.stringValue

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]

                if let dir = workDir {
                    process.currentDirectoryURL = URL(fileURLWithPath: dir)
                }

                // 환경 변수 상속
                var env = ProcessInfo.processInfo.environment
                let homePath = env["HOME"] ?? "/Users/\(NSUserName())"

                // nvm: 동적으로 최신 버전 탐색
                var additionalPaths: [String] = []
                let nvmDir = "\(homePath)/.nvm/versions/node"
                if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
                    let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                    for version in sorted {
                        additionalPaths.append("\(nvmDir)/\(version)/bin")
                    }
                }
                additionalPaths.append(contentsOf: [
                    "/opt/homebrew/bin",
                    "/usr/local/bin"
                ])

                if let existingPath = env["PATH"] {
                    env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath
                }
                process.environment = env

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let exitCode = process.terminationStatus

                    var output = ""
                    if !stdout.isEmpty { output += stdout }
                    if !stderr.isEmpty { output += (output.isEmpty ? "" : "\n") + "stderr: " + stderr }
                    if output.isEmpty { output = "(출력 없음)" }

                    // 출력 크기 제한
                    let maxLen = 30_000
                    if output.count > maxLen {
                        output = String(output.prefix(maxLen)) + "\n... (출력이 잘렸습니다)"
                    }

                    output += "\n[종료 코드: \(exitCode)]"

                    continuation.resume(returning: ToolResult(
                        callID: call.id,
                        content: output,
                        isError: exitCode != 0
                    ))
                } catch {
                    continuation.resume(returning: ToolResult(
                        callID: call.id,
                        content: "명령 실행 실패: \(error.localizedDescription)",
                        isError: true
                    ))
                }
            }
        }
    }
}
