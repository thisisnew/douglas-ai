import Testing
import Foundation
@testable import DOUGLAS

@Suite("BuildLoopRunner Tests")
struct BuildLoopRunnerTests {

    // MARK: - runBuild

    @Test("빌드 성공 시 BuildResult.success == true")
    func buildSuccess() async {
        await ProcessRunner.withMock({ _, _, _, _ in
            (exitCode: 0, stdout: "Build complete!", stderr: "")
        }) {
            let result = await BuildLoopRunner.runBuild(
                command: "echo ok",
                workingDirectory: "/tmp"
            )
            #expect(result.success == true)
            #expect(result.exitCode == 0)
            #expect(result.output.contains("Build complete!"))
        }
    }

    @Test("빌드 실패 시 BuildResult.success == false")
    func buildFailure() async {
        await ProcessRunner.withMock({ _, _, _, _ in
            (exitCode: 1, stdout: "", stderr: "error: cannot find module")
        }) {
            let result = await BuildLoopRunner.runBuild(
                command: "swift build",
                workingDirectory: "/tmp"
            )
            #expect(result.success == false)
            #expect(result.exitCode == 1)
            #expect(result.output.contains("cannot find module"))
        }
    }

    @Test("빌드 출력 크기 제한")
    func buildOutputTruncation() async {
        let longOutput = String(repeating: "a", count: 20_000)
        await ProcessRunner.withMock({ _, _, _, _ in
            (exitCode: 0, stdout: longOutput, stderr: "")
        }) {
            let result = await BuildLoopRunner.runBuild(
                command: "build",
                workingDirectory: "/tmp"
            )
            #expect(result.output.count < longOutput.count)
            #expect(result.output.contains("생략"))
        }
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

    // MARK: - runTests (Phase C-3)

    @Test("테스트 성공 시 QAResult.success == true")
    func testSuccess() async {
        await ProcessRunner.withMock({ _, _, _, _ in
            (exitCode: 0, stdout: "All tests passed!", stderr: "")
        }) {
            let result = await BuildLoopRunner.runTests(
                command: "swift test",
                workingDirectory: "/tmp"
            )
            #expect(result.success == true)
            #expect(result.exitCode == 0)
            #expect(result.output.contains("All tests passed!"))
        }
    }

    @Test("테스트 실패 시 QAResult.success == false")
    func testFailure() async {
        await ProcessRunner.withMock({ _, _, _, _ in
            (exitCode: 1, stdout: "", stderr: "2 tests failed")
        }) {
            let result = await BuildLoopRunner.runTests(
                command: "npm test",
                workingDirectory: "/tmp"
            )
            #expect(result.success == false)
            #expect(result.exitCode == 1)
            #expect(result.output.contains("2 tests failed"))
        }
    }

    @Test("테스트 출력 크기 제한")
    func testOutputTruncation() async {
        let longOutput = String(repeating: "x", count: 20_000)
        await ProcessRunner.withMock({ _, _, _, _ in
            (exitCode: 0, stdout: longOutput, stderr: "")
        }) {
            let result = await BuildLoopRunner.runTests(
                command: "test",
                workingDirectory: "/tmp"
            )
            #expect(result.output.count < longOutput.count)
            #expect(result.output.contains("생략"))
        }
    }

    @Test("QA 수정 프롬프트 형식 검증")
    func qaFixPromptFormat() {
        let prompt = BuildLoopRunner.qaFixPrompt(
            testCommand: "swift test",
            testOutput: "testFoo FAILED",
            retryNumber: 1,
            maxRetries: 3
        )
        #expect(prompt.contains("시도 1/3"))
        #expect(prompt.contains("swift test"))
        #expect(prompt.contains("testFoo FAILED"))
        #expect(prompt.contains("수정"))
    }

    @Test("빌드 명령이 working directory로 전달됨")
    func workingDirectoryPassed() async {
        let captured = CapturedValue<String>()
        await ProcessRunner.withMock({ _, _, _, workDir in
            captured.value = workDir
            return (exitCode: 0, stdout: "", stderr: "")
        }) {
            _ = await BuildLoopRunner.runBuild(
                command: "make",
                workingDirectory: "/Users/test/project"
            )
            #expect(captured.value == "/Users/test/project")
        }
    }
}
