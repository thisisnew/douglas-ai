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

@Suite("WorkRuleMatcher Tests")
struct WorkRuleMatcherTests {

    private func makeRule(_ name: String, summary: String = "", alwaysActive: Bool = false) -> WorkRule {
        WorkRule(name: name, summary: summary, content: .inline("내용"), isAlwaysActive: alwaysActive)
    }

    // MARK: - 기본 매칭

    @Test("키워드 매칭 — 이름에 포함된 키워드")
    func matchByName() {
        let rules = [makeRule("코딩 규칙"), makeRule("PR 규칙"), makeRule("배포 규칙")]
        let result = WorkRuleMatcher.match(rules: rules, taskText: "코딩만 해줘")
        #expect(result.contains(rules[0].id))
        #expect(!result.contains(rules[1].id))
        #expect(!result.contains(rules[2].id))
    }

    @Test("키워드 매칭 — 요약에 포함된 키워드")
    func matchBySummary() {
        let rules = [
            makeRule("규칙A", summary: "코드 작성, 구현 시 적용"),
            makeRule("규칙B", summary: "리뷰, 검토 시 적용")
        ]
        let result = WorkRuleMatcher.match(rules: rules, taskText: "코드 구현해줘")
        #expect(result.contains(rules[0].id))
        #expect(!result.contains(rules[1].id))
    }

    // MARK: - isAlwaysActive

    @Test("isAlwaysActive — 항상 포함")
    func alwaysActiveIncluded() {
        let rules = [
            makeRule("공통 규칙", alwaysActive: true),
            makeRule("코딩 규칙"),
            makeRule("PR 규칙")
        ]
        let result = WorkRuleMatcher.match(rules: rules, taskText: "코딩해줘")
        #expect(result.contains(rules[0].id))  // 항상 활성
        #expect(result.contains(rules[1].id))   // 매칭됨
        #expect(!result.contains(rules[2].id))  // 매칭 안 됨
    }

    // MARK: - 폴백

    @Test("매칭 0건 → 전체 포함 (폴백)")
    func fallbackToAll() {
        let rules = [makeRule("코딩 규칙"), makeRule("PR 규칙")]
        let result = WorkRuleMatcher.match(rules: rules, taskText: "안녕하세요")
        #expect(result.count == 2)  // 전부 포함
    }

    @Test("isAlwaysActive만 매칭되고 동적 매칭 0건 → 전체 포함")
    func fallbackWithOnlyAlwaysActive() {
        let rules = [
            makeRule("공통", alwaysActive: true),
            makeRule("코딩 규칙"),
            makeRule("PR 규칙")
        ]
        let result = WorkRuleMatcher.match(rules: rules, taskText: "날씨 어때")
        #expect(result.count == 3)  // 전부 포함
    }

    // MARK: - 빈 규칙

    @Test("빈 규칙 배열 → 빈 결과")
    func emptyRules() {
        let result = WorkRuleMatcher.match(rules: [], taskText: "코딩해줘")
        #expect(result.isEmpty)
    }

    // MARK: - 대소문자 무시

    @Test("대소문자 무시 매칭")
    func caseInsensitive() {
        let rules = [makeRule("API 규칙")]
        let result = WorkRuleMatcher.match(rules: rules, taskText: "api 만들어줘")
        #expect(result.contains(rules[0].id))
    }

    // MARK: - 한글자 키워드 무시

    @Test("2글자 미만 키워드 무시")
    func shortKeywordsIgnored() {
        let rules = [makeRule("A 규칙", summary: "A")]
        // "A"는 1글자라 키워드에서 제외, "규칙"만 매칭 대상
        let result = WorkRuleMatcher.match(rules: rules, taskText: "A를 해줘")
        // "규칙"이 태스크에 없으므로 매칭 0 → 폴백으로 전체
        #expect(result.count == 1)
    }
}
