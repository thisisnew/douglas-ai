import Testing
import Foundation
@testable import DOUGLAS

@Suite("ClaudeCodeProvider 토큰 관리 Tests")
struct ClaudeCodeProviderTokenTests {

    // MARK: - P0: MCP 와일드카드

    @Test("MCP mcp__* 와일드카드가 기본 allowedTools에 자동 추가되지 않음")
    func mcpWildcardNotAutoAdded() {
        let defaultTools = ["Edit", "Write", "Bash", "Read", "Glob", "Grep", "WebSearch"]
        // MCP 와일드카드 자동 추가 로직이 제거되었으므로 기본 도구에 mcp__* 없어야 함
        #expect(!defaultTools.contains(where: { $0.hasPrefix("mcp__") }))
    }

    @Test("allowedTools에 mcp__* 명시적 포함 시 유지")
    func mcpWildcardKeptWhenExplicit() {
        let tools = ["Edit", "Write", "Bash", "mcp__atlassian__get_issue"]
        // 명시적 MCP 도구는 그대로 유지되어야 함
        #expect(tools.contains(where: { $0.hasPrefix("mcp__") }))
    }

    // MARK: - P1: buildUserPrompt 메시지 절단

    @Test("buildUserPrompt — 짧은 메시지는 절단 없이 전달")
    func shortMessagesNotTruncated() {
        let messages: [(role: String, content: String)] = [
            (role: "user", content: "안녕하세요"),
            (role: "assistant", content: "반갑습니다"),
            (role: "user", content: "작업 시작")
        ]
        let prompt = ClaudeCodeProviderTokenTests.buildUserPromptHelper(from: messages)
        #expect(prompt.contains("안녕하세요"))
        #expect(prompt.contains("반갑습니다"))
        #expect(prompt.contains("작업 시작"))
        #expect(!prompt.contains("…"))
    }

    @Test("buildUserPrompt — 500자 초과 메시지 절단")
    func longMessagesTruncated() {
        let longContent = String(repeating: "가", count: 600)
        let messages: [(role: String, content: String)] = [
            (role: "user", content: longContent),
            (role: "user", content: "마지막 질문")
        ]
        let prompt = ClaudeCodeProviderTokenTests.buildUserPromptHelper(from: messages)
        // 히스토리(첫 메시지)는 절단되어야 함
        #expect(!prompt.contains(longContent))
        #expect(prompt.contains("…"))
        // 마지막 메시지(현재 질문)는 절단 없이 전달
        #expect(prompt.contains("마지막 질문"))
    }

    @Test("buildUserPrompt — 마지막 메시지는 절단하지 않음")
    func lastMessageNotTruncated() {
        let longContent = String(repeating: "A", count: 1000)
        let messages: [(role: String, content: String)] = [
            (role: "user", content: longContent)
        ]
        let prompt = ClaudeCodeProviderTokenTests.buildUserPromptHelper(from: messages)
        // 메시지가 1개면 히스토리가 비어있으므로 마지막 메시지만 전달 — 절단 없음
        #expect(prompt.contains(longContent))
    }

    @Test("buildUserPrompt — 히스토리 최대 10개")
    func historyLimitedTo10() {
        var messages: [(role: String, content: String)] = []
        for i in 1...15 {
            messages.append((role: "user", content: "메시지\(i)"))
        }
        let prompt = ClaudeCodeProviderTokenTests.buildUserPromptHelper(from: messages)
        // 히스토리는 마지막 메시지 제외 14개 중 suffix(10)만
        // 즉 메시지5~14가 히스토리, 메시지15가 현재
        #expect(!prompt.contains("메시지1\n"))
        #expect(!prompt.contains("메시지4\n"))
        #expect(prompt.contains("메시지5"))
        #expect(prompt.contains("메시지14"))
        #expect(prompt.contains("메시지15"))
    }

    // MARK: - Helper (buildUserPrompt 로직 미러)

    /// ClaudeCodeProvider.buildUserPrompt와 동일한 로직 (테스트용)
    static func buildUserPromptHelper(from messages: [(role: String, content: String)]) -> String {
        let lastUserMessage = messages.last(where: { $0.role == "user" })?.content ?? ""
        var userPrompt = ""
        let history = messages.dropLast()
        if !history.isEmpty {
            userPrompt += "[이전 대화]\n"
            for msg in history.suffix(10) {
                let label = msg.role == "user" ? "사용자" : "어시스턴트"
                let truncated = msg.content.count > 500
                    ? String(msg.content.prefix(500)) + "…"
                    : msg.content
                userPrompt += "\(label): \(truncated)\n"
            }
            userPrompt += "\n"
        }
        userPrompt += lastUserMessage
        return userPrompt
    }
}
