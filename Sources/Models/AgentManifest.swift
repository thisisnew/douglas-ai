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
        let equippedPluginIDs: [String]?  // 장착된 플러그인 ID
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
        equippedPluginIDs = agent.equippedPluginIDs.isEmpty ? nil : agent.equippedPluginIDs
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
            equippedPluginIDs: equippedPluginIDs ?? []
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

// MARK: - Fingerprint 기반 중복 감지

extension AgentManifest {

    /// 에이전트의 본질적 동일성을 판별하는 해시
    /// name + persona 앞 200자 + skillTags.sorted를 결합하여 SHA256
    static func fingerprint(for agent: Agent) -> String {
        let personaPrefix = String(agent.persona.prefix(200))
        let sortedTags = agent.skillTags.sorted().joined(separator: ",")
        let input = "\(agent.name)|\(personaPrefix)|\(sortedTags)"
        return sha256Hash(input)
    }

    /// AgentEntry의 fingerprint (Agent와 동일 로직)
    static func entryFingerprint(for entry: AgentEntry) -> String {
        let personaPrefix = String(entry.persona.prefix(200))
        let sortedTags = (entry.skillTags ?? []).sorted().joined(separator: ",")
        let input = "\(entry.name)|\(personaPrefix)|\(sortedTags)"
        return sha256Hash(input)
    }

    /// 중복 매치 결과
    struct DuplicateMatch {
        let entry: AgentEntry
        let existingAgent: Agent
        let matchType: MatchType

        enum MatchType {
            case exact     // fingerprint 완전 일치
            case nameOnly  // 이름만 같음 (내용 다름)
        }
    }

    /// 임포트할 entries와 기존 agents 사이의 중복을 감지
    static func findDuplicates(entries: [AgentEntry], existing: [Agent]) -> [DuplicateMatch] {
        let existingFingerprints = Dictionary(
            existing.map { (fingerprint(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingNames = Dictionary(
            existing.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var matches: [DuplicateMatch] = []
        for entry in entries {
            let entryFP = entryFingerprint(for: entry)
            if let match = existingFingerprints[entryFP] {
                matches.append(DuplicateMatch(entry: entry, existingAgent: match, matchType: .exact))
            } else if let match = existingNames[entry.name] {
                matches.append(DuplicateMatch(entry: entry, existingAgent: match, matchType: .nameOnly))
            }
        }
        return matches
    }

    // MARK: - SHA256

    private static func sha256Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        // CC_SHA256 대신 CryptoKit-free 구현 (간단한 해시)
        // CryptoKit은 이미 KeychainHelper에서 import 중이므로 여기서도 사용 가능
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            // 간단한 해시: FNV-1a 128bit x2를 concatenate (SHA256 대용)
            // 완전한 충돌 방지는 아니지만 fingerprint 용도로 충분
            var h1: UInt64 = 14695981039346656037
            var h2: UInt64 = 14695981039346656037
            let prime: UInt64 = 1099511628211
            for (i, byte) in buffer.enumerated() {
                if i % 2 == 0 {
                    h1 ^= UInt64(byte)
                    h1 &*= prime
                } else {
                    h2 ^= UInt64(byte)
                    h2 &*= prime
                }
            }
            withUnsafeBytes(of: h1) { ptr in
                for i in 0..<8 { hash[i] = ptr[i] }
            }
            withUnsafeBytes(of: h2) { ptr in
                for i in 0..<8 { hash[8 + i] = ptr[i] }
            }
            // 나머지는 h1 ^ h2 변형
            var h3 = h1 ^ h2
            h3 &*= prime
            withUnsafeBytes(of: h3) { ptr in
                for i in 0..<8 { hash[16 + i] = ptr[i] }
            }
            var h4 = h1 &+ h2
            h4 &*= prime
            withUnsafeBytes(of: h4) { ptr in
                for i in 0..<8 { hash[24 + i] = ptr[i] }
            }
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
