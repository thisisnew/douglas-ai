import SwiftUI

// MARK: - 방 목록 (메신저 스타일)

struct RoomListView: View {
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore
    let onCreateRoom: () -> Void
    let onRoomTap: (UUID) -> Void

    /// 모든 방을 최신순으로 (활성 → 비활성, 각각 최신순)
    private var allRooms: [Room] {
        let active = roomManager.activeRooms   // 이미 최신순
        let done = roomManager.completedRooms  // 이미 최신순
        return active + done
    }

    var body: some View {
        VStack(spacing: 0) {
            // 방 리스트
            if allRooms.isEmpty {
                HStack {
                    Spacer()
                    Text("아직 방이 없습니다")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(allRooms) { room in
                            RoomListItem(room: room)
                                .onTapGesture { onRoomTap(room.id) }
                                .contextMenu { roomContextMenu(room) }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func roomContextMenu(_ room: Room) -> some View {
        if room.isActive {
            Button {
                roomManager.completeRoom(room.id)
            } label: {
                Label("완료 처리", systemImage: "checkmark.circle")
            }
        }
        Button {
            roomManager.archiveRoom(room.id)
        } label: {
            Label("보관", systemImage: "archivebox")
        }
        Divider()
        Button(role: .destructive) {
            roomManager.deleteRoom(room.id)
        } label: {
            Label("삭제", systemImage: "trash")
        }
    }
}

// MARK: - 방 목록 아이템 (메신저 스타일)

struct RoomListItem: View {
    let room: Room
    @EnvironmentObject var agentStore: AgentStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // 좌측: 에이전트 아바타 스택
            avatarStack

            // 중앙: 제목 + 마지막 메시지
            VStack(alignment: .leading, spacing: 3) {
                Text(room.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(lastMessagePreview)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // 우측: 시간 + 상태 뱃지
            VStack(alignment: .trailing, spacing: 4) {
                Text(timeText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                statusBadge
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered
                      ? Color.black.opacity(0.07)
                      : (room.isActive ? Color.black.opacity(0.04) : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - 아바타 스택

    private var avatarStack: some View {
        let agents = room.assignedAgentIDs.prefix(3).compactMap { id in
            agentStore.agents.first { $0.id == id }
        }

        return ZStack(alignment: .bottomLeading) {
            ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                AgentAvatarView(agent: agent, size: 24)
                    .overlay(
                        Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                    )
                    .offset(x: CGFloat(index) * 10)
            }
        }
        .frame(width: CGFloat(min(agents.count, 3)) * 10 + 14, alignment: .leading)
    }

    // MARK: - 마지막 메시지 미리보기

    private var lastMessagePreview: String {
        if let last = room.messages.last {
            let prefix = last.agentName.map { "\($0): " } ?? ""
            return prefix + last.content.replacingOccurrences(of: "\n", with: " ")
        }
        return "메시지 없음"
    }

    // MARK: - 시간 텍스트

    private var timeText: String {
        let date = room.completedAt ?? room.createdAt
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - 상태 뱃지

    @ViewBuilder
    private var statusBadge: some View {
        switch room.status {
        case .planning:
            badgeView(text: room.plan == nil ? room.discussionProgressText : "계획 중",
                       color: DesignTokens.RoomStatusColor.color(for: .planning))

        case .inProgress:
            let pct = progressPercent
            badgeView(text: "\(DesignTokens.RoomStatusColor.label(for: .inProgress)) \(pct)%",
                       color: DesignTokens.RoomStatusColor.color(for: .inProgress))

        case .completed:
            badgeView(text: DesignTokens.RoomStatusColor.label(for: .completed),
                       color: DesignTokens.RoomStatusColor.color(for: .completed))

        case .failed:
            badgeView(text: DesignTokens.RoomStatusColor.label(for: .failed),
                       color: DesignTokens.RoomStatusColor.color(for: .failed))

        case .archived:
            badgeView(text: DesignTokens.RoomStatusColor.label(for: .archived),
                       color: DesignTokens.RoomStatusColor.color(for: .archived))
        }
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: DesignTokens.FontSize.badge, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, DesignTokens.Radius.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(color.opacity(DesignTokens.Opacity.badgeBg))
            .cornerRadius(DesignTokens.Radius.badge)
    }

    private var progressPercent: Int {
        guard let plan = room.plan, !plan.steps.isEmpty else { return 0 }
        return min(100, room.currentStepIndex * 100 / plan.steps.count)
    }
}
