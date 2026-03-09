import Testing
@testable import DOUGLAS

@Suite("AgentPreset Tests")
struct AgentPresetTests {

    // MARK: - find

    @Test("find - backend-engineer 프리셋 검색")
    func findBackendEngineer() {
        let preset = AgentPreset.find("backend-engineer")
        #expect(preset != nil)
        #expect(preset?.name == "백엔드 엔지니어")
    }

    @Test("find - frontend-engineer 프리셋 검색")
    func findFrontendEngineer() {
        let preset = AgentPreset.find("frontend-engineer")
        #expect(preset != nil)
        #expect(preset?.name == "프론트엔드 엔지니어")
    }

    @Test("find - 존재하지 않는 ID는 nil 반환")
    func findNonexistent() {
        #expect(AgentPreset.find("nonexistent") == nil)
    }

    @Test("find - custom 프리셋 검색 및 isCustom 확인")
    func findCustom() {
        let preset = AgentPreset.find("custom")
        #expect(preset != nil)
        #expect(preset?.isCustom == true)
    }

    // MARK: - builtIn

    @Test("builtIn - 프리셋 개수는 13개")
    func builtInCount() {
        #expect(AgentPreset.builtIn.count == 13)
    }

    @Test("builtIn - 모든 ID가 고유")
    func builtInUniqueIDs() {
        let ids = AgentPreset.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("builtIn - custom 외 모든 프리셋은 suggestedPersona가 비어있지 않음")
    func builtInNonCustomHavePersona() {
        for preset in AgentPreset.builtIn where !preset.isCustom {
            #expect(!preset.suggestedPersona.isEmpty, "preset \(preset.id) has empty suggestedPersona")
        }
    }

    @Test("builtIn - 모든 프리셋은 icon이 비어있지 않음")
    func builtInAllHaveIcon() {
        for preset in AgentPreset.builtIn {
            #expect(!preset.icon.isEmpty, "preset \(preset.id) has empty icon")
        }
    }

    @Test("builtIn - 모든 프리셋은 name이 비어있지 않음")
    func builtInAllHaveName() {
        for preset in AgentPreset.builtIn {
            #expect(!preset.name.isEmpty, "preset \(preset.id) has empty name")
        }
    }

    // MARK: - grouped

    @Test("grouped - 카테고리 순서가 PresetCategory.allCases 순서를 따름")
    func groupedCategoryOrder() {
        let grouped = AgentPreset.grouped
        let groupedCategories = grouped.map(\.category)
        let expectedOrder = AgentPreset.PresetCategory.allCases.filter { cat in
            AgentPreset.builtIn.contains { $0.category == cat }
        }
        #expect(groupedCategories == expectedOrder)
    }

    @Test("grouped - 전체 프리셋 합계가 builtIn 개수와 일치")
    func groupedTotalCount() {
        let total = AgentPreset.grouped.reduce(0) { $0 + $1.presets.count }
        #expect(total == AgentPreset.builtIn.count)
    }

    // MARK: - isCustom

    @Test("isCustom - custom만 true, 나머지는 모두 false")
    func isCustomOnlyForCustomID() {
        for preset in AgentPreset.builtIn {
            if preset.id == "custom" {
                #expect(preset.isCustom == true)
            } else {
                #expect(preset.isCustom == false, "preset \(preset.id) should not be custom")
            }
        }
    }
}
