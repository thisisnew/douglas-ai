import Foundation

/// DOUGLAS 에이전트 매니페스트 — 플랫폼 무관한 이식 포맷
///
/// `.douglas` 확장자의 JSON 파일로 저장되며,
/// 어떤 런타임이든 이 포맷을 해석하면 동일한 에이전트 팀을 재구성할 수 있다.
struct AgentManifest: Codable {
    /// 포맷 버전 (하위 호환용)
    let formatVersion: Int
    /// 내보낸 시각
    let exportedAt: Date
    /// 내보낸 애플리케이션 이름
    let exportedFrom: String
    /// 에이전트 목록
    let agents: [AgentEntry]

    static let currentFormatVersion = 1
}

extension AgentManifest {
    /// 단일 에이전트의 이식 가능한 정의
    struct AgentEntry: Codable {
        /// 에이전트 이름
        let name: String
        /// 시스템 프롬프트 (페르소나)
        let persona: String
        /// 마스터 에이전트 여부
        let isMaster: Bool
        /// 선호 프로바이더 타입 ("OpenAI", "Anthropic" 등 — 자격증명 아님)
        let providerType: String
        /// 선호 모델 ("claude-sonnet-4-6" 등)
        let preferredModel: String
        /// 작업 규칙 (resolve된 인라인 텍스트, nil이면 규칙 없음)
        let workingRules: String?
        /// 아바타 이미지 (PNG base64, nil이면 이미지 없음)
        let avatarBase64: String?
        // Plan C: 에이전트 카드 확장 필드
        let skillTags: [String]?
        let workModes: [String]?          // WorkMode rawValue 배열
        let outputStyles: [String]?       // OutputStyle rawValue 배열
        let restrictions: [String]?       // AgentRestriction rawValue 배열
        let actionPermissions: [String]?  // ActionScope rawValue 배열
    }
}

// MARK: - Agent ↔ AgentEntry 변환

extension AgentManifest.AgentEntry {
    /// Agent → AgentEntry 변환
    init(from agent: Agent) {
        name = agent.name
        persona = agent.persona
        isMaster = agent.isMaster
        providerType = agent.providerName
        preferredModel = agent.modelName

        if let rules = agent.workingRules, !rules.isEmpty {
            workingRules = rules.resolve()
        } else {
            workingRules = nil
        }

        if agent.hasImage, let data = agent.imageData {
            avatarBase64 = data.base64EncodedString()
        } else {
            avatarBase64 = nil
        }

        // Plan C: 에이전트 카드 확장 필드 (비어있으면 nil로 — 역호환)
        skillTags = agent.skillTags.isEmpty ? nil : agent.skillTags
        workModes = agent.workModes.isEmpty ? nil : agent.workModes.map(\.rawValue)
        outputStyles = agent.outputStyles.isEmpty ? nil : agent.outputStyles.map(\.rawValue)
        restrictions = agent.restrictions.isEmpty ? nil : agent.restrictions.map(\.rawValue)
        actionPermissions = agent.actionPermissions.isEmpty ? nil : agent.actionPermissions.map(\.rawValue)
    }

    /// AgentEntry → Agent 변환 (새 UUID 발급)
    func toAgent() -> Agent {
        let imageData: Data? = avatarBase64.flatMap { Data(base64Encoded: $0) }

        let rules: WorkingRulesSource?
        if let text = workingRules, !text.isEmpty {
            rules = WorkingRulesSource(inlineText: text)
        } else {
            rules = nil
        }

        // Plan C: 에이전트 카드 확장 필드 복원
        let decodedModes: Set<WorkMode> = Set(workModes?.compactMap { WorkMode(rawValue: $0) } ?? [])
        let decodedOutputs: Set<OutputStyle> = Set(outputStyles?.compactMap { OutputStyle(rawValue: $0) } ?? [])
        let decodedRestrictions: Set<AgentRestriction> = Set(restrictions?.compactMap { AgentRestriction(rawValue: $0) } ?? [])
        let decodedPermissions: Set<ActionScope> = Set(actionPermissions?.compactMap { ActionScope(rawValue: $0) } ?? [])

        return Agent(
            name: name,
            persona: persona,
            providerName: providerType,
            modelName: preferredModel,
            isMaster: false, // 마스터는 import 시 항상 무시
            imageData: imageData,
            workingRules: rules,
            skillTags: skillTags ?? [],
            workModes: decodedModes,
            outputStyles: decodedOutputs,
            restrictions: decodedRestrictions,
            actionPermissions: decodedPermissions
        )
    }
}

// MARK: - 이름 중복 해결

extension AgentManifest {
    /// 기존 에이전트와 이름 중복 시 "(2)", "(3)" 등 접미어 추가
    static func deduplicateName(_ name: String, existing: [Agent]) -> String {
        let existingNames = Set(existing.map(\.name))
        if !existingNames.contains(name) { return name }
        var counter = 2
        while existingNames.contains("\(name) (\(counter))") {
            counter += 1
        }
        return "\(name) (\(counter))"
    }
}
