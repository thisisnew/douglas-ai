import SwiftUI

struct SuggestionCard: View {
    let suggestion: AgentSuggestion
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var roomManager: RoomManager

    @State private var editedName: String = ""
    @State private var editedPersona: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                Text("새 에이전트 제안")
                    .font(.callout.bold())
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("에이전트 이름", text: $editedName)
                    .font(.callout.weight(.medium))
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $editedPersona)
                    .font(.caption)
                    .frame(minHeight: 48, maxHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

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
                    .disabled(editedName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("건너뛰기") { chatVM.pendingSuggestion = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .continuousRadius(DesignTokens.Radius.lg)
        .onAppear {
            editedName = suggestion.name
            editedPersona = suggestion.persona
        }
    }

    private func createAgent() {
        let name = editedName.trimmingCharacters(in: .whitespaces)
        let persona = editedPersona.trimmingCharacters(in: .whitespacesAndNewlines)

        let providerName = suggestion.recommendedProvider.isEmpty
            ? (agentStore.masterAgent?.providerName ?? "Claude Code")
            : suggestion.recommendedProvider
        let modelName = suggestion.recommendedModel.isEmpty
            ? (agentStore.masterAgent?.modelName ?? "claude-sonnet-4-6")
            : suggestion.recommendedModel

        // 사용자가 설명을 편집하지 않았고 roleTemplateID가 있으면 템플릿 persona 사용
        let finalPersona: String
        if persona == suggestion.persona,
           let templateID = suggestion.roleTemplateID,
           let template = AgentRoleTemplateRegistry.template(for: templateID) {
            finalPersona = template.resolvedPersona(for: providerName)
        } else {
            finalPersona = persona
        }

        let agent = Agent(
            name: name,
            persona: finalPersona,
            providerName: providerName,
            modelName: modelName,
            roleTemplateID: suggestion.roleTemplateID
        )
        agentStore.addAgent(agent)

        let msg = ChatMessage(
            role: .assistant,
            content: "'\(name)' 에이전트가 생성되었습니다.",
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
            content: "'\(name)' 에이전트로 방을 생성합니다: \(task)",
            agentName: "마스터",
            messageType: .delegation
        )
        chatVM.appendMessagePublic(delegationMsg, for: suggestion.masterAgentID)

        roomManager.launchWorkflow(roomID: room.id, task: task)

        chatVM.pendingSuggestion = nil
    }

}
