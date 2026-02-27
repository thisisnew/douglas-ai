import Foundation

/// 빌드 실행 + 수정 프롬프트 생성 엔진
enum BuildLoopRunner {
    /// 빌드 명령 실행 후 BuildResult 반환
    static func runBuild(command: String, workingDirectory: String) async -> BuildResult {
        // nvm/homebrew PATH 설정 (ToolExecutor.executeShellExec과 동일 패턴)
        var env = ProcessInfo.processInfo.environment
        let homePath = env["HOME"] ?? "/Users/\(NSUserName())"

        var additionalPaths: [String] = []
        let nvmDir = "\(homePath)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                additionalPaths.append("\(nvmDir)/\(version)/bin")
            }
        }
        additionalPaths.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin"])

        if let existingPath = env["PATH"] {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath
        }

        let result = await ProcessRunner.run(
            executable: "/bin/zsh",
            args: ["-c", command],
            env: env,
            workDir: workingDirectory
        )

        var output = ""
        if !result.stdout.isEmpty { output += result.stdout }
        if !result.stderr.isEmpty { output += (output.isEmpty ? "" : "\n") + result.stderr }
        if output.isEmpty { output = "(출력 없음)" }

        // 빌드 출력 크기 제한 (토큰 절약)
        let maxLen = 15_000
        if output.count > maxLen {
            // 앞부분 + 뒷부분 보존 (에러는 보통 뒤에 나옴)
            let headLen = 3_000
            let tailLen = maxLen - headLen
            output = String(output.prefix(headLen))
                + "\n\n... (출력 \(output.count)자 중 중간 생략) ...\n\n"
                + String(output.suffix(tailLen))
        }

        return BuildResult(
            success: result.exitCode == 0,
            output: output,
            exitCode: result.exitCode
        )
    }

    /// 테스트 명령 실행 후 QAResult 반환 (runBuild와 동일 패턴)
    static func runTests(command: String, workingDirectory: String) async -> QAResult {
        var env = ProcessInfo.processInfo.environment
        let homePath = env["HOME"] ?? "/Users/\(NSUserName())"

        var additionalPaths: [String] = []
        let nvmDir = "\(homePath)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                additionalPaths.append("\(nvmDir)/\(version)/bin")
            }
        }
        additionalPaths.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin"])

        if let existingPath = env["PATH"] {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath
        }

        let result = await ProcessRunner.run(
            executable: "/bin/zsh",
            args: ["-c", command],
            env: env,
            workDir: workingDirectory
        )

        var output = ""
        if !result.stdout.isEmpty { output += result.stdout }
        if !result.stderr.isEmpty { output += (output.isEmpty ? "" : "\n") + result.stderr }
        if output.isEmpty { output = "(출력 없음)" }

        let maxLen = 15_000
        if output.count > maxLen {
            let headLen = 3_000
            let tailLen = maxLen - headLen
            output = String(output.prefix(headLen))
                + "\n\n... (출력 \(output.count)자 중 중간 생략) ...\n\n"
                + String(output.suffix(tailLen))
        }

        return QAResult(
            success: result.exitCode == 0,
            output: output,
            exitCode: result.exitCode
        )
    }

    /// 테스트 실패 시 에이전트에게 보낼 수정 프롬프트 생성
    static func qaFixPrompt(
        testCommand: String,
        testOutput: String,
        retryNumber: Int,
        maxRetries: Int
    ) -> String {
        """
        테스트 실패 (시도 \(retryNumber)/\(maxRetries))

        실행 명령: \(testCommand)

        테스트 출력:
        ```
        \(testOutput)
        ```

        위 테스트 실패를 분석하고 코드를 수정해 주세요.
        - 실패한 테스트를 정확히 파악하세요.
        - file_read로 관련 소스/테스트 파일을 확인한 후 file_write로 수정하세요.
        - 테스트 로직이 아닌 소스 코드를 수정하는 것을 우선하세요.
        - 수정 완료 후 반드시 수정 내용을 요약해 주세요.
        """
    }

    /// 빌드 실패 시 에이전트에게 보낼 수정 프롬프트 생성
    static func buildFixPrompt(
        buildCommand: String,
        buildOutput: String,
        retryNumber: Int,
        maxRetries: Int
    ) -> String {
        """
        빌드 실패 (시도 \(retryNumber)/\(maxRetries))

        실행 명령: \(buildCommand)

        빌드 출력:
        ```
        \(buildOutput)
        ```

        위 빌드 오류를 분석하고 수정해 주세요.
        - 오류 메시지를 정확히 읽고 원인을 파악하세요.
        - file_read로 관련 파일을 확인한 후 file_write로 수정하세요.
        - 수정 완료 후 반드시 수정 내용을 요약해 주세요.
        """
    }
}
