import Foundation

/// 테스트에서 교체 가능한 프로세스 실행기
/// 프로덕션: Process()로 실제 실행. 테스트: handler를 설정하여 mock.
enum ProcessRunner {
    /// 테스트에서 이 핸들러를 설정하면 실제 Process 대신 mock 응답을 반환
    nonisolated(unsafe) static var handler: (
        (_ executable: String, _ args: [String], _ env: [String: String]?, _ workDir: String?)
        async -> (exitCode: Int32, stdout: String, stderr: String)
    )? = nil

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
                    process.waitUntilExit()

                    let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: outData, encoding: .utf8) ?? ""
                    let stderr = String(data: errData, encoding: .utf8) ?? ""

                    continuation.resume(returning: (process.terminationStatus, stdout, stderr))
                } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                }
            }
        }
    }
}
