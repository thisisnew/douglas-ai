import Foundation
import AppKit

/// 에이전트 매니페스트 Export/Import 핸들러
@MainActor
enum AgentPorter {

    // MARK: - Export

    /// 단일 에이전트를 .douglas 파일로 내보내기
    static func exportAgent(_ agent: Agent) {
        exportAgents([agent], suggestedName: "\(agent.name).douglas")
    }

    /// 전체 에이전트를 .douglas 파일로 내보내기
    static func exportAllAgents(from store: AgentStore) {
        exportAgents(store.agents, suggestedName: "douglas-agents.douglas")
    }

    /// 에이전트 배열을 매니페스트 JSON으로 내보내기
    static func exportAgents(_ agents: [Agent], suggestedName: String) {
        let entries = agents.map { AgentManifest.AgentEntry(from: $0) }
        let manifest = AgentManifest(
            formatVersion: AgentManifest.currentFormatVersion,
            exportedAt: Date(),
            exportedFrom: "DOUGLAS",
            agents: entries
        )

        guard let data = encode(manifest) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedName
        panel.message = "에이전트 매니페스트를 저장할 위치를 선택하세요"
        panel.prompt = "내보내기"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url)
        } catch {
            showAlert(title: "내보내기 실패", message: error.localizedDescription)
        }
    }

    // MARK: - Import

    /// .douglas 파일에서 에이전트 가져오기
    static func importAgents(into store: AgentStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "가져올 .douglas 파일을 선택하세요"
        panel.prompt = "가져오기"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let manifest = try decode(data)

            // 미래 버전 경고
            if manifest.formatVersion > AgentManifest.currentFormatVersion {
                let proceed = showConfirm(
                    title: "버전 불일치",
                    message: "이 파일은 더 새로운 버전(v\(manifest.formatVersion))에서 생성되었습니다. 일부 정보가 누락될 수 있습니다."
                )
                if !proceed { return }
            }

            let nonMasterEntries = manifest.agents.filter { !$0.isMaster }
            let duplicates = AgentManifest.findDuplicates(entries: nonMasterEntries, existing: store.agents)
            let duplicateEntryNames = Set(duplicates.filter { $0.matchType == .exact }.map(\.entry.name))

            var importedCount = 0
            var skippedCount = 0
            for entry in nonMasterEntries {
                // fingerprint 완전 일치 → 건너뜀 (중복)
                if duplicateEntryNames.contains(entry.name) {
                    skippedCount += 1
                    continue
                }

                let finalName = AgentManifest.deduplicateName(entry.name, existing: store.agents)
                var agent = entry.toAgent()
                if finalName != entry.name {
                    agent = Agent(
                        name: finalName,
                        persona: agent.persona,
                        providerName: agent.providerName,
                        modelName: agent.modelName,
                        imageData: agent.imageData,
                        workingRules: agent.workingRules
                    )
                }
                store.addAgent(agent)
                importedCount += 1
            }

            let skippedMasters = manifest.agents.filter(\.isMaster).count
            var message = "\(importedCount)개의 에이전트를 가져왔습니다."
            if skippedCount > 0 {
                message += "\n(\(skippedCount)개는 이미 동일한 에이전트가 있어 건너뜀)"
            }
            if skippedMasters > 0 {
                message += "\n(마스터 에이전트 \(skippedMasters)개는 건너뜀)"
            }
            showAlert(title: "가져오기 완료", message: message)

        } catch {
            showAlert(title: "가져오기 실패", message: error.localizedDescription)
        }
    }

    // MARK: - JSON 직렬화

    private static func encode(_ manifest: AgentManifest) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(manifest)
        } catch {
            showAlert(title: "직렬화 실패", message: error.localizedDescription)
            return nil
        }
    }

    private static func decode(_ data: Data) throws -> AgentManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentManifest.self, from: data)
    }

    // MARK: - Alerts

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private static func showConfirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "계속")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
