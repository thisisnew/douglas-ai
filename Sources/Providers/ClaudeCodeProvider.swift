import Foundation
import os.log

private let cliLogger = Logger(subsystem: "com.douglas.app", category: "ClaudeCLI")

/// Claude Code stream-json NDJSON 이벤트를 실시간 파싱하여 도구 활동 + 텍스트 스트리밍 추적
private final class StreamJsonHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var _resultText = ""
    /// 누적된 어시스턴트 텍스트 (partial message 포함)
    private var _streamedText = ""
    private let onActivity: (String, ToolActivityDetail?) -> Void
    /// 텍스트 청크 콜백 (sendMessageStreaming용)
    private let onTextChunk: (@Sendable (String) -> Void)?

    var resultText: String { lock.withLock { _resultText } }
    var streamedText: String { lock.withLock { _streamedText } }

    init(
        onActivity: @escaping (String, ToolActivityDetail?) -> Void,
        onTextChunk: (@Sendable (String) -> Void)? = nil
    ) {
        self.onActivity = onActivity
        self.onTextChunk = onTextChunk
    }

    func feed(_ chunk: String) {
        lock.lock()
        buffer += chunk
        while let idx = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<idx])
            buffer = String(buffer[buffer.index(after: idx)...])
            lock.unlock()
            processLine(line)
            lock.lock()
        }
        lock.unlock()
    }

    private func processLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let type = json["type"] as? String

        // 1) tool_use 이벤트: {"type": "tool_use", "tool": {"name": "Read", "input": {...}}}
        if type == "tool_use", let tool = json["tool"] as? [String: Any] {
            emitToolUse(tool)
        }
        // 2) assistant 메시지: content 배열 안에 tool_use + text가 포함될 수 있음
        else if type == "assistant", let message = json["message"] as? [String: Any] {
            // 직접 tool_use인 경우 (레거시 형식)
            if message["type"] as? String == "tool_use" {
                emitToolUse(message)
            }
            // content 배열에서 tool_use + text 추출
            if let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if item["type"] as? String == "tool_use" {
                        emitToolUse(item)
                    } else if item["type"] as? String == "text",
                              let text = item["text"] as? String,
                              let onTextChunk {
                        // 텍스트 스트리밍: 전체 누적 텍스트를 콜백으로 전달
                        lock.lock()
                        _streamedText = text
                        lock.unlock()
                        onTextChunk(text)
                    }
                }
            }
        }
        // 3) result 이벤트
        else if type == "result" {
            let resultText = json["result"] as? String
                ?? (json["result"] as? [String: Any])?["text"] as? String
            if let resultText {
                lock.lock()
                _resultText = resultText
                lock.unlock()
            }
        }
        // 4) error 이벤트
        else if type == "error" {
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String
                ?? json["error"] as? String
                ?? "알 수 없는 오류"
            let detail = ToolActivityDetail(
                toolName: "error", subject: errorMsg,
                contentPreview: nil, isError: true
            )
            onActivity("오류: \(errorMsg)", detail)
        }
    }

    /// tool_use JSON 객체에서 활동 이벤트 방출
    private func emitToolUse(_ tool: [String: Any]) {
        let toolName = tool["name"] as? String ?? "unknown"
        // Claude Code 내부 도구 필터링 (UI에 표시하지 않음)
        let internalTools: Set<String> = ["ToolSearch", "Agent", "TodoRead", "TodoWrite", "EnterPlanMode", "ExitPlanMode", "NotebookEdit"]
        guard !internalTools.contains(toolName) else { return }
        let input = tool["input"] as? [String: Any]
        let subject = Self.extractSubject(toolName: toolName, input: input)
        let preview = Self.extractContentPreview(toolName: toolName, input: input)
        let displayName = ToolActivityDetail(toolName: toolName, subject: nil, contentPreview: nil, isError: false).displayName
        let label = "\(displayName)\(subject.map { " → \($0)" } ?? "")"
        let detail = ToolActivityDetail(
            toolName: toolName, subject: subject,
            contentPreview: preview, isError: false
        )
        onActivity(label, detail)
    }

    private static func extractSubject(toolName: String, input: [String: Any]?) -> String? {
        guard let input else { return nil }
        switch toolName {
        case "Read", "file_read":
            return input["file_path"] as? String ?? input["path"] as? String
        case "Write", "file_write":
            return input["file_path"] as? String ?? input["path"] as? String
        case "Edit":
            return input["file_path"] as? String
        case "Bash", "shell_exec":
            let cmd = input["command"] as? String ?? ""
            return cmd.count > 80 ? String(cmd.prefix(77)) + "..." : cmd
        case "Glob":
            return input["pattern"] as? String
        case "Grep":
            return input["pattern"] as? String
        case "WebFetch", "web_fetch":
            return input["url"] as? String
        case "WebSearch", "web_search":
            return input["query"] as? String
        default:
            return nil
        }
    }

    /// tool_use input에서 상세 미리보기 추출 (최대 500자)
    private static func extractContentPreview(toolName: String, input: [String: Any]?) -> String? {
        guard let input else { return nil }
        let maxLen = 500

        switch toolName {
        case "Bash", "shell_exec":
            // 긴 명령어의 전체 텍스트 표시
            guard let cmd = input["command"] as? String, cmd.count > 80 else { return nil }
            return String(cmd.prefix(maxLen))

        case "Edit":
            // old_string → new_string 변경 내용
            let old = input["old_string"] as? String ?? ""
            let new = input["new_string"] as? String ?? ""
            guard !old.isEmpty || !new.isEmpty else { return nil }
            let oldPreview = old.count > 200 ? String(old.prefix(197)) + "..." : old
            let newPreview = new.count > 200 ? String(new.prefix(197)) + "..." : new
            return "- \(oldPreview)\n+ \(newPreview)"

        case "Write", "file_write":
            // 작성할 내용의 첫 부분
            guard let content = input["content"] as? String, !content.isEmpty else { return nil }
            let lines = content.components(separatedBy: "\n").prefix(10)
            let preview = lines.joined(separator: "\n")
            return preview.count > maxLen ? String(preview.prefix(maxLen - 3)) + "..." : preview

        case "Grep":
            // 검색 패턴 + 경로 + 타입 종합
            var parts: [String] = []
            if let pattern = input["pattern"] as? String { parts.append("패턴: \(pattern)") }
            if let path = input["path"] as? String { parts.append("경로: \(path)") }
            if let glob = input["glob"] as? String { parts.append("필터: \(glob)") }
            if let type = input["type"] as? String { parts.append("타입: \(type)") }
            return parts.count > 1 ? parts.joined(separator: "\n") : nil

        case "Read", "file_read":
            // offset/limit가 있으면 표시
            let offset = input["offset"] as? Int
            let limit = input["limit"] as? Int
            if let o = offset, let l = limit {
                return "범위: \(o)행부터 \(l)줄"
            } else if let o = offset {
                return "시작: \(o)행부터"
            } else if let l = limit {
                return "제한: \(l)줄"
            }
            return nil

        case "WebSearch", "web_search":
            // 검색 쿼리 + 도메인 필터
            var parts: [String] = []
            if let domains = input["allowed_domains"] as? [String], !domains.isEmpty {
                parts.append("도메인: \(domains.joined(separator: ", "))")
            }
            if let blocked = input["blocked_domains"] as? [String], !blocked.isEmpty {
                parts.append("제외: \(blocked.joined(separator: ", "))")
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")

        default:
            return nil
        }
    }
}

// MARK: - 경로 해석 (인프라 계층)

/// CLI 실행에 필요한 경로 정보
private struct ResolvedExecutable {
    let claudePath: String
    let nodePath: String?  // nil이면 shebang 사용

    /// 실제 실행할 바이너리 경로
    var executable: String { nodePath ?? claudePath }

    /// CLI 인자 (node 직접 실행 시 cli.js 경로 포함)
    func baseArgs(prompt: String, model: String) -> [String] {
        if let nodePath {
            let resolvedClaude = ClaudeCodeProvider.resolveSymlink(claudePath)
            cliLogger.info("node 직접 실행: \(nodePath, privacy: .public) \(resolvedClaude, privacy: .public)")
            return [resolvedClaude, "-p", prompt, "--model", model]
        }
        return ["-p", prompt, "--model", model]
    }
}

/// 이미 설치된 Claude Code CLI를 활용하는 프로바이더
/// API 키 불필요 - 기존 claude 로그인 세션을 그대로 사용
class ClaudeCodeProvider: AIProvider {
    let config: ProviderConfig

    /// 프로세스 타임아웃 (초)
    private let timeoutSeconds: Double = 120

    init(config: ProviderConfig) {
        self.config = config
    }

    // MARK: - 경로 탐색 (단일 진실 공급원)

    /// claude CLI 경로와 node 경로를 함께 해석 (v18 체크 통합)
    /// 우선순위: nvm(v18+) → homebrew → 시스템 → 폴백("claude")
    private static func resolveExecutable() -> ResolvedExecutable {
        let homePath = NSHomeDirectory()

        // 1. nvm 경로 검색 (v18+ 필터링)
        for binPath in ShellEnvironment.nvmBinPaths {
            let claudePath = "\(binPath)/claude"
            guard FileManager.default.isExecutableFile(atPath: claudePath) else { continue }

            let nodePath = (binPath as NSString).appendingPathComponent("node")
            guard FileManager.default.isExecutableFile(atPath: nodePath) else { continue }

            // v18 미만 건너뛰기
            if let major = nodeVersion(at: nodePath), major < 18 {
                cliLogger.info("nvm 건너뜀 (node v\(major) < 18): \(claudePath, privacy: .public)")
                continue
            }

            return ResolvedExecutable(claudePath: claudePath, nodePath: nodePath)
        }

        // 2. homebrew/시스템 경로 검색
        let systemCandidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(homePath)/.local/bin/claude"
        ]

        for claudePath in systemCandidates {
            guard FileManager.default.isExecutableFile(atPath: claudePath) else { continue }
            // homebrew/시스템 경로는 shebang에 의존 (nodePath = nil)
            return ResolvedExecutable(claudePath: claudePath, nodePath: nil)
        }

        // 3. 폴백
        return ResolvedExecutable(claudePath: "claude", nodePath: nil)
    }

    /// 시스템에서 claude CLI 경로를 자동으로 찾는다 (외부 호출부 호환성 유지)
    static func findClaudePath() -> String {
        return resolveExecutable().claudePath
    }

    /// node 바이너리의 major 버전 추출 (v22.21.1 → 22)
    private static func nodeVersion(at nodePath: String) -> Int? {
        // nvm 경로에서 버전 추출: .../node/v22.21.1/bin/node
        let components = nodePath.components(separatedBy: "/")
        for comp in components {
            if comp.hasPrefix("v"), let dot = comp.dropFirst().firstIndex(of: ".") {
                return Int(comp[comp.index(after: comp.startIndex)..<dot])
            }
        }
        return nil // 버전 추출 불가 시 사용 허용
    }

    /// symlink를 해석하여 실제 파일 경로 반환
    fileprivate static func resolveSymlink(_ path: String) -> String {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return path
        }
        if dest.hasPrefix("/") {
            return dest
        }
        // 상대 경로: claude가 있는 디렉토리 기준으로 해석
        return ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(dest)
    }

    func fetchModels() async throws -> [String] {
        return [
            "claude-opus-4-6",
            "claude-sonnet-4-6",
            "claude-haiku-4-5"
        ]
    }

    func sendMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)]
    ) async throws -> String {
        let userPrompt = buildUserPrompt(from: messages)
        return try await runClaude(
            path: config.baseURL, prompt: userPrompt, model: model,
            systemPrompt: systemPrompt, disallowedTools: ["WebFetch"]
        )
    }

    /// 프로젝트 경로를 작업 디렉토리로 사용하는 sendMessage (도구 활동 추적 + 텍스트 스트리밍 지원)
    func sendMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        workingDirectory: String?,
        onToolActivity: ((String, ToolActivityDetail?) -> Void)? = nil,
        onTextChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let userPrompt = buildUserPrompt(from: messages)
        return try await runClaude(
            path: config.baseURL, prompt: userPrompt, model: model,
            systemPrompt: systemPrompt, disallowedTools: ["WebFetch"],
            workingDirectory: workingDirectory,
            onToolActivity: onToolActivity,
            onTextChunk: onTextChunk
        )
    }

    /// 스트리밍 지원: stream-json + --include-partial-messages로 실시간 텍스트 스트리밍
    var supportsStreaming: Bool { true }

    func sendMessageStreaming(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let userPrompt = buildUserPrompt(from: messages)
        return try await runClaude(
            path: config.baseURL, prompt: userPrompt, model: model,
            systemPrompt: systemPrompt, disallowedTools: ["WebFetch"],
            onToolActivity: { _, _ in },  // 스트리밍 모드 활성화 (stream-json 사용)
            onTextChunk: onChunk
        )
    }

    /// 도구 제한이 가능한 스트리밍 모드 (allowedTools로 CLI 도구 필터링 + 도구 활동 추적)
    func sendMessageStreamingWithTools(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        allowedTools: [String],
        workingDirectory: String? = nil,
        onToolActivity: ((String, ToolActivityDetail?) -> Void)? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let userPrompt = buildUserPrompt(from: messages)
        return try await runClaude(
            path: config.baseURL, prompt: userPrompt, model: model,
            systemPrompt: systemPrompt,
            allowedTools: allowedTools,
            workingDirectory: workingDirectory,
            onToolActivity: onToolActivity ?? { _, _ in },
            onTextChunk: onChunk
        )
    }

    /// 검색 허용 모드: WebSearch를 allowedTools에 포함
    func sendMessageWithSearch(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        onToolActivity: ((String, ToolActivityDetail?) -> Void)? = nil
    ) async throws -> String {
        let userPrompt = buildUserPrompt(from: messages)
        return try await runClaude(
            path: config.baseURL, prompt: userPrompt, model: model,
            systemPrompt: systemPrompt,
            allowedTools: ["Read", "WebSearch", "WebFetch"],
            onToolActivity: onToolActivity
        )
    }

    /// 이미지 첨부를 파일 경로로 변환하여 CLI에 전달
    func sendMessageWithTools(
        model: String,
        systemPrompt: String,
        messages: [ConversationMessage],
        tools: [AgentTool]
    ) async throws -> AIResponseContent {
        let simpleMsgs = messages
            .filter { $0.role != "tool" }
            .compactMap { msg -> (role: String, content: String)? in
                var text = msg.content ?? ""
                if let attachments = msg.attachments, !attachments.isEmpty {
                    let paths = attachments.map { $0.diskPath.path }
                    text += "\n\n[첨부 이미지 — 아래 경로의 파일을 Read 도구로 확인하세요]\n" + paths.joined(separator: "\n")
                }
                guard !text.isEmpty else { return nil }
                return (role: msg.role, content: text)
            }
        let result = try await sendMessage(
            model: model, systemPrompt: systemPrompt, messages: simpleMsgs
        )
        return .text(result)
    }

    /// 라우터 전용: CLI 내장 도구 비활성화 (URL 직접 접근 방지)
    func sendRouterMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)]
    ) async throws -> String {
        let userPrompt = buildUserPrompt(from: messages)
        return try await runClaude(
            path: config.baseURL, prompt: userPrompt, model: model,
            systemPrompt: systemPrompt, disableTools: true
        )
    }

    private func buildUserPrompt(from messages: [(role: String, content: String)]) -> String {
        let lastUserMessage = messages.last(where: { $0.role == "user" })?.content ?? ""
        var userPrompt = ""
        let history = messages.dropLast()
        if !history.isEmpty {
            userPrompt += "[이전 대화]\n"
            for msg in history.suffix(10) {
                let label = msg.role == "user" ? "사용자" : "어시스턴트"
                let truncated = msg.content.count > 500
                    ? String(msg.content.prefix(500)) + "…"
                    : msg.content
                userPrompt += "\(label): \(truncated)\n"
            }
            userPrompt += "\n"
        }
        userPrompt += lastUserMessage
        return userPrompt
    }

    // MARK: - CLI 실행 헬퍼 (Step 2: runClaude 분해)

    /// CLI 인자 구성 (도구/시스템 프롬프트/스트리밍 설정)
    private func buildCLIArguments(
        baseArgs: [String],
        systemPrompt: String,
        disableTools: Bool,
        allowedTools: [String]?,
        disallowedTools: [String],
        useStreaming: Bool,
        includePartialMessages: Bool
    ) -> [String] {
        var args = baseArgs

        // 라우터 모드: 내장 도구 비활성화 + 시스템 프롬프트 교체
        if disableTools {
            if !systemPrompt.isEmpty {
                args += ["--system-prompt", systemPrompt]
            }
            // 도구 비활성화: 빈 allowedTools 목록 사용
            args += ["--allowedTools"]
        } else {
            // 에이전트 모드: Claude Code 기본 프롬프트 유지 + 페르소나 추가
            if !systemPrompt.isEmpty {
                args += ["--append-system-prompt", systemPrompt]
            }
            var tools = allowedTools ?? ["Edit", "Write", "Bash", "Read", "Glob", "Grep", "WebSearch"]
            if !tools.contains(where: { $0.hasPrefix("mcp__") }) {
                tools.append("mcp__*")
            }
            args += ["--allowedTools"] + tools
            cliLogger.info("CLI tools: \(tools, privacy: .public)")
        }

        // 특정 도구 차단
        for tool in disallowedTools {
            args += ["--disallowedTools", tool]
        }

        // 스트리밍 모드 설정
        if useStreaming {
            args += ["--output-format", "stream-json", "--verbose"]
            if includePartialMessages {
                args += ["--include-partial-messages"]
            }
        }

        return args
    }

    /// 환경변수 구성 (PATH에 nvm/homebrew 추가)
    private func buildEnvironment(workingDirectory: String?) -> (env: [String: String], workDir: String) {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")

        let homePath = env["HOME"] ?? NSHomeDirectory()
        var additionalPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

        let nvmDir = "\(homePath)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                additionalPaths.insert("\(nvmDir)/\(version)/bin", at: 0)
            }
        }

        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath

        return (env, workingDirectory ?? homePath)
    }

    /// 프로세스 실행 및 결과 파싱
    private func executeAndParse(
        executable: String,
        args: [String],
        env: [String: String],
        workDir: String,
        useStreaming: Bool,
        onToolActivity: ((String, ToolActivityDetail?) -> Void)?,
        onTextChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        // 스트리밍 모드
        if useStreaming {
            let activityHandler = onToolActivity ?? { _, _ in }
            let handler = StreamJsonHandler(onActivity: activityHandler, onTextChunk: onTextChunk)
            let result = await ProcessRunner.runStreaming(
                executable: executable, args: args, env: env,
                workDir: workDir,
                onOutput: { chunk in handler.feed(chunk) }
            )

            if !handler.resultText.isEmpty {
                return handler.resultText
            }
            if let parsed = Self.extractResultFromNdjson(result.stdout) {
                return parsed
            }

            if result.exitCode == 15 {
                throw AIProviderError.apiError("Claude Code 응답 시간 초과 (\(Int(timeoutSeconds))초)")
            } else if result.exitCode != 0 {
                let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                cliLogger.error("CLI 에러 (streaming, exit=\(result.exitCode)): \(msg.suffix(300), privacy: .public)")
                throw AIProviderError.apiError(msg.isEmpty ? "Claude Code 실행 실패 (코드: \(result.exitCode))" : msg)
            }
            throw AIProviderError.invalidResponse
        }

        // 일반 모드
        let result = await ProcessRunner.run(
            executable: executable, args: args, env: env, workDir: workDir
        )

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorOutput = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.exitCode == 15 {
            throw AIProviderError.apiError("Claude Code 응답 시간 초과 (\(Int(timeoutSeconds))초)")
        } else if result.exitCode != 0 {
            let msg = errorOutput.isEmpty ? "Claude Code 실행 실패 (코드: \(result.exitCode))" : errorOutput
            cliLogger.error("CLI 에러 (normal, exit=\(result.exitCode)): \(msg.suffix(300), privacy: .public)")
            throw AIProviderError.apiError(msg)
        } else if output.isEmpty {
            throw AIProviderError.invalidResponse
        }
        return output
    }

    private func runClaude(
        path: String, prompt: String, model: String,
        systemPrompt: String = "", disableTools: Bool = false,
        disallowedTools: [String] = [],
        allowedTools: [String]? = nil,
        workingDirectory: String? = nil,
        onToolActivity: ((String, ToolActivityDetail?) -> Void)? = nil,
        onTextChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        cliLogger.info("runClaude: model=\(model, privacy: .public) disableTools=\(disableTools) prompt=\(prompt.count)자 system=\(systemPrompt.count)자")

        // 1. 경로 해석
        let exe = Self.resolveExecutable()

        // 2. 스트리밍 여부 결정
        let useStreaming = onToolActivity != nil || onTextChunk != nil

        // 3. CLI 인자 구성
        let args = buildCLIArguments(
            baseArgs: exe.baseArgs(prompt: prompt, model: model),
            systemPrompt: systemPrompt,
            disableTools: disableTools,
            allowedTools: allowedTools,
            disallowedTools: disallowedTools,
            useStreaming: useStreaming,
            includePartialMessages: onTextChunk != nil
        )

        // 4. 환경변수 구성
        let (env, workDir) = buildEnvironment(workingDirectory: workingDirectory)

        // 5. 실행 및 결과 파싱
        return try await executeAndParse(
            executable: exe.executable,
            args: args,
            env: env,
            workDir: workDir,
            useStreaming: useStreaming,
            onToolActivity: onToolActivity,
            onTextChunk: onTextChunk
        )
    }

    /// NDJSON stdout에서 마지막 result 이벤트의 텍스트 추출
    private static func extractResultFromNdjson(_ output: String) -> String? {
        for line in output.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "result",
                  let result = json["result"] as? String else {
                continue
            }
            return result
        }
        return nil
    }
}
