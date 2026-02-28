import Testing
import Foundation
@testable import DOUGLAS

@Suite("AgentRoleTemplate Tests")
struct AgentRoleTemplateTests {

    // MARK: - AgentRoleTemplate

    @Test("resolvedPersona - 프로바이더 힌트 있는 경우")
    func resolvedPersonaWithHint() {
        let template = AgentRoleTemplate(
            id: "test",
            name: "테스트",
            icon: "star",
            category: .development,
            basePersona: "기본 역할",

            providerHints: ["Anthropic": "Claude 전용 지시"]
        )
        let result = template.resolvedPersona(for: "Anthropic")
        #expect(result.contains("기본 역할"))
        #expect(result.contains("Claude 전용 지시"))
    }

    @Test("resolvedPersona - 프로바이더 힌트 없는 경우")
    func resolvedPersonaWithoutHint() {
        let template = AgentRoleTemplate(
            id: "test",
            name: "테스트",
            icon: "star",
            category: .development,
            basePersona: "기본 역할",

            providerHints: ["Anthropic": "Claude 전용"]
        )
        let result = template.resolvedPersona(for: "Google")
        #expect(result == "기본 역할")
    }

    @Test("resolvedPersona - 빈 힌트는 basePersona만 반환")
    func resolvedPersonaEmptyHint() {
        let template = AgentRoleTemplate(
            id: "test",
            name: "테스트",
            icon: "star",
            category: .development,
            basePersona: "기본 역할",

            providerHints: ["Anthropic": ""]
        )
        let result = template.resolvedPersona(for: "Anthropic")
        #expect(result == "기본 역할")
    }

    // MARK: - TemplateCategory

    @Test("TemplateCategory - 모든 케이스 rawValue")
    func templateCategoryRawValues() {
        #expect(TemplateCategory.analysis.rawValue == "분석")
        #expect(TemplateCategory.development.rawValue == "개발")
        #expect(TemplateCategory.quality.rawValue == "품질")
        #expect(TemplateCategory.operations.rawValue == "운영")
    }

    @Test("TemplateCategory - CaseIterable")
    func templateCategoryAllCases() {
        #expect(TemplateCategory.allCases.count == 4)
    }

    // MARK: - AgentRoleTemplateRegistry

    @Test("Registry - 빌트인 템플릿 9개")
    func registryBuiltInCount() {
        #expect(AgentRoleTemplateRegistry.builtIn.count == 9)
    }

    @Test("Registry - 모든 빌트인 ID가 고유")
    func registryUniqueIDs() {
        let ids = AgentRoleTemplateRegistry.builtIn.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test("Registry - template(for:) 존재하는 ID")
    func registryTemplateForExistingID() {
        let template = AgentRoleTemplateRegistry.template(for: "backend_dev")
        #expect(template != nil)
        #expect(template?.name == "백엔드 개발자")
    }

    @Test("Registry - template(for:) 존재하지 않는 ID")
    func registryTemplateForNonExistingID() {
        let template = AgentRoleTemplateRegistry.template(for: "does_not_exist")
        #expect(template == nil)
    }

    @Test("Registry - templates(in:) 카테고리 필터")
    func registryTemplatesByCategory() {
        let devTemplates = AgentRoleTemplateRegistry.templates(in: .development)
        #expect(devTemplates.count == 2) // backend_dev, frontend_dev
        #expect(devTemplates.allSatisfy { $0.category == .development })

        let qaTemplates = AgentRoleTemplateRegistry.templates(in: .quality)
        #expect(qaTemplates.count == 4) // qa_test_automation, qa_exploratory, qa_security, qa_code_review
    }

    @Test("Registry - 모든 빌트인에 basePersona가 비어있지 않음")
    func registryAllHavePersona() {
        for template in AgentRoleTemplateRegistry.builtIn {
            #expect(!template.basePersona.isEmpty, "Template \(template.id) has empty basePersona")
        }
    }

    @Test("Registry - 모든 빌트인에 icon이 비어있지 않음")
    func registryAllHaveIcon() {
        for template in AgentRoleTemplateRegistry.builtIn {
            #expect(!template.icon.isEmpty, "Template \(template.id) has empty icon")
        }
    }

    @Test("Registry - 레거시 별칭 매핑 검증")
    func registryLegacyAliasMapping() {
        // jira_analyst, requirements_analyst 제거됨 (마스터가 PM 역할 수행)
        let analyst = AgentRoleTemplateRegistry.template(for: "jira_analyst")
        #expect(analyst == nil)

        let qa = AgentRoleTemplateRegistry.template(for: "qa_engineer")
        #expect(qa?.id == "qa_test_automation")

        let devops = AgentRoleTemplateRegistry.template(for: "devops_engineer")
        #expect(devops != nil)

        let writer = AgentRoleTemplateRegistry.template(for: "tech_writer")
        #expect(writer != nil)
    }

    @Test("Registry - 프로바이더 힌트가 주요 프로바이더에 존재")
    func registryProviderHints() {
        for template in AgentRoleTemplateRegistry.builtIn {
            #expect(template.providerHints["Anthropic"] != nil,
                    "Template \(template.id) missing Anthropic hint")
            #expect(template.providerHints["OpenAI"] != nil,
                    "Template \(template.id) missing OpenAI hint")
        }
    }

    // MARK: - Agent roleTemplateID

    @Test("Agent - roleTemplateID 기본값 nil")
    func agentRoleTemplateIDDefault() {
        let agent = Agent(name: "테스트", persona: "역할", providerName: "OpenAI", modelName: "gpt-4o")
        #expect(agent.roleTemplateID == nil)
    }

    @Test("Agent - roleTemplateID 설정")
    func agentRoleTemplateIDSet() {
        let agent = Agent(
            name: "백엔드",
            persona: "백엔드 개발자",
            providerName: "Anthropic",
            modelName: "claude-sonnet-4-6",
            roleTemplateID: "backend_dev"
        )
        #expect(agent.roleTemplateID == "backend_dev")
    }

    @Test("Agent - roleTemplateID Codable 라운드트립")
    func agentRoleTemplateIDCodable() throws {
        let agent = Agent(
            name: "QA",
            persona: "QA 엔지니어",
            providerName: "OpenAI",
            modelName: "gpt-4o",
            roleTemplateID: "qa_engineer"
        )
        let data = try JSONEncoder().encode(agent)
        let decoded = try JSONDecoder().decode(Agent.self, from: data)
        #expect(decoded.roleTemplateID == "qa_engineer")
    }

    @Test("Agent - roleTemplateID 없는 레거시 JSON 호환")
    func agentRoleTemplateIDLegacy() throws {
        // roleTemplateID 필드 없는 JSON
        let json = """
        {"id":"12345678-1234-1234-1234-123456789012","name":"테스트","persona":"역할","providerName":"OpenAI","modelName":"gpt-4o","status":"idle","isMaster":false,"hasImage":false}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Agent.self, from: data)
        #expect(decoded.roleTemplateID == nil)
        #expect(decoded.name == "테스트")
    }

    // MARK: - Codable round-trip

    // MARK: - Phase D: QA 세분화

    @Test("Registry - requirements_analyst 제거됨")
    func registryRequirementsAnalystRemoved() {
        let template = AgentRoleTemplateRegistry.template(for: "requirements_analyst")
        #expect(template == nil)
    }

    @Test("Registry - qa_engineer 레거시 별칭 → qa_test_automation")
    func registryQaEngineerLegacy() {
        let template = AgentRoleTemplateRegistry.template(for: "qa_engineer")
        #expect(template?.id == "qa_test_automation")
    }

    @Test("Registry - QA 4개 템플릿 존재")
    func registryQAFourTemplates() {
        let ids = ["qa_test_automation", "qa_exploratory", "qa_security", "qa_code_review"]
        for id in ids {
            let tmpl = AgentRoleTemplateRegistry.template(for: id)
            #expect(tmpl != nil, "QA template \(id) missing")
            #expect(tmpl?.category == .quality)
        }
    }

    @Test("Registry - QA 템플릿 카테고리 확인")
    func qaTemplateCategories() {
        for id in ["qa_test_automation", "qa_exploratory", "qa_security", "qa_code_review"] {
            let tmpl = AgentRoleTemplateRegistry.template(for: id)
            #expect(tmpl?.category == .quality, "\(id) should be quality category")
        }
    }

    // MARK: - Codable round-trip

    @Test("AgentRoleTemplate - Codable 라운드트립")
    func templateCodableRoundTrip() throws {
        let template = AgentRoleTemplate(
            id: "test_tmpl",
            name: "테스트 템플릿",
            icon: "star",
            category: .quality,
            basePersona: "테스트 역할",
            providerHints: ["Anthropic": "힌트A", "OpenAI": "힌트B"]
        )
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(AgentRoleTemplate.self, from: data)
        #expect(decoded.id == "test_tmpl")
        #expect(decoded.name == "테스트 템플릿")
        #expect(decoded.category == .quality)
        #expect(decoded.providerHints["Anthropic"] == "힌트A")
    }
}
