import Testing
import Foundation
@testable import DOUGLAS

@Suite("AgentMatcher Tests")
struct AgentMatcherTests {

    // MARK: - Helpers

    private func makeAgent(
        name: String,
        persona: String,
        workingRules: WorkingRulesSource? = nil,
        skillTags: [String] = [],
        workModes: Set<WorkMode> = [],
        outputStyles: Set<OutputStyle> = []
    ) -> Agent {
        var agent = Agent(
            name: name,
            persona: persona,
            providerName: "TestProvider",
            modelName: "test-model",
            workingRules: workingRules,
            skillTags: skillTags
        )
        agent.workModes = workModes
        agent.outputStyles = outputStyles
        return agent
    }

    // MARK: - matchRoles

    @Test("matchRoles — 에이전트 없으면 모두 unmatched")
    func matchRolesNoAgents() {
        let requirements = [
            RoleRequirement(roleName: "백엔드 개발자"),
            RoleRequirement(roleName: "QA 엔지니어")
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [])
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.status == .unmatched })
    }

    @Test("matchRoles — skillTags + 이름 키워드 매칭")
    func matchRolesByName() {
        let agent = makeAgent(
            name: "백엔드 개발자",
            persona: "백엔드 서버 API 개발 전문",
            skillTags: ["백엔드", "서버", "api"]
        )
        let requirements = [
            RoleRequirement(roleName: "백엔드")
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [agent])
        #expect(results[0].status != .unmatched)
        #expect(results[0].matchedAgentID == agent.id)
    }

    @Test("matchRoles — skillTags + persona 키워드 매칭")
    func matchRolesByPersona() {
        let agent = makeAgent(
            name: "프론트엔드 개발자",
            persona: "React, TypeScript, 프론트엔드 UI 개발 전문",
            skillTags: ["프론트엔드", "react", "typescript"]
        )
        let requirements = [
            RoleRequirement(roleName: "프론트엔드")
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [agent])
        #expect(results[0].status != .unmatched)
        #expect(results[0].matchedAgentID == agent.id)
    }

    @Test("matchRoles — skillTags + 작업 규칙 키워드 매칭")
    func matchRolesByWorkingRules() {
        let agent = makeAgent(
            name: "React 개발자",
            persona: "React 코드 작성 전문",
            workingRules: WorkingRulesSource(inlineText: "React 컴포넌트는 함수형으로 작성. TypeScript 필수."),
            skillTags: ["react", "typescript"]
        )
        let requirements = [
            RoleRequirement(roleName: "React")
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [agent])
        #expect(results[0].status != .unmatched)
    }

    @Test("matchRoles — 에이전트 중복 사용 불가")
    func matchRolesNoDuplicateAgent() {
        let agent = makeAgent(
            name: "백엔드",
            persona: "백엔드 서버 개발 전문",
            skillTags: ["백엔드", "서버"]
        )
        let requirements = [
            RoleRequirement(roleName: "백엔드"),
            RoleRequirement(roleName: "백엔드")  // 같은 역할 두 번
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [agent])
        let matched = results.filter { $0.status != .unmatched }
        #expect(matched.count == 1)  // 에이전트 하나이므로 하나만 매칭
    }

    @Test("matchRoles — 여러 에이전트 매칭")
    func matchRolesMultiple() {
        let agents = [
            makeAgent(name: "백엔드", persona: "백엔드 서버 개발", skillTags: ["백엔드", "서버"]),
            makeAgent(name: "프론트", persona: "프론트엔드 UI 개발", skillTags: ["프론트엔드", "ui"]),
        ]
        let requirements = [
            RoleRequirement(roleName: "백엔드"),
            RoleRequirement(roleName: "프론트"),
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: agents)
        let matched = results.filter { $0.status != .unmatched }
        #expect(matched.count == 2)
    }

    // MARK: - coverageRatio

    @Test("coverageRatio — 필수 역할 없으면 1.0")
    func coverageNoRequired() {
        let requirements = [
            RoleRequirement(roleName: "보조", priority: .optional, status: .unmatched)
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 1.0)
    }

    @Test("coverageRatio — 전체 매칭 시 1.0")
    func coverageFullMatch() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .matched),
            RoleRequirement(roleName: "B", priority: .required, status: .matched),
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 1.0)
    }

    @Test("coverageRatio — 절반 매칭 시 0.5")
    func coverageHalf() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .matched),
            RoleRequirement(roleName: "B", priority: .required, status: .unmatched),
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 0.5)
    }

    @Test("coverageRatio — suggested도 매칭으로 인정")
    func coverageSuggested() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .suggested),
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 1.0)
    }

    @Test("coverageRatio — optional은 계산에서 제외")
    func coverageOptionalExcluded() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .matched),
            RoleRequirement(roleName: "B", priority: .optional, status: .unmatched),
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 1.0)
    }

    // MARK: - checkMinimumCoverage

    @Test("checkMinimumCoverage — 50% 이상이면 true")
    func minimumCoveragePass() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .matched),
            RoleRequirement(roleName: "B", priority: .required, status: .unmatched),
        ]
        #expect(AgentMatcher.checkMinimumCoverage(requirements) == true)
    }

    @Test("checkMinimumCoverage — 50% 미만이면 false")
    func minimumCoverageFail() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .unmatched),
            RoleRequirement(roleName: "B", priority: .required, status: .unmatched),
            RoleRequirement(roleName: "C", priority: .required, status: .matched),
        ]
        // 1/3 ≈ 0.33 < 0.5
        #expect(AgentMatcher.checkMinimumCoverage(requirements) == false)
    }

    @Test("checkMinimumCoverage — 빈 목록이면 true")
    func minimumCoverageEmpty() {
        #expect(AgentMatcher.checkMinimumCoverage([]) == true)
    }

    // MARK: - parseRoleRequirements

    @Test("parseRoleRequirements — 기본 파싱")
    func parseBasic() {
        let content = """
        - [필수] 백엔드 개발자: API 서버 구축
        - [선택] DevOps: CI/CD 파이프라인
        """
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results.count == 2)
        #expect(results[0].roleName == "백엔드 개발자")
        #expect(results[0].reason == "API 서버 구축")
        #expect(results[0].priority == .required)
        #expect(results[1].roleName == "DevOps")
        #expect(results[1].priority == .optional)
    }

    @Test("parseRoleRequirements — 사유 없는 항목")
    func parseNoReason() {
        let content = "- [필수] 프론트엔드"
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results.count == 1)
        #expect(results[0].roleName == "프론트엔드")
        #expect(results[0].reason == "")
    }

    @Test("parseRoleRequirements — 빈 문자열")
    func parseEmpty() {
        let results = AgentMatcher.parseRoleRequirements(from: "")
        #expect(results.isEmpty)
    }

    @Test("parseRoleRequirements — 잘못된 형식 무시")
    func parseInvalidFormat() {
        let content = """
        이것은 일반 텍스트
        - 대괄호 없음
        - [필수] 유효한 항목: 포함
        """
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results.count == 1)
        #expect(results[0].roleName == "유효한 항목")
    }

    @Test("parseRoleRequirements — 알 수 없는 태그는 required 기본값")
    func parseUnknownTag() {
        let content = "- [중요] 리드 개발자: 총괄"
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results.count == 1)
        #expect(results[0].priority == .required)  // 기본값
    }

    // MARK: - 문서 유형 설정 시 매칭

    @Test("matchByTags — documentType 설정 시 도메인 키워드 필터링")
    func matchByTagsDocFiltersDomainKeywords() {
        let backendDev = makeAgent(name: "백엔드 개발자", persona: "서버 개발 전문")
        let docWriter = makeAgent(
            name: "기술 문서 작성자",
            persona: "문서화 전문가, 테크니컬 라이터, API 문서"
        )
        // matchByTags 직접 호출: 도메인 키워드 필터링 후 올바른 에이전트 선택 검증
        let (agent, confidence) = AgentMatcher.matchByTags(
            roleName: "백엔드 API 문서 작성자",
            agents: [backendDev, docWriter],
            excluding: [],
            documentType: .apiDoc
        )
        // "백엔드" 도메인 키워드 필터링 → "api", "문서", "작성자" → docWriter가 최고 매칭
        #expect(agent?.id == docWriter.id)
        #expect(confidence > 0)
    }

    @Test("matchByTags — documentType + preferredKeywords 보너스")
    func matchByTagsDocPreferredKeywordBonus() {
        let qaAgent = makeAgent(name: "QA 전문가", persona: "테스트 전략, 품질 보증")
        let devAgent = makeAgent(name: "시니어 개발자", persona: "풀스택 개발")
        // matchByTags 직접 호출: preferredKeywords 보너스로 올바른 에이전트 우선 선택 검증
        let (agent, confidence) = AgentMatcher.matchByTags(
            roleName: "테스트 계획 작성자",
            agents: [qaAgent, devAgent],
            excluding: [],
            documentType: .testPlan
        )
        // preferredKeywords: "qa", "테스트", "품질" → qaAgent가 최고 매칭
        #expect(agent?.id == qaAgent.id)
        #expect(confidence > 0)
    }

    @Test("matchRoles — documentType nil이면 skillTags 기반 매칭")
    func matchRolesNonDocPreservesOldBehavior() {
        let backendDev = makeAgent(
            name: "백엔드 개발자",
            persona: "백엔드 서버 개발 전문",
            skillTags: ["백엔드", "서버", "api"]
        )
        let requirements = [
            RoleRequirement(roleName: "백엔드")
        ]
        let results = AgentMatcher.matchRoles(
            requirements: requirements,
            agents: [backendDev]
        )
        #expect(results[0].status != .unmatched)
        #expect(results[0].matchedAgentID == backendDev.id)
    }

    // MARK: - findBestFallbackMatch

    @Test("findBestFallbackMatch — 번역 키워드 → 번역 전문가 매칭")
    func fallbackMatchTranslation() {
        let translator = makeAgent(name: "번역 전문가", persona: "다국어 번역", skillTags: ["번역", "translate"])
        let dev = makeAgent(name: "백엔드 개발자", persona: "서버 개발", skillTags: ["백엔드"])
        let result = AgentMatcher.findBestFallbackMatch(task: "이거 번역해줘", agents: [dev, translator], intent: .quickAnswer)
        #expect(result?.id == translator.id)
    }

    @Test("findBestFallbackMatch — quickAnswer + 개발자만 → nil")
    func fallbackMatchDevOnlyQuickAnswer() {
        let dev = makeAgent(name: "백엔드 개발자", persona: "서버 개발", skillTags: ["백엔드"])
        let result = AgentMatcher.findBestFallbackMatch(task: "두쯔쿠가 뭐야", agents: [dev], intent: .quickAnswer)
        #expect(result == nil)
    }

    @Test("findBestFallbackMatch — task intent + 개발자 → 매칭")
    func fallbackMatchDevOnTask() {
        let dev = makeAgent(name: "백엔드 개발자", persona: "서버 개발", skillTags: ["백엔드"])
        let result = AgentMatcher.findBestFallbackMatch(task: "API 서버 구현", agents: [dev], intent: .task)
        #expect(result?.id == dev.id)
    }

    // MARK: - findByName

    @Test("findByName — 정확 매칭")
    func findByNameExact() {
        let agent = makeAgent(name: "질의응답 전문가", persona: "범용")
        let result = AgentMatcher.findByName("질의응답 전문가", among: [agent])
        #expect(result?.id == agent.id)
    }

    @Test("findByName — 부분 포함 매칭")
    func findByNamePartial() {
        let agent = makeAgent(name: "리서치 & 문서 전문가", persona: "조사 분석")
        let result = AgentMatcher.findByName("문서 전문가", among: [agent])
        #expect(result?.id == agent.id)
    }

    @Test("findByName — 매칭 없음")
    func findByNameNoMatch() {
        let agent = makeAgent(name: "백엔드 개발자", persona: "서버")
        let result = AgentMatcher.findByName("번역 전문가", among: [agent])
        #expect(result == nil)
    }

    @Test("findBestFallbackMatch — 코드 작업 + enriched task → 백엔드 개발자 매칭")
    func fallbackMatchCodeTaskEnriched() {
        let dev = makeAgent(name: "백엔드 개발자", persona: "서버 API 개발 전문", skillTags: ["백엔드", "서버", "api"])
        let qa = makeAgent(name: "QA 전문가", persona: "테스트 전략", skillTags: ["qa", "테스트"])
        // Jira URL만으로는 매칭 안됨
        let urlOnly = AgentMatcher.findBestFallbackMatch(
            task: "https://kurly0521.atlassian.net/browse/IBS-3279",
            agents: [dev, qa], intent: .task
        )
        // URL에 키워드가 없어서 매칭 실패하거나 점수 낮음
        // enriched task에 사용자 의도 포함되면 매칭됨
        let enriched = "https://kurly0521.atlassian.net/browse/IBS-3279 코드 작업. SignSpecificationInquiryExtensionRepository를 우선적으로 보면되고 연관 파일도 같이 보고 분석해서 작업해"
        let result = AgentMatcher.findBestFallbackMatch(
            task: enriched, agents: [dev, qa], intent: .task
        )
        #expect(result?.id == dev.id)
    }

    @Test("suggestAgentProfile — enriched task에서 코드 키워드 감지")
    func suggestProfileEnrichedCodeTask() {
        let urlOnly = AgentMatcher.suggestAgentProfile(
            for: "https://kurly0521.atlassian.net/browse/IBS-3279",
            intent: .task
        )
        // URL만으로는 "범용 전문가" 폴백
        #expect(urlOnly.name.contains("범용") || urlOnly.name.contains("엔지니어") || urlOnly.name.contains("전문가"))

        let enriched = AgentMatcher.suggestAgentProfile(
            for: "https://kurly0521.atlassian.net/browse/IBS-3279 코드 작업. 분석해서 작업해",
            intent: .task
        )
        // "코드" 키워드 감지 → 소프트웨어 엔지니어
        #expect(enriched.name == "소프트웨어 엔지니어")
    }

    @Test("matchRoles — documentType 설정 시 도메인 키워드만 있으면 unmatched")
    func matchRolesDocAllKeywordsFiltered() {
        let frontendDev = makeAgent(name: "프론트엔드 개발자", persona: "React UI")
        let requirements = [
            RoleRequirement(roleName: "프론트엔드")
        ]
        let results = AgentMatcher.matchRoles(
            requirements: requirements,
            agents: [frontendDev],
            documentType: .freeform
        )
        // "프론트엔드"가 도메인 키워드로 필터링 → 키워드 없음 → unmatched
        #expect(results[0].status == .unmatched)
    }

    // MARK: - 동의어 사전 (개선안 E)

    @Test("expandSynonyms — 'FE' → '프론트엔드' 포함")
    func synonymFE() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["fe"])
        #expect(expanded.contains("프론트엔드"))
        #expect(expanded.contains("frontend"))
        #expect(expanded.contains("fe"))  // 원본 유지
    }

    @Test("expandSynonyms — 'BE' → '백엔드' 포함")
    func synonymBE() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["be"])
        #expect(expanded.contains("백엔드"))
        #expect(expanded.contains("backend"))
    }

    @Test("expandSynonyms — 'devops' → '인프라', 'sre' 포함")
    func synonymDevOps() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["devops"])
        #expect(expanded.contains("인프라"))
    }

    @Test("expandSynonyms — 매칭 없는 키워드는 그대로 유지")
    func synonymNoMatch() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["xyzzy"])
        #expect(expanded == ["xyzzy"])
    }

    @Test("matchByTags — 동의어 확장으로 'FE 개발자' → 프론트엔드 에이전트 매칭")
    func matchByTagsWithSynonym() {
        let agent = makeAgent(
            name: "프론트엔드 개발자",
            persona: "React UI 개발 전문",
            skillTags: ["프론트엔드", "react", "ui"]
        )
        let (matched, confidence) = AgentMatcher.matchByTags(
            roleName: "FE 개발자",
            agents: [agent],
            excluding: []
        )
        #expect(matched?.id == agent.id)
        #expect(confidence > 0.3)
    }

    // MARK: - TaskBrief 기반 동적 가중치 (개선안 F)

    @Test("matchByTags — TaskBrief.outputType=code → create/execute workMode 우선")
    func taskBriefCodeWeighting() {
        let creator = makeAgent(name: "백엔드 A", persona: "서버 개발", skillTags: ["백엔드"], workModes: [.create, .execute])
        let reviewer = makeAgent(name: "백엔드 B", persona: "서버 리뷰", skillTags: ["백엔드"], workModes: [.review])

        let brief = TaskBrief(
            goal: "API 구현", constraints: [], successCriteria: [],
            nonGoals: [], overallRisk: .medium, outputType: .code
        )
        let (matched, _) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [reviewer, creator],
            excluding: [],
            intent: .task,
            taskBrief: brief
        )
        #expect(matched?.id == creator.id)
    }

    // MARK: - 목표 시맨틱 매칭 (개선안 G)

    @Test("matchByTags — TaskBrief.goal이 시맨틱 매칭에 반영됨")
    func taskBriefGoalSemanticBoost() {
        // goal에 "보안 감사" 키워드 → 보안 에이전트가 매칭 유리
        let securityAgent = makeAgent(name: "보안 전문가", persona: "보안 감사 및 취약점 분석 전문", skillTags: ["보안", "감사"])
        let devAgent = makeAgent(name: "백엔드 개발자", persona: "서버 개발 전문", skillTags: ["백엔드", "서버"])

        let brief = TaskBrief(
            goal: "보안 감사 실시 및 취약점 리포트 작성",
            constraints: [], successCriteria: [],
            nonGoals: [], overallRisk: .high, outputType: .analysis
        )
        // roleName이 모호할 때 goal이 매칭을 도와줌
        let (matched, _) = AgentMatcher.matchByTags(
            roleName: "감사 전문가",
            agents: [devAgent, securityAgent],
            excluding: [],
            intent: .task,
            taskBrief: brief
        )
        #expect(matched?.id == securityAgent.id)
    }

    @Test("matchByTags — TaskBrief.goal이 없으면 기존 동작 유지")
    func taskBriefNoGoalFallback() {
        let agent = makeAgent(name: "백엔드 개발자", persona: "서버 개발", skillTags: ["백엔드", "서버"])
        let (matched, confidence) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [agent],
            excluding: [],
            intent: .task,
            taskBrief: nil
        )
        #expect(matched?.id == agent.id)
        #expect(confidence > 0.3)
    }

    @Test("matchByTags — TaskBrief.outputType=analysis → research workMode 우선")
    func taskBriefAnalysisWeighting() {
        let researcher = makeAgent(name: "리서치 전문가", persona: "조사 분석", skillTags: ["리서치"], workModes: [.research])
        let creator = makeAgent(name: "문서 작성자", persona: "문서화", skillTags: ["문서"], workModes: [.create])

        let brief = TaskBrief(
            goal: "시장 조사", constraints: [], successCriteria: [],
            nonGoals: [], overallRisk: .low, outputType: .analysis
        )
        let (matched, _) = AgentMatcher.matchByTags(
            roleName: "리서치",
            agents: [creator, researcher],
            excluding: [],
            intent: .research,
            taskBrief: brief
        )
        #expect(matched?.id == researcher.id)
    }

    // MARK: - Phase 3: position 파싱

    @Test("parseRoleRequirements — position 파싱")
    func parseWithPosition() {
        let content = """
        - [필수] 백엔드 개발자 (position=implementer): API 서버 구축
        - [선택] QA 엔지니어 (position=tester): 테스트 계획
        """
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results.count == 2)
        #expect(results[0].roleName == "백엔드 개발자")
        #expect(results[0].position == .implementer)
        #expect(results[1].roleName == "QA 엔지니어")
        #expect(results[1].position == .tester)
    }

    @Test("parseRoleRequirements — position 없으면 nil")
    func parseWithoutPosition() {
        let content = "- [필수] 백엔드 개발자: API 서버 구축"
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results[0].position == nil)
    }

    @Test("parseRoleRequirements — 잘못된 position은 nil")
    func parseInvalidPosition() {
        let content = "- [필수] 백엔드 개발자 (position=unknown): API 서버 구축"
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results[0].position == nil)
        #expect(results[0].roleName == "백엔드 개발자")
    }

    @Test("matchByTags — position 파라미터로 직접 매칭 보너스")
    func positionDirectBonus() {
        // 같은 태그를 가진 두 에이전트 중 position 일치하는 쪽이 높은 점수
        let implementer = makeAgent(
            name: "백엔드 A",
            persona: "서버 구현 전문",
            skillTags: ["백엔드"],
            workModes: [.create, .execute]  // goodPositions: implementer
        )
        let reviewer = makeAgent(
            name: "백엔드 B",
            persona: "코드 리뷰 전문",
            skillTags: ["백엔드"],
            workModes: [.review]  // goodPositions: reviewer
        )
        let (matchedImpl, confImpl) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [implementer],
            excluding: [],
            position: .implementer
        )
        let (matchedRev, confRev) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [reviewer],
            excluding: [],
            position: .implementer
        )
        #expect(confImpl > confRev)
    }

    // MARK: - Phase 1: 스코어링 보정 + 어휘 사전 확장

    @Test("containsWholeWord — 'qa'가 'squad'에 매칭 안 됨")
    func wholeWordQaNotInSquad() {
        // "qa" 키워드로 "squad" 태그를 가진 에이전트가 false positive 매칭되면 안 됨
        let agent = makeAgent(
            name: "스쿼드 리더",
            persona: "팀 조율",
            skillTags: ["squad", "management"]
        )
        let (matched, confidence) = AgentMatcher.matchByTags(
            roleName: "QA 전문가",
            agents: [agent],
            excluding: []
        )
        // "qa"가 "squad"에 부분 매칭되면 안 됨 → confidence가 0.5 미만이어야
        #expect(confidence < 0.5)
    }

    @Test("containsWholeWord — 'ai'가 'main'에 매칭 안 됨")
    func wholeWordAiNotInMain() {
        let agent = makeAgent(
            name: "메인 관리자",
            persona: "메인 시스템 관리",
            skillTags: ["main", "system"]
        )
        let (matched, confidence) = AgentMatcher.matchByTags(
            roleName: "AI 전문가",
            agents: [agent],
            excluding: []
        )
        #expect(confidence < 0.5)
    }

    @Test("containsWholeWord — 정확 매칭은 여전히 동작")
    func wholeWordExactMatch() {
        let agent = makeAgent(
            name: "QA 전문가",
            persona: "품질 보증",
            skillTags: ["qa", "테스트"]
        )
        let (matched, confidence) = AgentMatcher.matchByTags(
            roleName: "QA",
            agents: [agent],
            excluding: []
        )
        #expect(matched?.id == agent.id)
        #expect(confidence > 0.3)
    }

    @Test("empty skillTags — confidence 상한 0.75")
    func emptySkillTagsCap() {
        // skillTags 비어있는 에이전트는 0.75 이하여야 함
        let agent = makeAgent(
            name: "백엔드 개발자",
            persona: "백엔드 서버 API 개발 전문",
            skillTags: [],  // 빈 태그
            workModes: [.create, .execute]
        )
        let (matched, confidence) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [agent],
            excluding: [],
            intent: .task
        )
        #expect(matched?.id == agent.id)
        #expect(confidence <= 0.75)
    }

    @Test("empty skillTags — 태그 있는 에이전트가 항상 우선")
    func taggedAgentBeatsUntagged() {
        let tagged = makeAgent(
            name: "백엔드 개발자",
            persona: "백엔드 서버 API 개발 전문",
            skillTags: ["백엔드", "서버", "api"],
            workModes: [.create, .execute]
        )
        let untagged = makeAgent(
            name: "백엔드 엔지니어",
            persona: "백엔드 시스템 전문가. 서버 API 설계와 구현.",
            skillTags: [],
            workModes: [.create, .execute]
        )
        let (matched, _) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [untagged, tagged],  // untagged 먼저
            excluding: [],
            intent: .task
        )
        #expect(matched?.id == tagged.id)
    }

    @Test("goal 키워드 상한 — 5개 초과 goal에서 노이즈 제한")
    func goalKeywordLimit() {
        // 긴 goal이 있어도 점수가 터무니없이 높아지면 안 됨
        let agent = makeAgent(
            name: "백엔드 개발자",
            persona: "서버 개발",
            skillTags: ["백엔드", "서버"]
        )
        let longGoal = "백엔드 서버 API 개발 데이터베이스 설계 인프라 구축 배포 자동화 모니터링 시스템 보안 감사 성능 최적화 캐시 전략"
        let brief = TaskBrief(
            goal: longGoal, constraints: [], successCriteria: [],
            nonGoals: [], overallRisk: .low, outputType: .code
        )
        let (_, confidence) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [agent],
            excluding: [],
            intent: .task,
            taskBrief: brief
        )
        // confidence는 여전히 합리적 범위 (1.0 이하)
        #expect(confidence <= 1.0)
        #expect(confidence > 0)
    }

    @Test("OutputStyle — TaskBrief.outputType=code + agent.outputStyles에 .code → 보너스")
    func outputStyleCodeBonus() {
        let withStyle = makeAgent(
            name: "백엔드 A",
            persona: "서버 개발",
            skillTags: ["백엔드"],
            workModes: [.create, .execute],
            outputStyles: [.code]
        )
        let withoutStyle = makeAgent(
            name: "백엔드 B",
            persona: "서버 개발",
            skillTags: ["백엔드"],
            workModes: [.create, .execute],
            outputStyles: [.document]  // code 아님
        )
        let brief = TaskBrief(
            goal: "API 구현", constraints: [], successCriteria: [],
            nonGoals: [], overallRisk: .low, outputType: .code
        )
        let (_, confA) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [withStyle],
            excluding: [],
            intent: .task,
            taskBrief: brief
        )
        let (_, confB) = AgentMatcher.matchByTags(
            roleName: "백엔드",
            agents: [withoutStyle],
            excluding: [],
            intent: .task,
            taskBrief: brief
        )
        #expect(confA > confB)
    }

    @Test("OutputStyle — TaskBrief.outputType=document + agent.outputStyles에 .document → 보너스")
    func outputStyleDocumentBonus() {
        let docWriter = makeAgent(
            name: "문서 작성자",
            persona: "기술 문서 작성",
            skillTags: ["문서"],
            workModes: [.create],
            outputStyles: [.document]
        )
        let coder = makeAgent(
            name: "개발자",
            persona: "코드 구현",
            skillTags: ["문서"],  // 같은 태그로 Tier1 동일하게
            workModes: [.create],
            outputStyles: [.code]
        )
        let brief = TaskBrief(
            goal: "기술 문서 작성", constraints: [], successCriteria: [],
            nonGoals: [], overallRisk: .low, outputType: .document
        )
        let (_, confDoc) = AgentMatcher.matchByTags(
            roleName: "문서",
            agents: [docWriter],
            excluding: [],
            intent: .documentation,
            taskBrief: brief
        )
        let (_, confCode) = AgentMatcher.matchByTags(
            roleName: "문서",
            agents: [coder],
            excluding: [],
            intent: .documentation,
            taskBrief: brief
        )
        #expect(confDoc > confCode)
    }

    // MARK: - 동의어 사전 확장

    @Test("expandSynonyms — 'ios' → 'swift', 'swiftui' 포함")
    func synonymIOS() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["ios"])
        #expect(expanded.contains("swift"))
        #expect(expanded.contains("swiftui"))
    }

    @Test("expandSynonyms — 'react' → '리액트' 포함")
    func synonymReact() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["react"])
        #expect(expanded.contains("리액트"))
    }

    @Test("expandSynonyms — 'python' → '파이썬', 'django' 포함")
    func synonymPython() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["python"])
        #expect(expanded.contains("파이썬"))
        #expect(expanded.contains("django"))
    }

    @Test("expandSynonyms — 'marketing' → '마케팅' 포함")
    func synonymMarketing() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["marketing"])
        #expect(expanded.contains("마케팅"))
    }

    @Test("expandSynonyms — 'legal' → '법무', '법률' 포함")
    func synonymLegal() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["legal"])
        #expect(expanded.contains("법무"))
        #expect(expanded.contains("법률"))
    }

    @Test("expandSynonyms — 'android' → '안드로이드', 'kotlin' 포함")
    func synonymAndroid() {
        let expanded = MatchingVocabulary.default.expandSynonyms(["android"])
        #expect(expanded.contains("안드로이드"))
        #expect(expanded.contains("kotlin"))
    }

    // MARK: - genericSuffixes 확장

    @Test("isGenericSuffix — 기존 + 확장 접미사 인식")
    func genericSuffixExpanded() {
        // 기존
        #expect(AgentMatcher.isGenericSuffix("전문가"))
        #expect(AgentMatcher.isGenericSuffix("developer"))
        // 확장
        #expect(AgentMatcher.isGenericSuffix("리더"))
        #expect(AgentMatcher.isGenericSuffix("시니어"))
        #expect(AgentMatcher.isGenericSuffix("컨설턴트"))
        #expect(AgentMatcher.isGenericSuffix("lead"))
        #expect(AgentMatcher.isGenericSuffix("senior"))
        #expect(AgentMatcher.isGenericSuffix("specialist"))
    }
}
