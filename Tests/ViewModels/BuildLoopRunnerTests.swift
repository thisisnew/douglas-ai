import Testing
import Foundation
@testable import DOUGLAS

@Suite("BuildLoopRunner Tests", .serialized)
struct BuildLoopRunnerTests {

    // MARK: - runBuild

    @Test("빌드 성공 시 BuildResult.success == true")
    func buildSuccess() async {
        let original = ProcessRunner.handler
        ProcessRunner.handler = { _, _, _, _ in
            (exitCode: 0, stdout: "Build complete!", stderr: "")
        }
        defer { ProcessRunner.handler = original }

        let result = await BuildLoopRunner.runBuild(
            command: "echo ok",
            workingDirectory: "/tmp"
        )
        #expect(result.success == true)
        #expect(result.exitCode == 0)
        #expect(result.output.contains("Build complete!"))
    }

    @Test("빌드 실패 시 BuildResult.success == false")
    func buildFailure() async {
        let original = ProcessRunner.handler
        ProcessRunner.handler = { _, _, _, _ in
            (exitCode: 1, stdout: "", stderr: "error: cannot find module")
        }
        defer { ProcessRunner.handler = original }

        let result = await BuildLoopRunner.runBuild(
            command: "swift build",
            workingDirectory: "/tmp"
        )
        #expect(result.success == false)
        #expect(result.exitCode == 1)
        #expect(result.output.contains("cannot find module"))
    }

    @Test("빌드 출력 크기 제한")
    func buildOutputTruncation() async {
        let original = ProcessRunner.handler
        let longOutput = String(repeating: "a", count: 20_000)
        ProcessRunner.handler = { _, _, _, _ in
            (exitCode: 0, stdout: longOutput, stderr: "")
        }
        defer { ProcessRunner.handler = original }

        let result = await BuildLoopRunner.runBuild(
            command: "build",
            workingDirectory: "/tmp"
        )
        #expect(result.output.count < longOutput.count)
        #expect(result.output.contains("생략"))
    }

    // MARK: - buildFixPrompt

    @Test("수정 프롬프트 형식 검증")
    func fixPromptFormat() {
        let prompt = BuildLoopRunner.buildFixPrompt(
            buildCommand: "swift build",
            buildOutput: "error: type 'Foo' has no member 'bar'",
            retryNumber: 2,
            maxRetries: 3
        )
        #expect(prompt.contains("시도 2/3"))
        #expect(prompt.contains("swift build"))
        #expect(prompt.contains("type 'Foo' has no member 'bar'"))
        #expect(prompt.contains("수정"))
    }

    @Test("빌드 명령이 working directory로 전달됨")
    func workingDirectoryPassed() async {
        let original = ProcessRunner.handler
        var capturedWorkDir: String?
        ProcessRunner.handler = { _, _, _, workDir in
            capturedWorkDir = workDir
            return (exitCode: 0, stdout: "", stderr: "")
        }
        defer { ProcessRunner.handler = original }

        _ = await BuildLoopRunner.runBuild(
            command: "make",
            workingDirectory: "/Users/test/project"
        )
        #expect(capturedWorkDir == "/Users/test/project")
    }
}
