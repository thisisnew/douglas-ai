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
        case .active:    return room.status == .planning || room.status == .inProgress || room.status == .awaitingApproval || room.status == .awaitingUserInput
        case .completed: return room.status == .completed
        case .failed:    return room.status == .failed
        }
    }

    var color: Color {
        switch self {
        case .all:       return .primary
        case .active:    return .orange.opacity(0.7)
        case .completed: return .green.opacity(0.7)
        case .failed:    return .red.opacity(0.7)
        }
    }
}

struct RoomListView: View {
    @Environment(\.colorPalette) private var palette
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var agentStore: AgentStore
    @State private var selectedFilter: RoomFilter = .all
    @State private var isEditMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var searchText = ""
    let onCreateRoom: () -> Void
    let onRoomTap: (UUID) -> Void

    /// 모든 방을 최신순으로 (활성 → 비활성, 각각 최신순)
    private var allRooms: [Room] {
        let active = roomManager.activeRooms
        let done = roomManager.completedRooms
        return active + done
    }

    private var filteredRooms: [Room] {
        let byFilter = searchText.isEmpty
            ? allRooms.filter { selectedFilter.matches($0) }
            : allRooms // 검색 중이면 상태 필터 무시
        guard !searchText.isEmpty else { return byFilter }
        let query = searchText.lowercased()
        return byFilter.filter { room in
            room.title.lowercased().contains(query)
            || room.messages.contains { $0.content.lowercased().contains(query) }
        }
    }

    /// 필터별 방 개수
    private func count(for filter: RoomFilter) -> Int {
        allRooms.filter { filter.matches($0) }.count
    }

    /// 선택된 방 중 활성(완료 가능한) 방 수
    private var activeSelectedCount: Int {
        selectedIDs.filter { id in
            allRooms.first(where: { $0.id == id })?.isActive == true
        }.count
    }

    private var isAllSelected: Bool {
        !filteredRooms.isEmpty && filteredRooms.allSatisfy { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 검색 바
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
                TextField("방 또는 메시지 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04))
            .continuousRadius(DesignTokens.CozyGame.cardRadius)
            .shadow(color: palette.sidebarShadow, radius: 3, y: 1)
            .padding(.horizontal, 8)
            .padding(.top, 6)

            // 상태 필터 바 + 액션 버튼
            HStack(spacing: 6) {
                filterBar
                Spacer(minLength: 4)
                selectModeButton
                createRoomButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // 편집 모드: 전체 선택 바
            if isEditMode && !filteredRooms.isEmpty {
                selectAllBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 방 리스트
            if filteredRooms.isEmpty {
                Spacer()
                Text(!searchText.isEmpty ? "'\(searchText)' 검색 결과가 없습니다"
                     : selectedFilter == .all ? "아직 방이 없습니다"
                     : "'\(selectedFilter.rawValue)' 상태의 방이 없습니다")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredRooms) { room in
                            RoomRowAnimated(
                                room: room,
                                isEditMode: isEditMode,
                                isSelected: selectedIDs.contains(room.id),
                                onTap: {
                                    if isEditMode {
                                        toggleSelection(room.id)
                                    } else {
                                        onRoomTap(room.id)
                                    }
                                },
                                onComplete: { roomManager.completeRoom(room.id) },
                                onDelete: { roomManager.deleteRoom(room.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }

            // 편집 모드: 하단 액션 바
            if isEditMode && !selectedIDs.isEmpty {
                actionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.dgStandard, value: isEditMode)
        .confirmationDialog(
            "선택한 \(selectedIDs.count)개 방을 삭제할까요?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                roomManager.deleteRooms(selectedIDs)
                selectedIDs.removeAll()
                exitEditModeIfEmpty()
            }
        } message: {
            Text("완료된 방 \(selectedIDs.count)개가 삭제됩니다.")
        }
    }

    // MARK: - 선택 모드 버튼

    private var selectModeButton: some View {
        Button {
            withAnimation {
                isEditMode.toggle()
                if !isEditMode { selectedIDs.removeAll() }
            }
        } label: {
            Image(systemName: isEditMode ? "xmark.circle.fill" : "checklist")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isEditMode ? .accentColor : .secondary.opacity(0.6))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isEditMode ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(isEditMode ? "선택 해제" : "선택")
    }

    // MARK: - 방 만들기 버튼

    private var createRoomButton: some View {
        Button(action: onCreateRoom) {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("새 방")
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .buttonStyle(CozyButtonStyle(.accent))
    }

    // MARK: - 전체 선택 바

    private var selectAllBar: some View {
        HStack(spacing: 8) {
            Button {
                if isAllSelected {
                    selectedIDs.removeAll()
                } else {
                    // 작업 중인 방은 전체 선택에서 제외
                    selectedIDs = Set(filteredRooms.filter { !$0.isActive }.map(\.id))
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isAllSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isAllSelected ? .accentColor : .secondary.opacity(0.5))

                    Text("전체 선택")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if !selectedIDs.isEmpty {
                Text("\(selectedIDs.count)개 선택")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.surfaceTertiary)
    }

    // MARK: - 하단 액션 바

    private var actionBar: some View {
        HStack(spacing: 10) {
            // 완료 처리 버튼 (활성 방이 있을 때만)
            if activeSelectedCount > 0 {
                Button {
                    let activeIDs = selectedIDs.filter { id in
                        allRooms.first(where: { $0.id == id })?.isActive == true
                    }
                    roomManager.completeRooms(Set(activeIDs))
                    selectedIDs.removeAll()
                    exitEditModeIfEmpty()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11))
                        Text("완료 (\(activeSelectedCount))")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.green.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.green.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }

            // 삭제 버튼
            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("삭제 (\(selectedIDs.count))")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.red.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [palette.cardBorder.opacity(0), palette.cardBorder.opacity(0.4), palette.cardBorder.opacity(0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(height: 1.5)
                }
        )
    }

    // MARK: - 필터 바

    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(RoomFilter.allCases, id: \.self) { filter in
                let cnt = count(for: filter)
                let isSelected = selectedFilter == filter

                Button {
                    withAnimation(.dgFast) {
                        selectedFilter = filter
                        // 필터 바꾸면 선택 초기화
                        selectedIDs.removeAll()
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
                        Capsule()
                            .fill(isSelected ? filter.color.opacity(0.12) : Color.clear)
                    )
                    .shadow(color: isSelected ? palette.sidebarShadow : .clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        // 작업 중인 방은 선택 불가
        if let room = roomManager.rooms.first(where: { $0.id == id }), room.isActive { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func exitEditModeIfEmpty() {
        if filteredRooms.isEmpty {
            withAnimation { isEditMode = false }
        }
    }
}

// MARK: - 방 행 (편집 모드 지원)

struct RoomRow: View {
    let room: Room
    let isEditMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isEditMode {
                    if room.isActive {
                        Image(systemName: "lock.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary.opacity(0.25))
                    } else {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
                    }
                }
                RoomListItem(room: room)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if room.isActive {
                Button { onComplete() } label: {
                    Label("완료 처리", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}

// MARK: - 방 목록 아이템 (메신저 스타일)

struct RoomListItem: View {
    @Environment(\.colorPalette) private var palette
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

            // 우측: 시간 + ID + 상태 뱃지 + 확인 필요 플래그
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Text(room.shortID)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(timeText)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    statusBadge
                    if room.needsUserAttention {
                        Text("확인 필요")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.7)))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                .fill(isHovered
                      ? palette.hoverBackground
                      : (room.isActive ? palette.activeRowBackground : palette.surfaceTertiary.opacity(0.5)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(isHovered ? 0.3 : 0.12), lineWidth: 1)
        )
        .shadow(color: palette.sidebarShadow, radius: 3, y: 1)
        .onHover { hovering in
            withAnimation(.dgFast) {
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
            badgeView(text: room.phaseLabel,
                       color: DesignTokens.RoomStatusColor.color(for: .planning))

        case .inProgress:
            let pct = progressPercent
            badgeView(text: "\(DesignTokens.RoomStatusColor.label(for: .inProgress)) \(pct)%",
                       color: DesignTokens.RoomStatusColor.color(for: .inProgress))

        case .completed:
            badgeView(text: DesignTokens.RoomStatusColor.label(for: .completed),
                       color: DesignTokens.RoomStatusColor.color(for: .completed))

        case .awaitingApproval:
            badgeView(text: DesignTokens.RoomStatusColor.label(for: .awaitingApproval),
                       color: DesignTokens.RoomStatusColor.color(for: .awaitingApproval))

        case .awaitingUserInput:
            badgeView(text: DesignTokens.RoomStatusColor.label(for: .awaitingUserInput),
                       color: DesignTokens.RoomStatusColor.color(for: .awaitingUserInput))

        case .failed:
            badgeView(text: DesignTokens.RoomStatusColor.label(for: .failed),
                       color: DesignTokens.RoomStatusColor.color(for: .failed))
        }
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: DesignTokens.FontSize.badge, weight: .medium, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, DesignTokens.Radius.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(color.opacity(DesignTokens.Opacity.badgeBg))
            .clipShape(Capsule())
    }

    private var progressPercent: Int {
        guard let plan = room.plan, !plan.steps.isEmpty else { return 0 }
        return min(100, room.currentStepIndex * 100 / plan.steps.count)
    }
}

/// onAppear 페이드인 래퍼 — ForEach 레벨 animation 없이 개별 행만 애니메이션
private struct RoomRowAnimated: View {
    let room: Room
    let isEditMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void
    @State private var appeared = false

    var body: some View {
        RoomRow(
            room: room,
            isEditMode: isEditMode,
            isSelected: isSelected,
            onTap: onTap,
            onComplete: onComplete,
            onDelete: onDelete
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -6)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
    }
}
