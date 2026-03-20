import Testing
import Foundation
@testable import DOUGLAS

@Suite("PluginPreset Tests")
struct PluginPresetTests {

    @Test("빌트인 프리셋 3종 존재")
    func builtInPresets_3() {
        #expect(PluginPreset.builtIn.count == 3)
    }

    @Test("각 프리셋의 ID가 고유")
    func presetIDs_unique() {
        let ids = PluginPreset.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Slack 프리셋 — 필수 필드")
    func slackPreset_hasRequiredFields() {
        let preset = PluginPreset.builtIn.first(where: { $0.id == "slack-monitor" })!
        #expect(preset.name.contains("Slack"))
        #expect(!preset.tags.isEmpty)
        #expect(preset.capabilities.skillTags?.contains("slack") == true)
        #expect(!preset.globalConfigFields.isEmpty)  // botToken, appToken
        #expect(!preset.agentConfigFields.isEmpty)    // channelFilter, triggerPatterns
    }

    @Test("Jira 프리셋 — 필수 필드")
    func jiraPreset_hasRequiredFields() {
        let preset = PluginPreset.builtIn.first(where: { $0.id == "jira-manager" })!
        #expect(preset.name.contains("Jira"))
        #expect(preset.capabilities.skillTags?.contains("jira") == true)
    }

    @Test("Webhook 프리셋 — 필수 필드")
    func webhookPreset_hasRequiredFields() {
        let preset = PluginPreset.builtIn.first(where: { $0.id == "webhook-notify" })!
        #expect(preset.name.contains("Webhook"))
        #expect(preset.capabilities.skillTags?.contains("webhook") == true)
        #expect(!preset.globalConfigFields.isEmpty)  // webhookURL
    }

    @Test("toManifest — PluginManifest 변환")
    func presetToManifest() {
        let preset = PluginPreset.builtIn[0]
        let manifest = preset.toManifest()
        #expect(manifest.id == preset.id)
        #expect(manifest.name == preset.name)
        #expect(manifest.capabilities?.skillTags == preset.capabilities.skillTags)
    }
}
