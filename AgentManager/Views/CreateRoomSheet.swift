import SwiftUI

/// 사용자가 수동으로 방을 만들어 에이전트를 초대하고 작업을 지시하는 시트
struct CreateRoomSheet: View {
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var roomManager: RoomManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var task = ""
    @State private var selectedAgentIDs: Set<UUID> = []

    /// DevAgent + 서브에이전트 (마스터 제외)
    private var availableAgents: [Agent] {
        var list: [Agent] = []
        if let dev = agentStore.devAgent { list.append(dev) }
        list += agentStore.subAgents
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            // 네비게이션 바 스타일 헤더
            ZStack {
                Text("새 방 만들기")
                    .font(.headline)
                HStack {
                    Button("취소") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("만들기") { createRoom() }
                        .keyboardShortcut(.defaultAction)
                        .fontWeight(.semibold)
                        .disabled(!canCreate)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // 방 제목
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("방 제목")
                        TextField("예: 블로그 글 작성", text: $title)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .padding(10)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)
                    }

                    // 에이전트 선택
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            sectionLabel("에이전트")
                            Spacer()
                            if !selectedAgentIDs.isEmpty {
                                Text("\(selectedAgentIDs.count)명")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }

                        if availableAgents.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 4) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.title3)
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("에이전트를 먼저 추가하세요")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 16)
                                Spacer()
                            }
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(availableAgents.enumerated()), id: \.element.id) { index, agent in
                                    if index > 0 {
                                        Divider().padding(.leading, 48)
                                    }
                                    agentRow(agent)
                                }
                            }
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)
                        }
                    }

                    // 작업 내용
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("작업 내용")
                        TextEditor(text: $task)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80, maxHeight: 120)
                            .padding(8)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)
                        Text("에이전트들이 먼저 토론한 후, 계획을 세우고 작업을 진행합니다.")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 440, height: 520)
    }

    // MARK: - Components

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundColor(.secondary)
    }

    private func agentRow(_ agent: Agent) -> some View {
        let isSelected = selectedAgentIDs.contains(agent.id)

        return HStack(spacing: 10) {
            AgentAvatarView(agent: agent, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .medium : .regular)
                Text(agent.persona.prefix(50) + (agent.persona.count > 50 ? "..." : ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if agent.status == .working || agent.status == .busy {
                statusBadge("작업중", color: .orange)
            }

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : Color.primary.opacity(0.15))
                .font(.title3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { toggleAgent(agent.id) }
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }

    // MARK: - Logic

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedAgentIDs.isEmpty
    }

    private func toggleAgent(_ id: UUID) {
        if selectedAgentIDs.contains(id) {
            selectedAgentIDs.remove(id)
        } else {
            selectedAgentIDs.insert(id)
        }
    }

    private func createRoom() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedTask.isEmpty, !selectedAgentIDs.isEmpty else { return }

        roomManager.createManualRoom(
            title: trimmedTitle,
            agentIDs: Array(selectedAgentIDs),
            task: trimmedTask
        )
        // NSWindow 닫기
        NSApp.keyWindow?.close()
    }
}
