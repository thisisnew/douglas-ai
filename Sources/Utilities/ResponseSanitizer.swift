import Foundation

/// LLM 응답 텍스트 정제 유틸리티 — RoomManager 전역 함수에서 추출
/// 전역 함수는 하위 호환 포워더로 유지, 점진적으로 이 유틸리티로 전환
enum ResponseSanitizer {

    /// 에이전트 응답 끝에 붙은 선택지 텍스트 제거
    static func stripTrailingOptions(_ text: String) -> String {
        DOUGLAS.stripTrailingOptions(text)
    }

    /// Clarify 응답에서 Jira/인증 관련 환각 문장 제거
    static func stripHallucinatedAuthLines(_ text: String) -> String {
        DOUGLAS.stripHallucinatedAuthLines(text)
    }

    /// LLM 응답의 `~/` 경로를 절대경로로 확장
    static func expandTildePaths(_ text: String) -> String {
        DOUGLAS.expandTildePaths(text)
    }

    /// LLM 응답 정제 파이프라인 (3단계: 환각 제거 → 선택지 제거 → 경로 확장)
    static func sanitize(_ text: String) -> String {
        expandTildePaths(stripHallucinatedAuthLines(stripTrailingOptions(text)))
    }
}

/// [delegation] 블록 파서 — Clarify 응답에서 에이전트 위임 정보 추출
enum DelegationParser {

    /// [delegation]...[/delegation] 블록을 파싱
    static func parse(_ text: String) -> DelegationInfo {
        DOUGLAS.parseDelegationBlock(text)
    }

    /// [delegation]...[/delegation] 블록을 텍스트에서 제거
    static func strip(_ text: String) -> String {
        DOUGLAS.stripDelegationBlock(text)
    }
}
