import Foundation

/// Claude Code CLI 설치 및 검증 유틸리티
@MainActor
class ClaudeCodeInstaller: ObservableObject {

    enum InstallState: Equatable {
        case checking
        case found(path: String)
        case notFound
        case installing(step: String)
        case needsAuth
        case ready
        case failed(String)

        static func == (lhs: InstallState, rhs: InstallState) -> Bool {
            switch (lhs, rhs) {
            case (.checking, .checking): return true
            case (.found(let a), .found(let b)): return a == b
            case (.notFound, .notFound): return true
            case (.installing(let a), .installing(let b)): return a == b
            case (.needsAuth, .needsAuth): return true
            case (.ready, .ready): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    @Published var state: InstallState = .checking
    @Published var installLog: String = ""

    /// Claude Code가 설치되어 있으며 사용 가능한 상태인지
    var isReady: Bool {
        if case .ready = state { return true }
        if case .found = state { return true }
        return false
    }

    /// 감지된 Claude Code 바이너리 경로
    var detectedPath: String? {
        if case .found(let path) = state { return path }
        if case .ready = state { return ClaudeCodeProvider.findClaudePath() }
        return nil
    }

    // MARK: - 감지

    func detect() async {
        state = .checking
        let path = ClaudeCodeProvider.findClaudePath()

        if FileManager.default.isExecutableFile(atPath: path) {
            // 바이너리 있음 → 인증 상태 확인
            if checkAuthStatus() {
                state = .ready
            } else {
                state = .found(path: path)
            }
        } else {
            state = .notFound
        }
    }

    // MARK: - 설치

    func install() async {
        state = .installing(step: "npm 확인 중...")
        installLog = ""

        // 1. npm 경로 찾기
        let npmPath = findExecutable("npm")

        if let npmPath {
            // npm이 있으면 바로 설치
            await installWithNpm(npmPath)
        } else {
            // npm이 없으면 brew로 node 설치 시도
            let brewPath = findExecutable("brew")
            if let brewPath {
                state = .installing(step: "Node.js 설치 중 (Homebrew)...")
                let brewResult = await runProcess(brewPath, arguments: ["install", "node"])
                if !brewResult.success {
                    state = .failed("Node.js 설치 실패: \(brewResult.output.suffix(200))")
                    return
                }

                // brew 설치 후 npm 재탐색
                if let newNpmPath = findExecutable("npm") {
                    await installWithNpm(newNpmPath)
                } else {
                    state = .failed("Node.js 설치 후 npm을 찾을 수 없습니다")
                }
            } else {
                state = .failed("Node.js가 필요합니다.\nnodejs.org에서 설치하거나,\nHomebrew (brew.sh) 설치 후 다시 시도하세요.")
            }
        }
    }

    private func installWithNpm(_ npmPath: String) async {
        state = .installing(step: "Claude Code 설치 중...")
        let result = await runProcess(npmPath, arguments: ["install", "-g", "@anthropic-ai/claude-code"])
        installLog = result.output

        if result.success {
            // 설치 후 바이너리 확인
            let path = ClaudeCodeProvider.findClaudePath()
            if FileManager.default.isExecutableFile(atPath: path) {
                if checkAuthStatus() {
                    state = .ready
                } else {
                    state = .needsAuth
                }
            } else {
                state = .failed("설치는 완료되었으나 claude 바이너리를 찾을 수 없습니다")
            }
        } else {
            state = .failed("설치 실패:\n\(result.output.suffix(300))")
        }
    }

    // MARK: - 인증 확인

    /// ~/.claude/ 디렉토리의 존재로 인증 여부 추정
    func checkAuthStatus() -> Bool {
        let claudeDir = NSHomeDirectory() + "/.claude"
        return FileManager.default.fileExists(atPath: claudeDir)
    }

    /// 인증 완료로 전환 (수동 확인 후)
    func confirmAuth() {
        state = .ready
    }

    // MARK: - 프로세스 실행

    private func runProcess(_ executablePath: String, arguments: [String]) async -> (success: Bool, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments

                // PATH 보강
                var env = ProcessInfo.processInfo.environment
                let homePath = env["HOME"] ?? NSHomeDirectory()
                var paths = ["/opt/homebrew/bin", "/usr/local/bin"]
                let nvmDir = "\(homePath)/.nvm/versions/node"
                if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
                    let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                    for version in sorted {
                        paths.insert("\(nvmDir)/\(version)/bin", at: 0)
                    }
                }
                let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                env["PATH"] = paths.joined(separator: ":") + ":" + existing
                process.environment = env
                process.currentDirectoryURL = URL(fileURLWithPath: homePath)

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errData, encoding: .utf8) ?? ""

                    let combined = (output + "\n" + errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (process.terminationStatus == 0, combined))
                } catch {
                    continuation.resume(returning: (false, error.localizedDescription))
                }
            }
        }
    }

    // MARK: - 유틸리티

    /// 실행 가능한 바이너리 경로 찾기
    private func findExecutable(_ name: String) -> String? {
        let homePath = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]

        // nvm 경로도 탐색
        let nvmDir = "\(homePath)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                candidates.insert("\(nvmDir)/\(version)/bin/\(name)", at: 0)
            }
        }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
