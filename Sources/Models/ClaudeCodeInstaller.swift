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

        // 1단계: 하드코딩 경로 동기 체크 (즉시 완료, 메인 스레드에서)
        let quickPath = ClaudeCodeProvider.findClaudePath()
        if quickPath != "claude", FileManager.default.isExecutableFile(atPath: quickPath) {
            if checkAuthStatus() {
                state = .ready
            } else {
                state = .found(path: quickPath)
            }
            return
        }

        // 2단계: 셸 탐색 (백그라운드, 5초 타임아웃)
        let foundPath: String? = await Self.findClaudeInBackground()

        if let path = foundPath {
            if checkAuthStatus() {
                state = .ready
            } else {
                state = .found(path: path)
            }
        } else {
            state = .notFound
        }
    }

    /// 백그라운드에서 claude 바이너리 탐색 (5초 타임아웃)
    private static func findClaudeInBackground() async -> String? {
        await withTaskGroup(of: String?.self) { group in
            // 실제 탐색
            group.addTask {
                // 1. 하드코딩 경로 확인
                let path = ClaudeCodeProvider.findClaudePath()
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }

                // 2. 로그인 셸 which 폴백
                let result = await ProcessRunner.run(
                    executable: "/bin/zsh",
                    args: ["-l", "-c", "command -v claude"]
                )
                let found = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.exitCode == 0, !found.isEmpty,
                   FileManager.default.isExecutableFile(atPath: found) {
                    return found
                }
                return nil
            }
            // 타임아웃
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
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

    /// Claude Code 인증 여부 확인 — 디렉토리가 아닌 실제 자격증명 파일 또는 환경변수 확인
    func checkAuthStatus() -> Bool {
        let claudeDir = NSHomeDirectory() + "/.claude"
        // 실제 인증 토큰 파일 확인 (claude auth login 후 생성됨)
        let credentialFiles = [
            claudeDir + "/.credentials.json",
            claudeDir + "/credentials.json",
            claudeDir + "/settings.json"
        ]
        for file in credentialFiles {
            if FileManager.default.fileExists(atPath: file) {
                return true
            }
        }
        // 환경변수를 통한 인증
        if ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] != nil ||
           ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil {
            return true
        }
        return false
    }

    /// 인증 완료로 전환 (수동 확인 후)
    func confirmAuth() {
        state = .ready
    }

    // MARK: - 프로세스 실행

    private func runProcess(_ executablePath: String, arguments: [String]) async -> (success: Bool, output: String) {
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

        let result = await ProcessRunner.run(
            executable: executablePath,
            args: arguments,
            env: env,
            workDir: homePath
        )

        let combined = (result.stdout + "\n" + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return (result.exitCode == 0, combined)
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
