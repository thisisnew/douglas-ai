import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkRule Tests")
struct WorkRuleTests {

    // MARK: - resolve

    @Test("inline content — 텍스트 그대로 반환")
    func resolveInline() {
        let rule = WorkRule(name: "코딩", summary: "코딩 규칙", content: .inline("테스트 필수"))
        #expect(rule.resolve() == "테스트 필수")
    }

    @Test("빈 inline — 빈 문자열")
    func resolveEmptyInline() {
        let rule = WorkRule(name: "빈", summary: "", content: .inline(""))
        #expect(rule.resolve() == "")
        #expect(rule.isEmpty)
    }

    @Test("file content — 존재하지 않는 파일 → 경고")
    func resolveNonexistentFile() {
        let rule = WorkRule(name: "파일", summary: "", content: .file("/tmp/__nonexistent_rule__.txt"))
        let result = rule.resolve()
        #expect(result.contains("경고"))
    }

    // MARK: - displaySummary

    @Test("displaySummary — 이름: 요약")
    func displaySummary() {
        let rule = WorkRule(name: "코딩", summary: "코드 작성 규칙", content: .inline("내용"))
        #expect(rule.displaySummary.contains("코딩"))
        #expect(rule.displaySummary.contains("코드 작성 규칙"))
    }

    // MARK: - isEmpty

    @Test("isEmpty — inline 빈 문자열이면 true")
    func isEmptyInline() {
        #expect(WorkRule(name: "a", summary: "", content: .inline("  ")).isEmpty)
        #expect(!WorkRule(name: "a", summary: "", content: .inline("내용")).isEmpty)
    }

    @Test("isEmpty — file 빈 경로면 true")
    func isEmptyFile() {
        #expect(WorkRule(name: "a", summary: "", content: .file("")).isEmpty)
        #expect(!WorkRule(name: "a", summary: "", content: .file("/some/path")).isEmpty)
    }

    // MARK: - Codable

    @Test("Codable 왕복")
    func codableRoundTrip() throws {
        let original = WorkRule(
            name: "PR 규칙",
            summary: "PR, 코드 리뷰 시 적용",
            content: .inline("[필수] PR 올리기"),
            isAlwaysActive: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkRule.self, from: data)
        #expect(decoded.name == original.name)
        #expect(decoded.summary == original.summary)
        #expect(decoded.content == original.content)
        #expect(decoded.isAlwaysActive == original.isAlwaysActive)
        #expect(decoded.id == original.id)
    }

    @Test("Codable — file content 왕복")
    func codableFileRoundTrip() throws {
        let original = WorkRule(name: "외부", summary: "외부 파일", content: .file("/path/to/rules.md"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkRule.self, from: data)
        #expect(decoded.content == .file("/path/to/rules.md"))
    }
}

// WorkRuleMatcher tests moved to WorkRuleMatcherTests.swift
