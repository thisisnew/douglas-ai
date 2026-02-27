import Foundation

// MARK: - 역할 템플릿 카테고리

enum TemplateCategory: String, Codable, CaseIterable {
    case analysis    = "분석"
    case development = "개발"
    case quality     = "품질"
    case operations  = "운영"
}

// MARK: - 에이전트 역할 템플릿

struct AgentRoleTemplate: Identifiable, Codable {
    let id: String                          // "jira_analyst", "backend_dev" 등
    let name: String                        // "Jira 분석가"
    let icon: String                        // SF Symbol name
    let category: TemplateCategory
    let basePersona: String                 // 프로바이더 무관 기본 시스템 프롬프트
    let defaultPreset: CapabilityPreset     // 추천 도구 프리셋
    let providerHints: [String: String]     // ProviderType.rawValue → 모델별 추가 지시

    /// 프로바이더 타입에 맞는 최종 페르소나 생성
    func resolvedPersona(for providerType: String) -> String {
        let hint = providerHints[providerType] ?? ""
        if hint.isEmpty { return basePersona }
        return basePersona + "\n\n" + hint
    }
}
