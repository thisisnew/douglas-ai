import SwiftUI

/// 설정 > 에이전트 탭 — 내보내기(멀티 선택)/가져오기
struct AgentSettingsView: View {
    var isEmbedded = false

    @Environment(\.colorPalette) private var palette
    @EnvironmentObject var agentStore: AgentStore

    @State private var selectedIDs: Set<UUID> = []

    private var subAgents: [Agent] { agentStore.subAgents }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !isEmbedded {
                    Text("에이전트")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                }

                exportSection
                importSection
            }
            .padding(isEmbedded ? 24 : 16)
        }
        .frame(maxWidth: isEmbedded ? .infinity : nil, maxHeight: isEmbedded ? .infinity : nil)
    }

    // MARK: - 내보내기

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("에이전트 내보내기", systemImage: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Text(".douglas 파일로 내보내 다른 환경에서 가져올 수 있습니다.")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)

            if subAgents.isEmpty {
                Text("내보낼 에이전트가 없습니다.")
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSecondary.opacity(0.6))
                    .padding(.vertical, 8)
            } else {
                // 에이전트 목록
                VStack(spacing: 0) {
                    ForEach(Array(subAgents.enumerated()), id: \.element.id) { index, agent in
                        agentRow(agent)
                        if index < subAgents.count - 1 {
                            Rectangle()
                                .fill(LinearGradient(
                                    colors: [.clear, palette.separator.opacity(0.2), .clear],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(height: 1)
                                .padding(.leading, 40)
                        }
                    }
                }
                .background(palette.inputBackground)
                .continuousRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
                )

                // 하단: 전체 선택 + 내보내기 버튼
                HStack {
                    Button {
                        if selectedIDs.count == subAgents.count {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(subAgents.map(\.id))
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedIDs.count == subAgents.count ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                            Text(selectedIDs.count == subAgents.count ? "선택 해제" : "전체 선택")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(palette.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        let agents = subAgents.filter { selectedIDs.contains($0.id) }
                        AgentPorter.exportAgents(agents, suggestedName: "douglas-agents.douglas")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text("내보내기 (\(selectedIDs.count))")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(selectedIDs.isEmpty ? palette.textSecondary.opacity(0.4) : palette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIDs.isEmpty)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surfaceSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
        )
    }

    private func agentRow(_ agent: Agent) -> some View {
        let isSelected = selectedIDs.contains(agent.id)

        return Button {
            if isSelected {
                selectedIDs.remove(agent.id)
            } else {
                selectedIDs.insert(agent.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? palette.accent : palette.textSecondary.opacity(0.4))

                AgentAvatarView(agent: agent, size: 24)

                Text(agent.name)
                    .font(.system(size: 13))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(agent.modelName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(palette.textSecondary.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 가져오기

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("에이전트 가져오기", systemImage: "square.and.arrow.down")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Text(".douglas 파일에서 에이전트를 불러옵니다.")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)

            Button {
                AgentPorter.importAgents(into: agentStore)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                    Text("파일에서 가져오기")
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(palette.inputBackground)
                .continuousRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surfaceSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
        )
    }
}
