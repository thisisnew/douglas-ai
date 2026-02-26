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
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [timeoutSeconds] in
                let process = Process()

                // claude CLI는 Node.js 스크립트 → 같은 디렉토리의 node를 직접 사용
                if let nodePath = ClaudeCodeProvider.findNodePath(forClaude: path) {
                    process.executableURL = URL(fileURLWithPath: nodePath)
                    process.arguments = [path, "-p", prompt, "--model", model]
                } else {
                    process.executableURL = URL(fileURLWithPath: path)
                    process.arguments = ["-p", prompt, "--model", model]
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
                process.environment = env
                // 작업 디렉토리를 홈으로 설정 — macOS 디렉토리 접근 허락 다이얼로그 방지
                process.currentDirectoryURL = URL(fileURLWithPath: homePath)

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()

                    // 타임아웃 감시
                    let timer = DispatchSource.makeTimerSource(queue: .global())
                    timer.schedule(deadline: .now() + timeoutSeconds)
                    timer.setEventHandler {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    timer.resume()

                    process.waitUntilExit()
                    timer.cancel()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus == 15 {
                        // SIGTERM (타임아웃)
                        continuation.resume(throwing: AIProviderError.apiError("Claude Code 응답 시간 초과 (\(Int(timeoutSeconds))초)"))
                    } else if process.terminationStatus != 0 {
                        let msg = errorOutput.isEmpty ? "Claude Code 실행 실패 (코드: \(process.terminationStatus))" : errorOutput
                        continuation.resume(throwing: AIProviderError.apiError(msg))
                    } else if output.isEmpty {
                        continuation.resume(throwing: AIProviderError.invalidResponse)
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: AIProviderError.networkError("Claude Code를 실행할 수 없습니다: \(error.localizedDescription)"))
                }
            }
        }
    }
}
