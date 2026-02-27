import SwiftUI

struct SuggestionCard: View {
    let suggestion: AgentSuggestion
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var roomManager: RoomManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                Text("새 에이전트 제안")
                    .font(.callout.bold())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.name)
                    .font(.callout.weight(.medium))
                Text(suggestion.persona)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                if !suggestion.recommendedProvider.isEmpty {
                    Text("\(suggestion.recommendedProvider) / \(suggestion.recommendedModel)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("추가") { createAgent() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("건너뛰기") { chatVM.pendingSuggestion = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    private func createAgent() {
        let providerName = suggestion.recommendedProvider.isEmpty
            ? (agentStore.masterAgent?.providerName ?? "Claude Code")
            : suggestion.recommendedProvider
        let modelName = suggestion.recommendedModel.isEmpty
            ? (agentStore.masterAgent?.modelName ?? "claude-sonnet-4-6")
            : suggestion.recommendedModel

        // roleTemplateID가 있으면 템플릿의 persona를 사용
        let finalPersona: String
        if let templateID = suggestion.roleTemplateID,
           let template = AgentRoleTemplateRegistry.template(for: templateID) {
            finalPersona = template.resolvedPersona(for: providerName)
        } else {
            finalPersona = suggestion.persona
        }

        let agent = Agent(
            name: suggestion.name,
            persona: finalPersona,
            providerName: providerName,
            modelName: modelName,
            roleTemplateID: suggestion.roleTemplateID
        )
        agentStore.addAgent(agent)

        let msg = ChatMessage(
            role: .assistant,
            content: "'\(suggestion.name)' 에이전트가 생성되었습니다.",
            agentName: "마스터",
            messageType: .text
        )
        chatVM.appendMessagePublic(msg, for: suggestion.masterAgentID)

        // 방 생성 + 워크플로우 시작
        let task = suggestion.originalTask
        let room = roomManager.createRoom(
            title: task,
            agentIDs: [agent.id],
            createdBy: .master(agentID: suggestion.masterAgentID)
        )
        roomManager.pendingAutoOpenRoomID = room.id

        let delegationMsg = ChatMessage(
            role: .assistant,
            content: "'\(suggestion.name)' 에이전트로 방을 생성합니다: \(task)",
            agentName: "마스터",
            messageType: .delegation
        )
        chatVM.appendMessagePublic(delegationMsg, for: suggestion.masterAgentID)

        roomManager.launchWorkflow(roomID: room.id, task: task)

        chatVM.pendingSuggestion = nil
    }

}
