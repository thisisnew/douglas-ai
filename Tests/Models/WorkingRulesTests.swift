import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkingRulesSource Tests")
struct WorkingRulesTests {

    // MARK: - resolve

    @Test("inline — 텍스트 그대로 반환")
    func resolveInline() {
        let rules = WorkingRulesSource(inlineText: "브랜치 전략: feature/xxx 형식 사용")
        #expect(rules.resolve() == "브랜치 전략: feature/xxx 형식 사용")
    }

    @Test("filePaths — 존재하는 파일 읽기")
    func resolveFilePathsExists() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("test-rules-\(UUID().uuidString).txt")
        try "커밋 메시지는 한글로 작성".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let rules = WorkingRulesSource(filePaths: [file.path])
        #expect(rules.resolve() == "커밋 메시지는 한글로 작성")
    }

    @Test("filePaths — 여러 파일 합치기")
    func resolveMultipleFiles() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file1 = tmpDir.appendingPathComponent("rules1-\(UUID().uuidString).txt")
        let file2 = tmpDir.appendingPathComponent("rules2-\(UUID().uuidString).txt")
        try "규칙 A".write(to: file1, atomically: true, encoding: .utf8)
        try "규칙 B".write(to: file2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }

        let rules = WorkingRulesSource(filePaths: [file1.path, file2.path])
        let resolved = rules.resolve()
        #expect(resolved.contains("규칙 A"))
        #expect(resolved.contains("규칙 B"))
    }

    @Test("combined — 인라인 + 파일 합산")
    func resolveCombined() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("rules-combined-\(UUID().uuidString).txt")
        try "파일 규칙".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let rules = WorkingRulesSource(inlineText: "인라인 규칙", filePaths: [file.path])
        let resolved = rules.resolve()
        #expect(resolved.contains("인라인 규칙"))
        #expect(resolved.contains("파일 규칙"))
    }

    @Test("filePaths — 존재하지 않는 파일은 경고 메시지")
    func resolveFilePathsNotExists() {
        let rules = WorkingRulesSource(filePaths: ["/nonexistent/path/rules.txt"])
        let result = rules.resolve()
        #expect(result.contains("경고"))
        #expect(result.contains("rules.txt"))
    }

    @Test("filePaths — 빈 파일은 경고 메시지")
    func resolveFilePathsEmpty() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("test-empty-rules-\(UUID().uuidString).txt")
        try "".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let rules = WorkingRulesSource(filePaths: [file.path])
        let result = rules.resolve()
        #expect(result.contains("경고"))
    }

    // MARK: - isEmpty

    @Test("isEmpty — 빈 인라인 + 빈 파일 배열")
    func isEmptyBoth() {
        #expect(WorkingRulesSource(inlineText: "", filePaths: []).isEmpty == true)
        #expect(WorkingRulesSource(inlineText: "  \n ", filePaths: []).isEmpty == true)
        #expect(WorkingRulesSource.empty.isEmpty == true)
    }

    @Test("isEmpty — 인라인 내용 있음")
    func isEmptyInlineNotBlank() {
        #expect(WorkingRulesSource(inlineText: "규칙").isEmpty == false)
    }

    @Test("isEmpty — 파일 경로 있음")
    func isEmptyFilePathsNotBlank() {
        #expect(WorkingRulesSource(filePaths: ["/path/to/rules"]).isEmpty == false)
    }

    // MARK: - displaySummary

    @Test("displaySummary — 인라인만")
    func displaySummaryInlineOnly() {
        let rules = WorkingRulesSource(inlineText: "짧은 규칙")
        #expect(rules.displaySummary == "짧은 규칙")
    }

    @Test("displaySummary — 인라인 긴 텍스트 잘림")
    func displaySummaryInlineLong() {
        let long = String(repeating: "가", count: 100)
        let rules = WorkingRulesSource(inlineText: long)
        #expect(rules.displaySummary.hasSuffix("..."))
    }

    @Test("displaySummary — 파일만")
    func displaySummaryFileOnly() {
        let rules = WorkingRulesSource(filePaths: ["/Users/test/project/.cursorrules"])
        #expect(rules.displaySummary == "파일: .cursorrules")
    }

    @Test("displaySummary — 인라인 + 파일 합산")
    func displaySummaryCombined() {
        let rules = WorkingRulesSource(inlineText: "인라인", filePaths: ["/path/to/a.md"])
        #expect(rules.displaySummary.contains("인라인"))
        #expect(rules.displaySummary.contains("파일: a.md"))
        #expect(rules.displaySummary.contains(" + "))
    }

    // MARK: - Codable

    @Test("Codable 라운드트립")
    func codableRoundTrip() throws {
        let original = WorkingRulesSource(inlineText: "테스트 규칙", filePaths: ["/path/to/rules.md"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkingRulesSource.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable 레거시 — inline enum → struct")
    func codableLegacyInline() throws {
        let json = #"{"type":"inline","inline":"레거시 텍스트"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkingRulesSource.self, from: data)
        #expect(decoded.inlineText == "레거시 텍스트")
        #expect(decoded.filePaths.isEmpty)
    }

    @Test("Codable 레거시 — filePath(String) → struct")
    func codableLegacyFilePath() throws {
        let json = #"{"type":"filePath","filePath":"/legacy/path"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkingRulesSource.self, from: data)
        #expect(decoded.inlineText.isEmpty)
        #expect(decoded.filePaths == ["/legacy/path"])
    }

    @Test("Codable 레거시 — filePaths([String]) → struct")
    func codableLegacyFilePaths() throws {
        let json = #"{"type":"filePaths","filePaths":["/a","/b"]}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkingRulesSource.self, from: data)
        #expect(decoded.inlineText.isEmpty)
        #expect(decoded.filePaths == ["/a", "/b"])
    }

    // MARK: - Equatable

    @Test("Equatable — 같은 값")
    func equatableSame() {
        #expect(WorkingRulesSource(inlineText: "abc") == WorkingRulesSource(inlineText: "abc"))
        #expect(WorkingRulesSource(filePaths: ["/a"]) == WorkingRulesSource(filePaths: ["/a"]))
    }

    @Test("Equatable — 다른 값")
    func equatableDifferent() {
        #expect(WorkingRulesSource(inlineText: "a") != WorkingRulesSource(inlineText: "b"))
        #expect(WorkingRulesSource(inlineText: "a") != WorkingRulesSource(filePaths: ["/a"]))
    }
}
