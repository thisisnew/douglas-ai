import Foundation

/// 테스트에서 교체 가능한 프로세스 실행기
/// 프로덕션: Process()로 실제 실행. 테스트: handler를 설정하여 mock.
enum ProcessRunner {
    /// 테스트에서 `$handler.withValue(mock) { ... }` 로 태스크별 격리된 mock 주입.
    /// @TaskLocal로 병렬 테스트 간 핸들러 충돌 방지.
    @TaskLocal static var handler: (
        @Sendable (_ executable: String, _ args: [String], _ env: [String: String]?, _ workDir: String?)
        async -> (exitCode: Int32, stdout: String, stderr: String)
    )?

    /// 테스트에서 mock handler를 태스크 격리 방식으로 주입
    static func withMock(
        _ mock: @escaping @Sendable (_ executable: String, _ args: [String], _ env: [String: String]?, _ workDir: String?)
            async -> (exitCode: Int32, stdout: String, stderr: String),
        body: () async throws -> Void
    ) async rethrows {
        try await $handler.withValue(mock, operation: body)
    }

    /// 프로세스 실행. handler가 설정되면 mock, 아니면 실제 Process 실행.
    static func run(
        executable: String,
        args: [String],
        env: [String: String]? = nil,
        workDir: String? = nil
    ) async -> (exitCode: Int32, stdout: String, stderr: String) {
        if let handler {
            return await handler(executable, args, env, workDir)
        }
        return await defaultRun(executable: executable, args: args, env: env, workDir: workDir)
    }

    /// 실제 Process 실행 (프로덕션 코드 경로)
    /// stdout/stderr를 별도 스레드에서 동시 읽기하여 파이프 버퍼(64KB) 데드락 방지.
    private static func defaultRun(
        executable: String,
        args: [String],
        env: [String: String]?,
        workDir: String?
    ) async -> (exitCode: Int32, stdout: String, stderr: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args

                if let env {
                    process.environment = env
                }
                if let workDir {
                    process.currentDirectoryURL = URL(fileURLWithPath: workDir)
                }

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()

                    // 파이프를 별도 스레드에서 동시 읽기 — waitUntilExit 전에 드레인해야
                    // 서브프로세스가 64KB 이상 출력 시 파이프 버퍼 가득 참 → 데드락 방지
                    var stdoutData = Data()
                    var stderrData = Data()
                    let group = DispatchGroup()

                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }

                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }

                    group.wait()
                    process.waitUntilExit()

                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: (process.terminationStatus, stdout, stderr))
                } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                }
            }
        }
    }
}
