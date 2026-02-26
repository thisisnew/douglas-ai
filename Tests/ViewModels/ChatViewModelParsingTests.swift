import Testing
import Foundation
@testable import AgentManagerLib

@Suite("ChatViewModel JSON Parsing Tests")
@MainActor
struct ChatViewModelParsingTests {
    let vm = ChatViewModel()

    // MARK: - extractJSON 테스트

    @Test("extractJSON - json 코드블록")
    func extractJSONCodeBlock() {
        let input = """
        ```json
        {"action": "respond", "message": "hello"}
        ```
        """
        let result = vm.extractJSON(from: input)
        #expect(result.contains("respond"))
        #expect(result.contains("hello"))
    }

    @Test("extractJSON - 일반 코드블록")
    func extractJSONPlainCodeBlock() {
        let input = """
        ```
        {"action": "respond"}
        ```
        """
        let result = vm.extractJSON(from: input)
        #expect(result.contains("respond"))
    }

    @Test("extractJSON - 순수 JSON")
    func extractJSONRawJSON() {
        let input = """
        {"action": "respond", "message": "hello"}
        """
        let result = vm.extractJSON(from: input)
        #expect(result == input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("extractJSON - 텍스트에 포함된 JSON")
    func extractJSONInText() {
        let input = "Here is my response: {\"action\": \"respond\"} end"
        let result = vm.extractJSON(from: input)
        #expect(result == "{\"action\": \"respond\"}")
    }

    @Test("extractJSON - JSON 없는 텍스트")
    func extractJSONNoJSON() {
        let input = "Just a plain text response"
        let result = vm.extractJSON(from: input)
        #expect(result == input)
    }

    @Test("extractJSON - 중첩 중괄호")
    func extractJSONNestedBraces() {
        let input = "{\"action\": \"respond\", \"message\": \"use {braces} carefully\"}"
        let result = vm.extractJSON(from: input)
        #expect(result == input)
    }

    // MARK: - parseMasterResponse 테스트

    @Test("parseMasterResponse - delegate 단일")
    func parseDelegateSingle() {
        let input = """
        {"action": "delegate", "agents": ["Agent1"], "task": "do something"}
        """
        let result = vm.parseMasterResponse(input)
        if case .delegate(let agents, let task, let contextFrom) = result {
            #expect(agents == ["Agent1"])
            #expect(task == "do something")
            #expect(contextFrom == nil)
        } else {
            Issue.record("Expected .delegate, got \(result)")
        }
    }

    @Test("parseMasterResponse - delegate 복수")
    func parseDelegateMultiple() {
        let input = """
        {"action": "delegate", "agents": ["A", "B"], "task": "compare"}
        """
        let result = vm.parseMasterResponse(input)
        if case .delegate(let agents, _, _) = result {
            #expect(agents == ["A", "B"])
        } else {
            Issue.record("Expected .delegate")
        }
    }

    @Test("parseMasterResponse - delegate with context_from")
    func parseDelegateWithContext() {
        let input = """
        {"action": "delegate", "agents": ["B"], "task": "work", "context_from": ["A"]}
        """
        let result = vm.parseMasterResponse(input)
        if case .delegate(_, _, let contextFrom) = result {
            #expect(contextFrom == ["A"])
        } else {
            Issue.record("Expected .delegate with contextFrom")
        }
    }

    @Test("parseMasterResponse - respond는 unknown으로 처리 (직접 답변 금지)")
    func parseRespondNowUnknown() {
        let input = """
        {"action": "respond", "message": "Hello!"}
        """
        let result = vm.parseMasterResponse(input)
        if case .unknown = result {
            // respond 액션은 제거됨 → unknown으로 처리
        } else {
            Issue.record("Expected .unknown for respond action")
        }
    }

    @Test("parseMasterResponse - suggest_agent")
    func parseSuggestAgent() {
        let input = """
        {"action": "suggest_agent", "name": "Coder", "persona": "writes code", "recommended_provider": "OpenAI", "recommended_model": "gpt-4o"}
        """
        let result = vm.parseMasterResponse(input)
        if case .suggestAgent(let name, let persona, let provider, let model) = result {
            #expect(name == "Coder")
            #expect(persona == "writes code")
            #expect(provider == "OpenAI")
            #expect(model == "gpt-4o")
        } else {
            Issue.record("Expected .suggestAgent")
        }
    }

    @Test("parseMasterResponse - chain")
    func parseChain() {
        let input = """
        {"action": "chain", "steps": [{"agent": "A", "task": "step1"}, {"agent": "B", "task": "step2"}]}
        """
        let result = vm.parseMasterResponse(input)
        if case .chain(let steps) = result {
            #expect(steps.count == 2)
            #expect(steps[0].agent == "A")
            #expect(steps[0].task == "step1")
            #expect(steps[1].agent == "B")
        } else {
            Issue.record("Expected .chain")
        }
    }

    @Test("parseMasterResponse - chain (빈 steps)")
    func parseChainEmptySteps() {
        let input = """
        {"action": "chain", "steps": []}
        """
        let result = vm.parseMasterResponse(input)
        if case .unknown = result {
            // 정상: 빈 steps면 unknown
        } else {
            Issue.record("Expected .unknown for empty chain steps")
        }
    }

    @Test("parseMasterResponse - unknown action")
    func parseUnknownAction() {
        let input = """
        {"action": "something_else"}
        """
        let result = vm.parseMasterResponse(input)
        if case .unknown = result {
            // 정상
        } else {
            Issue.record("Expected .unknown")
        }
    }

    @Test("parseMasterResponse - 유효하지 않은 JSON")
    func parseInvalidJSON() {
        let input = "This is not JSON at all"
        let result = vm.parseMasterResponse(input)
        if case .unknown(let raw) = result {
            #expect(raw == input)
        } else {
            Issue.record("Expected .unknown")
        }
    }

    @Test("parseMasterResponse - 코드블록에 감싸진 delegate JSON")
    func parseWrappedInCodeBlock() {
        let input = """
        ```json
        {"action": "delegate", "agents": ["Agent1"], "task": "do work"}
        ```
        """
        let result = vm.parseMasterResponse(input)
        if case .delegate(let agents, let task, _) = result {
            #expect(agents == ["Agent1"])
            #expect(task == "do work")
        } else {
            Issue.record("Expected .delegate, got \(result)")
        }
    }

    @Test("parseMasterResponse - delegate (agents 누락)")
    func parseDelegateMissingAgents() {
        let input = """
        {"action": "delegate", "task": "something"}
        """
        let result = vm.parseMasterResponse(input)
        if case .unknown = result {
            // agents가 없으면 unknown
        } else {
            Issue.record("Expected .unknown")
        }
    }

    @Test("parseMasterResponse - delegate (task 누락)")
    func parseDelegateMissingTask() {
        let input = """
        {"action": "delegate", "agents": ["A"]}
        """
        let result = vm.parseMasterResponse(input)
        if case .unknown = result {
            // task가 없으면 unknown
        } else {
            Issue.record("Expected .unknown")
        }
    }
}
