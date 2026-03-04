import Foundation

/// Claude Code stream-json NDJSON 이벤트를 실시간 파싱하여 도구 활동 추적
private final class StreamJsonHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var _resultText = ""
    private let onActivity: (String, ToolActivityDetail?) -> Void

    var resultText: String { lock.withLock { _resultText } }

    init(onActivity: @escaping (String, ToolActivityDetail?) -> Void) {
        self.onActivity = onActivity
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

        if type == "assistant", let message = json["message"] as? [String: Any] {
            if message["type"] as? String == "tool_use" {
                let toolName = message["name"] as? String ?? "unknown"
                let input = message["input"] as? [String: Any]
                let subject = Self.extractSubject(toolName: toolName, input: input)
                let label = "도구 사용: \(toolName)\(subject.map { " → \($0)" } ?? "")"
                let detail = ToolActivityDetail(
                    toolName: toolName, subject: subject,
                    contentPreview: nil, isError: false
                )
                onActivity(label, detail)
            }
        } else if type == "result", let resultText = json["result"] as? String {
            lock.lock()
            _resultText = resultText
            lock.unlock()
        }
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

    /// 시스템에서 claude CLI 경로를 자동으로 찾는다
    static func findClaudePath() -> String {
        let homePath = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(homePath)/.local/bin/claude"
        ]

        // nvm: 현재 활성 버전을 동적으로 탐색 (하드코딩 방지)
        let nvmDir = "\(homePath)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                candidates.insert("\(nvmDir)/\(version)/bin/claude", at: 0)
            }
        }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "claude"
    }

    /// claude 바이너리와 같은 디렉토리에 있는 node 경로를 찾는다
    private static func findNodePath(forClaude claudePath: String) -> String? {
        let claudeDir = (claudePath as NSString).deletingLastPathComponent
        let nodePath = (claudeDir as NSString).appendingPathComponent("node")
        if FileManager.default.isExecutableFile(atPath: nodePath) {
            return nodePath
        }
        return nil
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

    /// 프로젝트 경로를 작업 디렉토리로 사용하는 sendMessage (도구 활동 추적 지원)
    func sendMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        workingDirectory: String?,
        onToolActivity: ((String, ToolActivityDetail?) -> Void)? = nil
    ) async throws -> String {
        let userPrompt = buildUserPrompt(from: messages)
        return try await runClaude(
            path: config.baseURL, prompt: userPrompt, model: model,
            systemPrompt: systemPrompt, disallowedTools: ["WebFetch"],
            workingDirectory: workingDirectory,
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
                userPrompt += "\(label): \(msg.content)\n"
            }
            userPrompt += "\n"
        }
        userPrompt += lastUserMessage
        return userPrompt
    }

    private func runClaude(
        path: String, prompt: String, model: String,
        systemPrompt: String = "", disableTools: Bool = false,
        disallowedTools: [String] = [],
        workingDirectory: String? = nil,
        onToolActivity: ((String, ToolActivityDetail?) -> Void)? = nil
    ) async throws -> String {
        // claude CLI는 Node.js 스크립트 → 같은 디렉토리의 node를 직접 사용
        let executable: String
        var args: [String]
        if let nodePath = ClaudeCodeProvider.findNodePath(forClaude: path) {
            executable = nodePath
            args = [path, "-p", prompt, "--model", model]
        } else {
            executable = path
            args = ["-p", prompt, "--model", model]
        }

        // 시스템 프롬프트가 있으면 --system-prompt로 분리 전달
        if !systemPrompt.isEmpty {
            args += ["--system-prompt", systemPrompt]
        }

        // 라우터 모드: 내장 도구 비활성화 (URL 직접 접근/파일 조작 방지)
        if disableTools {
            args += ["--tools", ""]
        }

        // 특정 도구만 선택적으로 차단 (바이브코딩 유지하면서 WebFetch 등 차단)
        for tool in disallowedTools {
            args += ["--disallowed-tools", tool]
        }

        // 도구 활동 추적 모드: stream-json NDJSON 출력
        let useStreaming = onToolActivity != nil
        if useStreaming {
            args += ["--output-format", "stream-json"]
        }

        // 환경변수 상속
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")

        let homePath = env["HOME"] ?? NSHomeDirectory()
        var additionalPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        let nvmDir = "\(homePath)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                additionalPaths.insert("\(nvmDir)/\(version)/bin", at: 0)
            }
        }
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath

        let effectiveWorkDir = workingDirectory ?? homePath

        // 스트리밍 모드: NDJSON 실시간 파싱으로 도구 활동 추적
        if useStreaming, let onToolActivity {
            let handler = StreamJsonHandler(onActivity: onToolActivity)
            let result = await ProcessRunner.runStreaming(
                executable: executable, args: args, env: env,
                workDir: effectiveWorkDir,
                onOutput: { chunk in handler.feed(chunk) }
            )

            // stream-json result 이벤트에서 최종 텍스트 추출
            let finalText = handler.resultText
            if !finalText.isEmpty {
                return finalText
            }

            // 폴백: stdout NDJSON에서 result 이벤트 재파싱
            if let parsed = Self.extractResultFromNdjson(result.stdout) {
                return parsed
            }

            if result.exitCode == 15 {
                throw AIProviderError.apiError("Claude Code 응답 시간 초과 (\(Int(timeoutSeconds))초)")
            } else if result.exitCode != 0 {
                let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw AIProviderError.apiError(msg.isEmpty ? "Claude Code 실행 실패 (코드: \(result.exitCode))" : msg)
            }
            throw AIProviderError.invalidResponse
        }

        // 일반 모드: 기존 동작
        let result = await ProcessRunner.run(
            executable: executable,
            args: args,
            env: env,
            workDir: effectiveWorkDir
        )

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorOutput = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.exitCode == 15 {
            // SIGTERM (타임아웃)
            throw AIProviderError.apiError("Claude Code 응답 시간 초과 (\(Int(timeoutSeconds))초)")
        } else if result.exitCode != 0 {
            let msg = errorOutput.isEmpty ? "Claude Code 실행 실패 (코드: \(result.exitCode))" : errorOutput
            throw AIProviderError.apiError(msg)
        } else if output.isEmpty {
            throw AIProviderError.invalidResponse
        }
        return output
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
