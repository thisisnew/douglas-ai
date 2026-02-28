import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkingRulesSource Tests")
struct WorkingRulesTests {

    // MARK: - resolve

    @Test("inline — 텍스트 그대로 반환")
    func resolveInline() {
        let rules = WorkingRulesSource.inline("브랜치 전략: feature/xxx 형식 사용")
        #expect(rules.resolve() == "브랜치 전략: feature/xxx 형식 사용")
    }

    @Test("filePath — 존재하는 파일 읽기")
    func resolveFilePathExists() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("test-rules-\(UUID().uuidString).txt")
        try "커밋 메시지는 한글로 작성".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let rules = WorkingRulesSource.filePath(file.path)
        #expect(rules.resolve() == "커밋 메시지는 한글로 작성")
    }

    @Test("filePath — 존재하지 않는 파일은 경고 메시지")
    func resolveFilePathNotExists() {
        let rules = WorkingRulesSource.filePath("/nonexistent/path/rules.txt")
        let result = rules.resolve()
        #expect(result.contains("경고"))
        #expect(result.contains("rules.txt"))
    }

    @Test("filePath — 빈 파일은 경고 메시지")
    func resolveFilePathEmpty() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("test-empty-rules-\(UUID().uuidString).txt")
        try "".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let rules = WorkingRulesSource.filePath(file.path)
        let result = rules.resolve()
        #expect(result.contains("경고"))
    }

    // MARK: - isEmpty

    @Test("isEmpty — inline 빈 문자열")
    func isEmptyInlineBlank() {
        #expect(WorkingRulesSource.inline("").isEmpty == true)
        #expect(WorkingRulesSource.inline("  \n ").isEmpty == true)
    }

    @Test("isEmpty — inline 내용 있음")
    func isEmptyInlineNotBlank() {
        #expect(WorkingRulesSource.inline("규칙").isEmpty == false)
    }

    @Test("isEmpty — filePath 빈 경로")
    func isEmptyFilePathBlank() {
        #expect(WorkingRulesSource.filePath("").isEmpty == true)
        #expect(WorkingRulesSource.filePath("  ").isEmpty == true)
    }

    @Test("isEmpty — filePath 경로 있음")
    func isEmptyFilePathNotBlank() {
        #expect(WorkingRulesSource.filePath("/path/to/rules").isEmpty == false)
    }

    // MARK: - displaySummary

    @Test("displaySummary — inline 짧은 텍스트")
    func displaySummaryInlineShort() {
        let rules = WorkingRulesSource.inline("짧은 규칙")
        #expect(rules.displaySummary == "짧은 규칙")
    }

    @Test("displaySummary — inline 긴 텍스트 잘림")
    func displaySummaryInlineLong() {
        let long = String(repeating: "가", count: 100)
        let rules = WorkingRulesSource.inline(long)
        #expect(rules.displaySummary.hasSuffix("..."))
        #expect(rules.displaySummary.count <= 84) // 80 + "..."
    }

    @Test("displaySummary — filePath 파일명 표시")
    func displaySummaryFilePath() {
        let rules = WorkingRulesSource.filePath("/Users/test/project/.cursorrules")
        #expect(rules.displaySummary == "파일: .cursorrules")
    }

    // MARK: - Codable

    @Test("Codable 라운드트립 — inline")
    func codableInline() throws {
        let original = WorkingRulesSource.inline("테스트 규칙")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkingRulesSource.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable 라운드트립 — filePath")
    func codableFilePath() throws {
        let original = WorkingRulesSource.filePath("/path/to/rules.md")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkingRulesSource.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Equatable

    @Test("Equatable — 같은 값")
    func equatableSame() {
        #expect(WorkingRulesSource.inline("abc") == WorkingRulesSource.inline("abc"))
        #expect(WorkingRulesSource.filePath("/a") == WorkingRulesSource.filePath("/a"))
    }

    @Test("Equatable — 다른 값")
    func equatableDifferent() {
        #expect(WorkingRulesSource.inline("a") != WorkingRulesSource.inline("b"))
        #expect(WorkingRulesSource.inline("a") != WorkingRulesSource.filePath("a"))
    }
}
