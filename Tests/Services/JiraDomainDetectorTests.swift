import Testing
import Foundation
@testable import DOUGLAS

@Suite("JiraDomainDetector 도메인 감지")
struct JiraDomainDetectorTests {

    // MARK: - 단일 도메인

    @Test("백엔드 키워드 감지 — API, 서버, 엔드포인트")
    func detectBackend() {
        let hints = JiraDomainDetector.detect(summary: "API 엔드포인트 추가", description: "서버에 새 REST API 추가")
        #expect(hints.contains(where: { $0.domain == "백엔드" }))
    }

    @Test("프론트엔드 키워드 감지 — UI, 화면, 컴포넌트")
    func detectFrontend() {
        let hints = JiraDomainDetector.detect(summary: "로그인 화면 UI 수정", description: "컴포넌트 레이아웃 개선")
        #expect(hints.contains(where: { $0.domain == "프론트엔드" }))
    }

    @Test("인프라 키워드 감지 — CI/CD, Docker")
    func detectInfra() {
        let hints = JiraDomainDetector.detect(summary: "CI/CD 파이프라인 구축", description: "Docker 기반 배포")
        #expect(hints.contains(where: { $0.domain == "인프라" }))
    }

    @Test("QA 키워드 감지 — 테스트, 검증")
    func detectQA() {
        let hints = JiraDomainDetector.detect(summary: "로그인 기능 테스트 계획", description: "QA TC 작성")
        #expect(hints.contains(where: { $0.domain == "QA" }))
    }

    @Test("모바일 키워드 감지 — iOS, Android")
    func detectMobile() {
        let hints = JiraDomainDetector.detect(summary: "iOS 앱 푸시 알림", description: "")
        #expect(hints.contains(where: { $0.domain == "모바일" }))
    }

    @Test("데이터 키워드 감지 — ML, 파이프라인")
    func detectData() {
        let hints = JiraDomainDetector.detect(summary: "데이터 파이프라인 개선", description: "ETL 배치 최적화")
        #expect(hints.contains(where: { $0.domain == "데이터" }))
    }

    @Test("기획 키워드 감지 — PRD, 요구사항")
    func detectPlanning() {
        let hints = JiraDomainDetector.detect(summary: "신규 기능 PRD 작성", description: "요구사항 정리")
        #expect(hints.contains(where: { $0.domain == "기획" }))
    }

    @Test("디자인 키워드 감지 — UX, 피그마")
    func detectDesign() {
        let hints = JiraDomainDetector.detect(summary: "결제 화면 UX 개선", description: "피그마 시안 반영")
        #expect(hints.contains(where: { $0.domain == "디자인" }))
    }

    // MARK: - 복수 도메인

    @Test("백엔드 + 프론트엔드 동시 감지")
    func detectMultiple_backendAndFrontend() {
        let hints = JiraDomainDetector.detect(
            summary: "API 연동 + 결과 화면 표시",
            description: "백엔드 API를 호출하여 결과를 프론트 화면에 렌더링"
        )
        let domains = hints.map { $0.domain }
        #expect(domains.contains("백엔드"))
        #expect(domains.contains("프론트엔드"))
    }

    @Test("백엔드 + QA 동시 감지")
    func detectMultiple_backendAndQA() {
        let hints = JiraDomainDetector.detect(
            summary: "API 버그 수정 + 테스트 추가",
            description: "서버 엔드포인트 수정 후 TC 작성"
        )
        let domains = hints.map { $0.domain }
        #expect(domains.contains("백엔드"))
        #expect(domains.contains("QA"))
    }

    // MARK: - 미감지

    @Test("키워드 없는 텍스트 — 빈 배열")
    func detectNone() {
        let hints = JiraDomainDetector.detect(summary: "회의록 정리", description: "지난주 미팅 내용 요약")
        #expect(hints.isEmpty)
    }

    @Test("빈 문자열 — 빈 배열")
    func detectEmpty() {
        let hints = JiraDomainDetector.detect(summary: "", description: "")
        #expect(hints.isEmpty)
    }

    // MARK: - evidence 검증

    @Test("evidence에 매칭된 키워드 포함")
    func evidenceContainsKeywords() {
        let hints = JiraDomainDetector.detect(summary: "REST API 서버 구축", description: "")
        let backend = hints.first(where: { $0.domain == "백엔드" })
        #expect(backend != nil)
        #expect(backend!.evidence.contains(where: { $0.lowercased().contains("api") }))
    }

    // MARK: - formatHint

    @Test("formatHint — 힌트 있을 때 포맷 문자열 반환")
    func formatHint_withHints() {
        let hints = JiraDomainDetector.detect(
            summary: "API 연동 + 화면 표시",
            description: ""
        )
        let formatted = JiraDomainDetector.formatHint(hints)
        #expect(formatted != nil)
        #expect(formatted!.contains("백엔드"))
        #expect(formatted!.contains("프론트엔드"))
    }

    @Test("formatHint — 힌트 없으면 nil")
    func formatHint_empty() {
        let formatted = JiraDomainDetector.formatHint([])
        #expect(formatted == nil)
    }

    // MARK: - 대소문자 무관

    @Test("대소문자 무관 매칭 — React, docker")
    func caseInsensitive() {
        let hints = JiraDomainDetector.detect(summary: "React 컴포넌트", description: "docker 배포")
        let domains = hints.map { $0.domain }
        #expect(domains.contains("프론트엔드"))
        #expect(domains.contains("인프라"))
    }
}
