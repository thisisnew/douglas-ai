import Foundation

/// 단계 실행 프롬프트 조립 유틸리티 (순수 함수, 테스트 용이)
enum StepPromptBuilder {

    /// `fullTask`에 `[사용자 추가 지시]` 마커가 포함되어 있으면 `stepPrompt` 끝에 주입한다.
    /// - Parameters:
    ///   - stepPrompt: 기본 단계 프롬프트
    ///   - fullTask: StepExecutionEngine이 구성한 전체 작업 문자열 (사용자 지시 포함 가능)
    /// - Returns: 사용자 지시가 주입된 프롬프트 (없으면 원본 그대로)
    static func injectDirective(into stepPrompt: String, from fullTask: String) -> String {
        let marker = "[사용자 추가 지시]"
        guard fullTask.contains(marker),
              let range = fullTask.range(of: marker) else {
            return stepPrompt
        }
        let directive = String(fullTask[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directive.isEmpty else { return stepPrompt }
        return stepPrompt + "\n\n[사용자 추가 지시 — 반드시 최우선으로 반영하세요]\n\(directive)"
    }

    /// 에이전트 작업 컨텍스트 요약 문자열 생성
    static func buildContextSummary(ruleCount: Int, toolCount: Int, artifactCount: Int) -> String {
        [
            ruleCount > 0 ? "업무규칙 \(ruleCount)건" : nil,
            "도구 \(toolCount)종",
            artifactCount > 0 ? "산출물 \(artifactCount)건" : nil
        ].compactMap { $0 }.joined(separator: " · ")
    }
}
