import Foundation

// MARK: - 에이전트 매칭 (시스템 주도 Assembly)

/// 역할 요구사항을 기존 에이전트와 매칭 (키워드 + NLEmbedding 시맨틱 하이브리드)
enum AgentMatcher {

    /// NLEmbedding 기반 시맨틱 매처 (캐시 포함)
    static let semanticMatcher = SemanticMatcher()

    /// 역할 요구사항을 기존 에이전트와 매칭 (Plan C: 3단 가중치 + 신뢰도 임계값)
    static func matchRoles(
        requirements: [RoleRequirement],
        agents: [Agent],
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil,
        taskBrief: TaskBrief? = nil,
        config: MatchScoringConfig = .default,
        pluginSkillTags: [UUID: [String]] = [:],
        domainHints: [DomainHintDetector.DomainHint] = []
    ) -> [RoleRequirement] {
        var results = requirements
        var usedAgentIDs: Set<UUID> = []

        for i in results.indices {
            let (agent, confidence) = matchByTags(
                roleName: results[i].roleName,
                agents: agents,
                excluding: usedAgentIDs,
                intent: intent,
                documentType: documentType,
                taskBrief: taskBrief,
                position: results[i].position,
                config: config,
                pluginSkillTags: pluginSkillTags,
                domainHints: domainHints
            )

            if let agent {
                results[i].applyMatch(agent: agent, confidence: confidence, config: config)
                if results[i].isEffectivelyMatched {
                    usedAgentIDs.insert(agent.id)
                }
            } else {
                results[i].markUnmatched()
            }
        }

        return results
    }

    /// 필수 역할 중 매칭된 비율 (0.0 ~ 1.0)
    static func coverageRatio(_ requirements: [RoleRequirement]) -> Double {
        let required = requirements.filter { $0.priority == .required }
        guard !required.isEmpty else { return 1.0 }
        let matched = required.filter { $0.status == .matched || $0.status == .suggested }
        return Double(matched.count) / Double(required.count)
    }

    /// 최소 커버리지 (필수 역할 50%+) 충족 여부
    static func checkMinimumCoverage(_ requirements: [RoleRequirement]) -> Bool {
        coverageRatio(requirements) >= 0.5
    }

    /// artifact:role_requirements 산출물에서 RoleRequirement 파싱
    static func parseRoleRequirements(from content: String) -> [RoleRequirement] {
        // 형식: "- [필수] 역할이름: 사유" 또는 "- [선택] 역할이름: 사유"
        let lines = content.components(separatedBy: "\n")
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [") else { return nil }

            let priority: RoleRequirement.Priority
            if trimmed.contains("[필수]") {
                priority = .required
            } else if trimmed.contains("[선택]") {
                priority = .optional
            } else {
                priority = .required  // 기본값
            }

            // "] " 이후 텍스트에서 "역할: 사유" 추출
            guard let bracketEnd = trimmed.range(of: "] ") else { return nil }
            let remaining = String(trimmed[bracketEnd.upperBound...])

            let parts = remaining.split(separator: ":", maxSplits: 1)
            var roleNameRaw = String(parts.first ?? "").trimmingCharacters(in: .whitespaces)
            let reason = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            // position 파싱: "역할이름 (position=implementer)" → position 추출 + 역할이름에서 제거
            var position: WorkflowPosition?
            if let posRange = roleNameRaw.range(of: #"\s*\(position=(\w+)\)"#, options: .regularExpression) {
                let posMatch = roleNameRaw[posRange]
                if let eqRange = posMatch.range(of: "="),
                   let closeRange = posMatch.range(of: ")") {
                    let posValue = String(posMatch[eqRange.upperBound..<closeRange.lowerBound])
                    position = WorkflowPosition(rawValue: posValue)
                }
                roleNameRaw = roleNameRaw.replacingCharacters(in: posRange, with: "")
                    .trimmingCharacters(in: .whitespaces)
            }

            guard !roleNameRaw.isEmpty else { return nil }
            return RoleRequirement(roleName: roleNameRaw, reason: reason, priority: priority, position: position)
        }
    }

    // MARK: - 어휘 사전 (MatchingVocabulary 위임)

    private static let vocabulary = MatchingVocabulary.default

    /// 범용 접미사 여부 확인 (외부에서 사전 매칭 시 사용)
    static func isGenericSuffix(_ keyword: String) -> Bool {
        vocabulary.isGenericSuffix(keyword)
    }

    /// Plan C: 3단 가중치 태그 매칭 + 0-1 정규화 신뢰도
    /// 반환: (최고 매칭 에이전트, 신뢰도 0.0~1.0)
    static func matchByTags(
        roleName: String,
        agents: [Agent],
        excluding used: Set<UUID>,
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil,
        taskBrief: TaskBrief? = nil,
        position: WorkflowPosition? = nil,
        config: MatchScoringConfig = .default,
        pluginSkillTags: [UUID: [String]] = [:],  // 플러그인 주입 태그 (agent.id → tags)
        domainHints: [DomainHintDetector.DomainHint] = []
    ) -> (Agent?, Double) {
        var keywords = roleName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !vocabulary.isGenericSuffix($0) }

        // 동의어 확장 (개선안 E): "FE" → ["fe", "프론트엔드", "frontend", ...]
        // 정규화 기준은 원본 키워드 수 (확장으로 분모가 커지는 것 방지)
        let originalKeywordCount = keywords.count
        keywords = vocabulary.expandSynonyms(keywords).filter { $0.count >= 2 && !vocabulary.isGenericSuffix($0) }

        if documentType != nil {
            keywords = keywords.filter { !vocabulary.domainKeywords.contains($0) }
        }

        let hasKeywords = !keywords.isEmpty
        let preferredKWs = documentType?.preferredKeywords ?? []
        let useSemanticScoring = semanticMatcher.isAvailable

        guard hasKeywords || useSemanticScoring else { return (nil, 0) }

        let tier1Weight = config.tier1Weight
        let tier2Weight = config.tier2Weight
        let tier3Weight = config.tier3Weight

        // 시맨틱 스코어를 배치 사전 계산 (roleName 벡터 1회만 계산)
        let candidates = agents.filter { !used.contains($0.id) }
        let roleSemanticScores: [UUID: Double]
        let goalSemanticScores: [UUID: Double]
        if useSemanticScoring {
            roleSemanticScores = semanticMatcher.batchSimilarity(roleName: roleName, agents: candidates)
            if let goal = taskBrief?.goal, !goal.isEmpty {
                goalSemanticScores = semanticMatcher.batchSimilarity(roleName: goal, agents: candidates)
            } else {
                goalSemanticScores = [:]
            }
        } else {
            roleSemanticScores = [:]
            goalSemanticScores = [:]
        }

        var bestMatch: (agent: Agent, confidence: Double)?

        for agent in candidates {
            // --- Tier 1: skillTags 직접 매칭 (가중치 5) ---
            var tier1Score: Double = 0
            // 플러그인 주입 태그 합산
            let allSkillTags = agent.skillTags + (pluginSkillTags[agent.id] ?? [])
            if hasKeywords, !allSkillTags.isEmpty {
                let lowerTags = allSkillTags.map { $0.lowercased() }
                var tagHits = 0
                for keyword in keywords {
                    if lowerTags.contains(where: { vocabulary.containsWholeWord($0, keyword: keyword) }) {
                        tagHits += 1
                    }
                }
                for pkw in preferredKWs {
                    if lowerTags.contains(where: { vocabulary.containsWholeWord($0, keyword: pkw.lowercased()) }) {
                        tagHits += 1
                    }
                }
                let maxPossible = max(originalKeywordCount + preferredKWs.count, 1)
                tier1Score = min(Double(tagHits) / Double(maxPossible), 1.0)  // 0~1
            }

            // Jira 도메인 힌트 보너스: 티켓 도메인 evidence와 에이전트 skillTags 교차
            if !domainHints.isEmpty {
                let allEvidence = domainHints.flatMap { $0.evidence }
                let lowerTags = allSkillTags.map { $0.lowercased() }
                let domainHits = allEvidence.filter { ev in
                    lowerTags.contains(where: { vocabulary.containsWholeWord($0, keyword: ev) })
                }
                if !domainHits.isEmpty {
                    let bonus = min(Double(domainHits.count) / Double(allEvidence.count), 1.0) * config.jiraDomainBonus
                    tier1Score = min(tier1Score + bonus, 1.0)
                }
            }

            // --- Tier 2: workModes 매칭 (가중치 2) ---
            // TaskBrief.outputType이 있으면 동적 가중치 (개선안 F)
            var tier2Score: Double = 0
            if !agent.workModes.isEmpty {
                if let outputType = taskBrief?.outputType {
                    // TaskBrief 기반 동적 workMode 가중치
                    switch outputType {
                    case .code:
                        if agent.workModes.contains(.execute) { tier2Score = 1.0 }
                        else if agent.workModes.contains(.create) { tier2Score = 0.9 }
                        else if agent.workModes.contains(.review) { tier2Score = 0.4 }
                    case .document, .message:
                        if agent.workModes.contains(.create) { tier2Score = 1.0 }
                        else if agent.workModes.contains(.review) || agent.workModes.contains(.research) { tier2Score = 0.5 }
                    case .analysis, .data:
                        if agent.workModes.contains(.research) { tier2Score = 1.0 }
                        else if agent.workModes.contains(.review) { tier2Score = 0.7 }
                        else if agent.workModes.contains(.create) { tier2Score = 0.3 }
                    case .design:
                        if agent.workModes.contains(.create) { tier2Score = 1.0 }
                        else if agent.workModes.contains(.review) { tier2Score = 0.5 }
                    case .answer:
                        if agent.workModes.contains(.research) || agent.workModes.contains(.review) { tier2Score = 1.0 }
                    }
                } else if let intent = intent {
                    // 기존 intent 기반 폴백
                    switch intent {
                    case .task, .complex:
                        if agent.workModes.contains(.create) || agent.workModes.contains(.execute) {
                            tier2Score = 1.0
                        } else if agent.workModes.contains(.research) || agent.workModes.contains(.review) {
                            tier2Score = 0.5
                        }
                    case .research:
                        if agent.workModes.contains(.research) {
                            tier2Score = 1.0
                        } else if agent.workModes.contains(.review) {
                            tier2Score = 0.5
                        }
                    case .documentation:
                        if agent.workModes.contains(.create) {
                            tier2Score = 1.0
                        } else if agent.workModes.contains(.review) || agent.workModes.contains(.research) {
                            tier2Score = 0.5
                        }
                    case .quickAnswer, .discussion:
                        if agent.workModes.contains(.research) || agent.workModes.contains(.review) {
                            tier2Score = 1.0
                        }
                    }
                }
            }

            // PositionTemplate 보너스: intent별 필요 포지션과 에이전트 추론 포지션 교차
            if let intent = intent {
                let neededPositions = PositionTemplate.slots(for: intent).map { $0.position }
                let agentPositions = PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona)
                let positionOverlap = neededPositions.filter { agentPositions.contains($0) }
                if !positionOverlap.isEmpty {
                    let positionBonus = Double(positionOverlap.count) / Double(max(neededPositions.count, 1)) * config.positionTemplateMaxBonus
                    tier2Score = min(tier2Score + positionBonus, 1.0)
                }
            }

            // position 직접 매칭 보너스: LLM이 지정한 position과 에이전트 추론 포지션 교차
            if let pos = position, PositionInferenceService.inferPositions(workModes: agent.workModes, persona: agent.persona).contains(pos) {
                tier2Score = min(tier2Score + config.positionDirectBonus, 1.0)
            }

            // --- Tier 3: 키워드 + 시맨틱 폴백 (가중치 2) ---
            var tier3Score: Double = 0
            if hasKeywords {
                let lowerPersona = agent.persona.lowercased()
                let lowerName = agent.name.lowercased()
                let lowerRules = (agent.workingRules.flatMap { $0.isEmpty ? nil : $0 }?.resolve() ?? "").lowercased()

                var kwHits = 0
                for keyword in keywords {
                    if vocabulary.containsWholeWord(lowerName, keyword: keyword) { kwHits += 2 }
                    if vocabulary.containsWholeWord(lowerPersona, keyword: keyword) { kwHits += 1 }
                    if vocabulary.containsWholeWord(lowerRules, keyword: keyword) { kwHits += 1 }
                }
                for pkw in preferredKWs {
                    let lower = pkw.lowercased()
                    if vocabulary.containsWholeWord(lowerName, keyword: lower) { kwHits += 1 }
                    if vocabulary.containsWholeWord(lowerPersona, keyword: lower) { kwHits += 1 }
                }

                // 개선안 G: TaskBrief.goal 키워드 → 에이전트 매칭 보너스
                // goal의 핵심 키워드가 에이전트 name/persona에 있으면 추가 점수 (상한 5개)
                var goalKeywordCount = 0
                if let goal = taskBrief?.goal, !goal.isEmpty {
                    let goalKeywords = Array(extractSemanticKeywords(from: goal)
                        .filter { $0.count >= 2 && !vocabulary.isGenericSuffix($0) }
                        .prefix(config.goalKeywordLimit))
                    goalKeywordCount = goalKeywords.count
                    for gkw in goalKeywords {
                        if vocabulary.containsWholeWord(lowerName, keyword: gkw) { kwHits += 1 }
                        if vocabulary.containsWholeWord(lowerPersona, keyword: gkw) { kwHits += 1 }
                    }
                }

                let maxKw = max((originalKeywordCount + preferredKWs.count) * 4 + goalKeywordCount * 2, 1)
                let kwScore = min(Double(kwHits) / Double(maxKw), 1.0)

                if useSemanticScoring {
                    let semScore = max(0, roleSemanticScores[agent.id] ?? 0)
                    let goalSemScore = max(0, goalSemanticScores[agent.id] ?? 0)
                    let combinedSem = goalSemScore > 0 ? semScore * 0.6 + goalSemScore * 0.4 : semScore
                    tier3Score = kwScore * 0.5 + combinedSem * 0.5
                } else {
                    tier3Score = kwScore
                }
            } else if useSemanticScoring {
                tier3Score = max(0, roleSemanticScores[agent.id] ?? 0)
            }

            // --- 가중 합산 → 0~1 정규화 ---
            let totalWeight = tier1Weight + tier2Weight + tier3Weight
            var confidence = (tier1Score * tier1Weight + tier2Score * tier2Weight + tier3Score * tier3Weight) / totalWeight

            // OutputStyle 보너스: TaskBrief.outputType과 agent.outputStyles 교차 시 최종 점수에 가산
            if let outputType = taskBrief?.outputType, !agent.outputStyles.isEmpty {
                let outputStyleMapping: [OutputType: OutputStyle] = [
                    .code: .code, .document: .document, .data: .data,
                    .message: .communication, .analysis: .data, .design: .plan,
                ]
                if let mappedStyle = outputStyleMapping[outputType],
                   agent.outputStyles.contains(mappedStyle) {
                    confidence = min(confidence + config.outputStyleBonus, 1.0)
                }
            }

            // skillTags가 비어있으면 Tier 1 무효 → Tier 2+3만으로 재계산
            let adjustedConfidence: Double
            if allSkillTags.isEmpty {
                let fallbackWeight = tier2Weight + tier3Weight
                let fallbackConfidence = (tier2Score * tier2Weight + tier3Score * tier3Weight) / fallbackWeight
                adjustedConfidence = min(fallbackConfidence, config.emptyTagsCap)
            } else {
                adjustedConfidence = confidence
            }

            if adjustedConfidence > (bestMatch?.confidence ?? 0) {
                bestMatch = (agent, adjustedConfidence)
            }
        }

        return (bestMatch?.agent, bestMatch?.confidence ?? 0)
    }

    // MARK: - Fallback 매칭 (LLM 역할 분석 실패 시)

    /// 작업 키워드 기반으로 가장 적합한 에이전트 탐색
    /// - quickAnswer/비개발 작업 시 개발자 에이전트 제외
    /// - task/complex intent + 코드 키워드 → 개발자 에이전트 보너스
    static func findBestFallbackMatch(
        task: String,
        agents: [Agent],
        intent: WorkflowIntent?,
        pluginSkillTags: [UUID: [String]] = [:]
    ) -> Agent? {
        let taskKeywords = extractSemanticKeywords(from: task)
        let isQuickAnswer = intent == .quickAnswer
        let taskLower = task.lowercased()

        // 코드/구현 관련 키워드 감지 → 개발자 에이전트에 보너스
        let codeKeywords: Set<String> = ["코드", "구현", "개발", "코딩", "버그", "수정", "리팩토링", "배포",
                                          "code", "implement", "develop", "fix", "refactor", "deploy"]
        let isCodeTask = (intent == .task || intent == .complex) &&
            codeKeywords.contains(where: { taskLower.contains($0) })

        var bestMatch: (agent: Agent, score: Int)?
        for candidate in agents {
            if candidate.isDeveloperAgent && isQuickAnswer { continue }

            var score = 0
            let tags = (candidate.skillTags + (pluginSkillTags[candidate.id] ?? [])).map { $0.lowercased() }
            for kw in taskKeywords {
                if tags.contains(where: { $0.contains(kw) || kw.contains($0) }) { score += 3 }
                if candidate.name.lowercased().contains(kw) { score += 2 }
                if candidate.persona.lowercased().contains(kw) { score += 1 }
            }

            // 코드 작업 + 개발자 에이전트 → 보너스 (직접 키워드 매칭 없어도 적합)
            if isCodeTask && candidate.isDeveloperAgent { score += 5 }

            if score > (bestMatch?.score ?? 0) {
                bestMatch = (candidate, score)
            }
        }
        return bestMatch?.agent
    }

    /// 이름으로 에이전트 탐색 (정확 매칭 또는 부분 포함)
    static func findByName(_ name: String, among agents: [Agent]) -> Agent? {
        let target = name.lowercased()
        return agents.first {
            let agentName = $0.name.lowercased()
            return agentName == target
                || agentName.contains(target)
                || target.contains(agentName)
        }
    }

    /// 작업에 적합한 에이전트 이름/페르소나 제안 (생성 제안용)
    static func suggestAgentProfile(
        for task: String,
        intent: WorkflowIntent?,
        taskBrief: TaskBrief? = nil
    ) -> (name: String, persona: String) {
        let lower = task.lowercased()
        if lower.contains("번역") || lower.contains("translate") {
            return ("번역 전문가", "다국어 번역 및 현지화 전문가입니다.")
        }
        if lower.contains("트렌드") || lower.contains("동향") {
            return ("트렌드 분석가", "기술 트렌드와 산업 동향을 분석하는 전문가입니다.")
        }
        if lower.contains("코드") || lower.contains("개발") || lower.contains("구현") {
            return ("소프트웨어 엔지니어", "소프트웨어 설계 및 구현 전문가입니다.")
        }
        if lower.contains("문서") || lower.contains("보고서") || lower.contains("작성") {
            return ("문서 작성 전문가", "보고서, 기획서 등 문서 작성 전문가입니다.")
        }
        if intent == .quickAnswer {
            return ("질의응답 전문가", "다양한 주제에 대해 정확하고 이해하기 쉽게 답변하는 범용 질의응답 전문가입니다.")
        }
        if let brief = taskBrief {
            let domain = brief.goal.prefix(30)
            let name = (brief.outputType == .answer || brief.outputType == .analysis)
                ? "리서치 전문가" : "\(intent?.displayName ?? "범용") 전문가"
            return (name, "\(domain) 관련 질문에 답변하고 분석하는 전문가입니다.")
        }
        return ("범용 전문가", "'\(String(task.prefix(60)))' 작업을 수행하는 전문가입니다.")
    }

    // MARK: - 유사 에이전트 탐지

    /// 새 에이전트 등록 시 유사한 기존 에이전트 탐지 (이름 + 페르소나 양방향 매칭)
    static func findSimilarAgents(
        name: String,
        persona: String,
        among agents: [Agent]
    ) -> [Agent] {
        let newKeywords = extractSemanticKeywords(from: "\(name) \(persona)")
        guard !newKeywords.isEmpty else { return [] }

        return agents.filter { agent in
            let agentText = "\(agent.name) \(agent.persona)".lowercased()
            let agentKeywords = extractSemanticKeywords(from: "\(agent.name) \(agent.persona)")
            let newText = "\(name) \(persona)".lowercased()

            // 양방향: 새→기존, 기존→새 (한쪽이라도 2개+ 겹치면 유사)
            let forward = newKeywords.filter { agentText.contains($0) }.count
            let reverse = agentKeywords.filter { newText.contains($0) }.count

            return max(forward, reverse) >= 2
        }
    }

    // MARK: - 의미 키워드 추출 (KoreanTextUtils 위임)

    /// 한국어 조사 제거 + 스크립트 경계 분리로 의미 키워드 추출
    static func extractSemanticKeywords(from text: String) -> [String] {
        KoreanTextUtils.extractSemanticKeywords(from: text, excluding: vocabulary.genericSuffixes)
    }

    // MARK: - Jira issueType 기반 에이전트 보너스

    /// Jira 이슈 타입에 따른 에이전트 적합도 보너스 (0.0~0.15)
    /// Bug → reviewer/tester 우선, Story/Task → implementer 우선
    static func jiraIssueTypeBonus(issueType: String, agent: Agent) -> Double {
        let type = issueType.lowercased()
        let modes = agent.workModes

        switch type {
        case "bug", "버그":
            if modes.contains(.review) { return 0.15 }
            if agent.name.lowercased().contains("qa") || agent.persona.lowercased().contains("qa") { return 0.12 }
            return 0
        case "story", "스토리", "task", "작업":
            if modes.contains(.execute) || modes.contains(.create) { return 0.12 }
            return 0
        case "epic", "에픽":
            if modes.contains(.plan) { return 0.10 }
            return 0
        default:
            return 0
        }
    }
}
