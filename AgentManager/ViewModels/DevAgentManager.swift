import Foundation

@MainActor
class DevAgentManager: ObservableObject {
    @Published var changeHistory: [ChangeRecord] = []
    @Published var isGitInitialized: Bool = false
    @Published var isBuildRunning: Bool = false

    let projectPath: String

    private static var historyDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgentManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var historyFile: URL {
        Self.historyDirectory.appendingPathComponent("changes.json")
    }

    init(projectPath: String = "/Users/douglas.kim/AgentManager") {
        self.projectPath = projectPath
        loadHistory()
        checkGitStatus()
    }

    // MARK: - Git 상태 확인

    private func checkGitStatus() {
        let gitDir = projectPath + "/.git"
        isGitInitialized = FileManager.default.fileExists(atPath: gitDir)
    }

    // MARK: - Git 초기화

    func initializeGitIfNeeded() async throws {
        if isGitInitialized { return }

        _ = try await runGitCommand(["init"])

        // .gitignore 생성
        let gitignore = """
        .build/
        .DS_Store
        dist/
        *.xcodeproj/
        .claude/
        """
        let gitignorePath = projectPath + "/.gitignore"
        try gitignore.write(toFile: gitignorePath, atomically: true, encoding: .utf8)

        _ = try await runGitCommand(["add", "."])
        _ = try await runGitCommand(["commit", "-m", "[Woz] docs: 프로젝트 초기 커밋"])

        isGitInitialized = true
    }

    // MARK: - 빌드 검증

    func runBuildVerification() async throws -> (success: Bool, output: String) {
        isBuildRunning = true
        defer { isBuildRunning = false }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [projectPath] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
                process.arguments = ["build", "-c", "release"]
                process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

                var env = ProcessInfo.processInfo.environment
                let homePath = env["HOME"] ?? "/Users/\(NSUserName())"
                let additionalPaths = [
                    "\(homePath)/.nvm/versions/node/v22.21.1/bin",
                    "/opt/homebrew/bin",
                    "/usr/local/bin"
                ]
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

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                    let combined = output + errorOutput

                    continuation.resume(returning: (
                        success: process.terminationStatus == 0,
                        output: combined.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Git 커밋

    func commitChange(
        message: String,
        description: String,
        filesChanged: [String],
        requestText: String
    ) async throws {
        try await initializeGitIfNeeded()

        _ = try await runGitCommand(["add", "."])
        _ = try await runGitCommand(["commit", "-m", message])

        // 커밋 해시 추출
        let hash = try await runGitCommand(["rev-parse", "--short", "HEAD"])

        let record = ChangeRecord(
            description: description,
            commitHash: hash.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .applied,
            filesChanged: filesChanged,
            requestText: requestText
        )
        changeHistory.append(record)
        saveHistory()
    }

    // MARK: - 롤백

    func revertChange(_ record: ChangeRecord) async throws {
        _ = try await runGitCommand(["revert", "--no-edit", record.commitHash])

        if let idx = changeHistory.firstIndex(where: { $0.id == record.id }) {
            changeHistory[idx].status = .rolledBack
            saveHistory()
        }
    }

    // MARK: - 미커밋 변경 폐기

    func discardUncommittedChanges() async throws {
        _ = try await runGitCommand(["checkout", "--", "."])
    }

    // MARK: - 변경된 파일 목록

    func getChangedFiles() async throws -> [String] {
        let output = try await runGitCommand(["diff", "--name-only"])
        let staged = try await runGitCommand(["diff", "--cached", "--name-only"])
        let all = (output + "\n" + staged)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        return Array(Set(all))
    }

    // MARK: - Git 명령 실행

    private nonisolated func runGitCommand(_ arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [projectPath] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        let msg = errorOutput.isEmpty ? "Git 명령 실패 (코드: \(process.terminationStatus))" : errorOutput
                        continuation.resume(throwing: DevAgentError.gitError(msg))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: DevAgentError.gitError("Git 실행 실패: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - 이력 영속화

    func saveHistory() {
        if let data = try? JSONEncoder().encode(changeHistory) {
            try? data.write(to: historyFile)
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyFile),
              let loaded = try? JSONDecoder().decode([ChangeRecord].self, from: data) else { return }
        changeHistory = loaded
    }
}

enum DevAgentError: LocalizedError {
    case gitError(String)
    case buildFailed(String)
    case notExecutionMode

    var errorDescription: String? {
        switch self {
        case .gitError(let msg): return "Git 오류: \(msg)"
        case .buildFailed(let msg): return "빌드 실패: \(msg)"
        case .notExecutionMode: return "실행 모드가 아닙니다. Claude Code CLI를 사용해야 직접 수정 가능합니다."
        }
    }
}
