import SwiftUI

// MARK: - 방 목록 (메신저 스타일)

// MARK: - 상태 필터

enum RoomFilter: String, CaseIterable {
    case all        = "전체"
    case active     = "진행"
    case completed  = "완료"
    case failed     = "실패"

    func matches(_ room: Room) -> Bool {
        switch self {
        case .all:       return true
        case .active:    return room.status == .planning || room.status == .inProgress
        case .completed: return room.status == .completed
        case .failed:    return room.status == .failed
        }
    }

    var color: Color {
        switch self {
        case .all:       return .primary
        case .active:    return .orange
        case .completed: return .green
        case .failed:    return .red
        }
    }
}

struct RoomListView: View {
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore
    @State private var selectedFilter: RoomFilter = .all
    let onCreateRoom: () -> Void
    let onRoomTap: (UUID) -> Void

    /// 모든 방을 최신순으로 (활성 → 비활성, 각각 최신순)
    private var allRooms: [Room] {
        let active = roomManager.activeRooms
        let done = roomManager.completedRooms
        return active + done
    }

    private var filteredRooms: [Room] {
        allRooms.filter { selectedFilter.matches($0) }
    }

    /// 필터별 방 개수
    private func count(for filter: RoomFilter) -> Int {
        allRooms.filter { filter.matches($0) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // 상태 필터 바
            filterBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            // 방 리스트
            if filteredRooms.isEmpty {
                Spacer()
                Text(selectedFilter == .all ? "아직 방이 없습니다" : "'\(selectedFilter.rawValue)' 상태의 방이 없습니다")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(filteredRooms) { room in
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

    // MARK: - 필터 바

    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(RoomFilter.allCases, id: \.self) { filter in
                let cnt = count(for: filter)
                let isSelected = selectedFilter == filter

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedFilter = filter
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(filter.rawValue)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        if filter != .all && cnt > 0 {
                            Text("\(cnt)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(isSelected ? .white : filter.color)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(isSelected ? filter.color : filter.color.opacity(0.15))
                                )
                        }
                    }
                    .foregroundColor(isSelected ? filter.color : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? filter.color.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
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
