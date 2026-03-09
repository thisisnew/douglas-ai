import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkRuleMatcher Tests")
struct WorkRuleMatcherTests {

    private func makeRule(
        _ name: String,
        summary: String = "",
        alwaysActive: Bool = false
    ) -> WorkRule {
        WorkRule(name: name, summary: summary, content: .inline("내용"), isAlwaysActive: alwaysActive)
    }

    // MARK: - 빈 입력

    @Test("빈 규칙 배열 → 빈 Set 반환")
    func emptyRulesReturnsEmptySet() {
        let result = WorkRuleMatcher.match(rules: [], taskText: "코딩해줘")
        #expect(result.isEmpty)
    }

    @Test("빈 태스크 텍스트 → 키워드 매칭 불가 → 전체 폴백")
    func emptyTaskTextFallsBackToAll() {
        let rules = [makeRule("코딩 규칙"), makeRule("PR 규칙")]
        let result = WorkRuleMatcher.match(rules: rules, taskText: "")
        #expect(result.count == 2)
    }

    // MARK: - isAlwaysActive 단독

    @Test("isAlwaysActive 규칙만 존재 + 동적 매칭 0건 → 전체 폴백")
    func singleAlwaysActiveOnlyFallsBackToAll() {
        let rule = makeRule("공통 규칙", alwaysActive: true)
        let result = WorkRuleMatcher.match(rules: [rule], taskText: "무관한 텍스트")
        // 동적 매칭 0건이므로 폴백 → 전체(1개) 반환
        #expect(result.count == 1)
        #expect(result.contains(rule.id))
    }

    @Test("isAlwaysActive만 매칭되고 동적 매칭 0건 → 전체 규칙 포함")
    func alwaysActivePlusDynamicZeroFallsBackToAll() {
        let rules = [
            makeRule("공통", alwaysActive: true),
            makeRule("코딩 규칙"),
            makeRule("배포 규칙"),
        ]
        let result = WorkRuleMatcher.match(rules: rules, taskText: "날씨 알려줘")
        #expect(result.count == 3)
    }

    // MARK: - 키워드 매칭

    @Test("이름 키워드로 특정 규칙 활성화")
    func keywordMatchActivatesSpecificRule() {
        let coding = makeRule("코딩 규칙")
        let deploy = makeRule("배포 규칙")
        let result = WorkRuleMatcher.match(rules: [coding, deploy], taskText: "코딩 작업 시작")
        #expect(result.contains(coding.id))
        #expect(!result.contains(deploy.id))
    }

    @Test("요약 키워드로 매칭")
    func matchBySummaryKeyword() {
        let rule = makeRule("규칙A", summary: "리팩토링, 구조 개선 관련")
        let other = makeRule("규칙B", summary: "문서 작성 관련")
        let result = WorkRuleMatcher.match(rules: [rule, other], taskText: "리팩토링 해줘")
        #expect(result.contains(rule.id))
        #expect(!result.contains(other.id))
    }

    @Test("복수 규칙 동시 매칭")
    func multipleRulesMatchSimultaneously() {
        let ruleA = makeRule("코딩 규칙", summary: "구현 관련")
        let ruleB = makeRule("테스트 규칙", summary: "코딩 테스트 관련")
        let ruleC = makeRule("배포 규칙")
        let result = WorkRuleMatcher.match(rules: [ruleA, ruleB, ruleC], taskText: "코딩 작업")
        #expect(result.contains(ruleA.id))
        #expect(result.contains(ruleB.id))
        #expect(!result.contains(ruleC.id))
    }

    // MARK: - 대소문자

    @Test("대소문자 무시 매칭 — 영문")
    func caseInsensitiveMatchingEnglish() {
        let rule = makeRule("API 규칙", summary: "REST endpoint")
        let result = WorkRuleMatcher.match(rules: [rule], taskText: "api endpoint 만들어줘")
        #expect(result.contains(rule.id))
    }

    @Test("대소문자 혼합 — 규칙 이름 대문자, 태스크 소문자")
    func caseInsensitiveMixedCase() {
        let rule = makeRule("README 작성")
        let result = WorkRuleMatcher.match(rules: [rule], taskText: "readme 업데이트")
        #expect(result.contains(rule.id))
    }

    // MARK: - alwaysActive + 동적 매칭 혼합

    @Test("alwaysActive + 동적 매칭 동시 → 폴백 없이 매칭된 것만 반환")
    func alwaysActivePlusDynamicMatchNoFallback() {
        let always = makeRule("공통 규칙", alwaysActive: true)
        let coding = makeRule("코딩 규칙")
        let deploy = makeRule("배포 규칙")
        let result = WorkRuleMatcher.match(rules: [always, coding, deploy], taskText: "코딩해줘")
        #expect(result.contains(always.id))
        #expect(result.contains(coding.id))
        #expect(!result.contains(deploy.id))
        #expect(result.count == 2)
    }

    // MARK: - 매칭 실패 폴백

    @Test("키워드 매칭 전혀 없음 → 전체 규칙 폴백")
    func noKeywordMatchFallsBackToAllRules() {
        let rules = [
            makeRule("코딩 규칙"),
            makeRule("PR 규칙"),
            makeRule("배포 규칙"),
        ]
        let result = WorkRuleMatcher.match(rules: rules, taskText: "안녕하세요 반갑습니다")
        #expect(result.count == 3)
        for rule in rules {
            #expect(result.contains(rule.id))
        }
    }

    // MARK: - 2글자 미만 키워드 필터링

    @Test("1글자 키워드 무시 — 매칭 불가로 폴백")
    func singleCharKeywordsIgnored() {
        // 이름 "A B"에서 "A", "B" 모두 1글자 → 키워드 0개 → 매칭 불가
        let rule = makeRule("A B", summary: "C D")
        let result = WorkRuleMatcher.match(rules: [rule], taskText: "A B C D")
        // 동적 매칭 0건 → 폴백으로 전체 반환
        #expect(result.count == 1)
        #expect(result.contains(rule.id))
    }

    @Test("2글자 키워드는 정상 매칭")
    func twoCharKeywordsMatch() {
        let rule = makeRule("AB 규칙")
        let result = WorkRuleMatcher.match(rules: [rule], taskText: "AB 작업해줘")
        // "ab"(2글자)가 태스크에 포함 → 매칭 성공
        #expect(result.contains(rule.id))
    }

    // MARK: - 구두점/구분자 처리

    @Test("구두점 구분자 — 중간점(·) 분리")
    func middleDotSeparator() {
        let rule = makeRule("규칙", summary: "코딩·배포·테스트")
        let result = WorkRuleMatcher.match(rules: [rule], taskText: "배포 시작")
        #expect(result.contains(rule.id))
    }

    @Test("슬래시·세미콜론·파이프 구분자 분리")
    func slashSemicolonPipeSeparators() {
        let ruleSlash = makeRule("규칙A", summary: "코딩/리뷰/배포")
        let ruleSemicolon = makeRule("규칙B", summary: "빌드;테스트;검증")
        let rulePipe = makeRule("규칙C", summary: "설계|구현|검토")

        let resultSlash = WorkRuleMatcher.match(rules: [ruleSlash], taskText: "리뷰 요청")
        #expect(resultSlash.contains(ruleSlash.id))

        let resultSemicolon = WorkRuleMatcher.match(rules: [ruleSemicolon], taskText: "빌드 실행")
        #expect(resultSemicolon.contains(ruleSemicolon.id))

        let resultPipe = WorkRuleMatcher.match(rules: [rulePipe], taskText: "검토 부탁")
        #expect(resultPipe.contains(rulePipe.id))
    }

    @Test("쉼표 구분자 — 키워드 개별 분리")
    func commaSeparator() {
        let rule = makeRule("규칙", summary: "리팩토링,최적화,정리")
        let result = WorkRuleMatcher.match(rules: [rule], taskText: "최적화 해줘")
        #expect(result.contains(rule.id))
    }
}
