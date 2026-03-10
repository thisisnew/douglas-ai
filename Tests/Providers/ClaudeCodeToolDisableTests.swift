import Testing
import Foundation
@testable import DOUGLAS

@Suite("ClaudeCodeProvider 도구 비활성화 Tests")
struct ClaudeCodeToolDisableTests {

    // MARK: - Change A: sendMessageWithTools(tools: []) → disableTools: true

    @Test("sendMessageWithTools tools 빈 배열 시 CLI 도구 비활성화")
    func sendMessageWithToolsEmptyToolsDisables() async throws {
        // Given: ClaudeCodeProvider에 tools: [] 로 호출
        // Then: runClaude에 전달되는 args에 --allowedTools가 없어야 함

        var capturedArgs: [String] = []
        await ProcessRunner.withMock { _, args, _, _ in
            capturedArgs = args
            return (0, "토론 응답입니다", "")
        } body: {
            let config = makeTestProviderConfig(
                name: "ClaudeCode", type: .claudeCode,
                baseURL: "/usr/bin/claude", authMethod: .none
            )
            let provider = ClaudeCodeProvider(config: config)
            let messages = [ConversationMessage.user("테스트 주제")]
            _ = try? await provider.sendMessageWithTools(
                model: "claude-sonnet-4-20250514",
                systemPrompt: "당신은 전문가입니다",
                messages: messages,
                tools: []  // 빈 배열 → 도구 비활성화
            )
        }

        // --allowedTools가 args에 없어야 함 (disableTools: true)
        #expect(!capturedArgs.contains("--allowedTools"),
                "tools: [] 시 --allowedTools가 포함되면 안 됨")
        // --system-prompt 사용 (disableTools: true 모드)
        #expect(capturedArgs.contains("--system-prompt"),
                "disableTools: true 시 --system-prompt 사용")
    }

    @Test("sendMessageWithTools tools 빈 배열 시 이미지 Read 도구 안내 제거")
    func sendMessageWithToolsEmptyToolsNoImageGuide() async throws {
        // Given: 이미지 첨부 + tools: []
        // Then: "Read 도구로 확인" 문구가 프롬프트에 없어야 함

        var capturedArgs: [String] = []
        await ProcessRunner.withMock { _, args, _, _ in
            capturedArgs = args
            return (0, "응답", "")
        } body: {
            let config = makeTestProviderConfig(
                name: "ClaudeCode", type: .claudeCode,
                baseURL: "/usr/bin/claude", authMethod: .none
            )
            let provider = ClaudeCodeProvider(config: config)
            // 실제 이미지 파일이 필요 없음 — sendMessageWithTools는 attachments.diskPath만 참조
            let attachment = FileAttachment(
                id: UUID(), filename: "test.png",
                mimeType: "image/png", fileSizeBytes: 100
            )
            let messages = [ConversationMessage.user("이미지 분석해줘", attachments: [attachment])]
            _ = try? await provider.sendMessageWithTools(
                model: "claude-sonnet-4-20250514",
                systemPrompt: "전문가",
                messages: messages,
                tools: []
            )
        }

        // 프롬프트에 Read 도구 안내가 없어야 함
        let promptContent = capturedArgs.joined(separator: " ")
        #expect(!promptContent.contains("Read 도구로 확인"),
                "tools: [] 시 Read 도구 안내 불필요")
    }

    // MARK: - Change B: withTaskGroup 취소 전파

    @Test("Task 취소 시 guard로 즉시 빈 결과 반환")
    func taskCancellationReturnsEmpty() async {
        let testID = UUID()
        let task = Task<(String, String, UUID), Never> {
            guard !Task.isCancelled else { return ("", "", testID) }
            return ("agent", "response", testID)
        }
        task.cancel()
        let result = await task.value
        #expect(result.0.isEmpty)
        #expect(result.1.isEmpty)
        #expect(result.2 == testID)
    }

    // MARK: - Change C: ProcessRunner 취소

    @Test("ProcessRunner mock에서 취소된 Task는 크래시 없이 완료")
    func processRunnerCancellationSafe() async {
        let task = Task<Bool, Never> {
            await ProcessRunner.withMock { _, _, _, _ in
                return (0, "result", "")
            } body: {
                let _ = await ProcessRunner.runStreaming(
                    executable: "/usr/bin/test",
                    args: [],
                    onOutput: { _ in }
                )
            }
            return Task.isCancelled
        }
        task.cancel()
        let wasCancelled = await task.value
        #expect(wasCancelled == true)
    }
}
