import Foundation

/// 문서 유형 (documentation intent에서 선택)
enum DocumentType: String, CaseIterable, Codable, Hashable {
    case prd                // Product Requirements Document
    case technicalDesign    // 기술 설계서
    case apiDoc             // API 문서
    case testPlan           // 테스트 계획서
    case report             // 보고서
    case freeform           // 자유 형식

    var displayName: String {
        switch self {
        case .prd:             return "PRD"
        case .technicalDesign: return "기술 설계서"
        case .apiDoc:          return "API 문서"
        case .testPlan:        return "테스트 계획서"
        case .report:          return "보고서"
        case .freeform:        return "자유 형식"
        }
    }

    var subtitle: String {
        switch self {
        case .prd:             return "제품 요구사항 정의서"
        case .technicalDesign: return "아키텍처·설계 문서"
        case .apiDoc:          return "API 엔드포인트·스키마 문서"
        case .testPlan:        return "테스트 전략·케이스 계획"
        case .report:          return "분석·조사 결과 보고서"
        case .freeform:        return "사용자 정의 구조"
        }
    }

    var iconName: String {
        switch self {
        case .prd:             return "list.clipboard"
        case .technicalDesign: return "cpu"
        case .apiDoc:          return "network"
        case .testPlan:        return "checkmark.shield"
        case .report:          return "chart.bar.doc.horizontal"
        case .freeform:        return "pencil.and.outline"
        }
    }

    /// 섹션 구조 가이드 (프롬프트 주입용)
    var templateSections: [String] {
        switch self {
        case .prd:
            return [
                "배경 및 맥락 (Background)",
                "문제 정의 (Problem Statement)",
                "목표 및 성공 지표 (Goals & Success Metrics)",
                "요구사항 (Requirements)",
                "비기능 요구사항 (Non-functional Requirements)",
                "범위 외 항목 (Out of Scope)",
                "일정 및 마일스톤 (Timeline)",
            ]
        case .technicalDesign:
            return [
                "개요 (Overview)",
                "현재 상태 분석 (Current State)",
                "제안 설계 (Proposed Design)",
                "시스템 아키텍처 (Architecture)",
                "데이터 모델 (Data Model)",
                "API 설계 (API Design)",
                "보안 고려사항 (Security)",
                "테스트 전략 (Testing Strategy)",
                "마이그레이션 계획 (Migration Plan)",
            ]
        case .apiDoc:
            return [
                "개요 (Overview)",
                "인증 (Authentication)",
                "엔드포인트 목록 (Endpoints)",
                "요청/응답 스키마 (Request/Response Schema)",
                "에러 코드 (Error Codes)",
                "사용 예시 (Usage Examples)",
                "제한사항 (Rate Limits & Constraints)",
            ]
        case .testPlan:
            return [
                "테스트 범위 (Scope)",
                "테스트 전략 (Strategy)",
                "테스트 환경 (Environment)",
                "테스트 케이스 (Test Cases)",
                "진입/종료 기준 (Entry/Exit Criteria)",
                "리스크 및 대응 (Risks & Mitigation)",
            ]
        case .report:
            return [
                "요약 (Executive Summary)",
                "배경 (Background)",
                "분석 방법론 (Methodology)",
                "주요 발견사항 (Key Findings)",
                "결론 및 권고 (Conclusions & Recommendations)",
            ]
        case .freeform:
            return []
        }
    }

    /// 프롬프트 주입용 템플릿 문자열
    func templatePromptBlock() -> String {
        guard !templateSections.isEmpty else { return "" }
        let sections = templateSections.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        return """
        [문서 유형: \(displayName)]
        권장 섹션 구조:
        \(sections)

        위 구조는 가이드라인입니다. 사용자의 요구에 맞게 섹션을 추가·제거·변경할 수 있습니다.
        """
    }
}
