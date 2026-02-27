import Foundation

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
        let claudePath = config.baseURL

        let lastUserMessage = messages.last(where: { $0.role == "user" })?.content ?? ""

        var fullPrompt = ""
        if !systemPrompt.isEmpty {
            fullPrompt += "[시스템 지시]\n\(systemPrompt)\n\n"
        }

        let history = messages.dropLast()
        if !history.isEmpty {
            fullPrompt += "[이전 대화]\n"
            for msg in history.suffix(10) {
                let label = msg.role == "user" ? "사용자" : "어시스턴트"
                fullPrompt += "\(label): \(msg.content)\n"
            }
            fullPrompt += "\n"
        }

        fullPrompt += lastUserMessage

        return try await runClaude(path: claudePath, prompt: fullPrompt, model: model)
    }

    private func runClaude(path: String, prompt: String, model: String) async throws -> String {
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

        let result = await ProcessRunner.run(
            executable: executable,
            args: args,
            env: env,
            workDir: homePath
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
}
