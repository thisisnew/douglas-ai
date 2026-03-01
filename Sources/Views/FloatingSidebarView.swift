import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 유틸리티 윈도우 관리: 참조를 유지해 메모리 누수 방지
@MainActor
final class UtilityWindowManager {
    static let shared = UtilityWindowManager()
    private(set) var windows: [NSWindow] = []
    private var observers: [NSWindow: Any] = [:]
    /// 윈도우 식별자 (title 대신 고유 ID로 중복 판별)
    private var windowIdentifiers: [NSWindow: String] = [:]

    /// 열려있는 유틸리티 윈도우가 있는지
    var hasOpenWindows: Bool { !windows.isEmpty }

    func open<Content: View>(
        title: String,
        identifier: String? = nil,
        width: CGFloat,
        height: CGFloat,
        agentStore: AgentStore,
        providerManager: ProviderManager,
        chatVM: ChatViewModel,
        roomManager: RoomManager? = nil,
        @ViewBuilder content: () -> Content
    ) {
        // 같은 identifier의 윈도우가 이미 열려 있으면 포커스만
        let windowID = identifier ?? title
        if let existing = windows.first(where: { windowIdentifiers[$0] == windowID }) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 일반 NSWindow 사용 (NSPanel 아님) — 텍스트 입력 문제 방지
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = title
        window.minSize = NSSize(width: width * 0.8, height: height * 0.8)
        var rootView = AnyView(content()
            .environmentObject(agentStore)
            .environmentObject(providerManager)
            .environmentObject(chatVM))
        if let roomMgr = roomManager {
            rootView = AnyView(rootView.environmentObject(roomMgr))
        }
        window.contentView = NSHostingView(rootView: rootView)
        window.center()

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let closedWindow = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in self?.cleanup(closedWindow) }
        }
        observers[window] = observer
        windowIdentifiers[window] = windowID
        windows.append(window)

        // 사이드바보다 높은 레벨로 표시 (사이드바 조작 없이)
        window.level = .floating + 1
        // MenuBarExtra 앱은 기본적으로 키보드 입력을 못 받음
        // → 유틸리티 윈도우가 열릴 때 .regular로 전환해서 TextField 입력 가능하게
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 페이드인 애니메이션
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    private func cleanup(_ window: NSWindow) {
        if let observer = observers.removeValue(forKey: window) {
            NotificationCenter.default.removeObserver(observer)
        }
        windowIdentifiers.removeValue(forKey: window)
        windows.removeAll { $0 === window }
        // 모든 유틸리티 윈도우가 닫히면 다시 accessory로 복원 (Dock 아이콘 숨김)
        if windows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - 슬래시 커맨드 모델

struct SlashCommand: Identifiable {
    let id: String
    let label: String
    let description: String
    let icon: String
    let iconColor: Color
    let takesArgument: Bool

    static let all: [SlashCommand] = [
        .init(id: "clear", label: "/clear", description: "채팅 내역 초기화",
              icon: "trash", iconColor: .red, takesArgument: false),
    ]

    static func filtered(by text: String) -> [SlashCommand] {
        let lower = text.lowercased()
        if lower == "/" { return all }
        return all.filter { $0.label.hasPrefix(lower) }
    }
}

// MARK: - 슬래시 메뉴 키보드 상태

@MainActor
final class SlashMenuState: ObservableObject {
    @Published var selectedIndex = 0
    private var monitor: Any?

    func startMonitoring(
        commandCount: Int,
        onSelect: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        stopMonitoring()
        selectedIndex = 0
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 125: // ↓
                self.selectedIndex = min(self.selectedIndex + 1, commandCount - 1)
                return nil
            case 126: // ↑
                self.selectedIndex = max(self.selectedIndex - 1, 0)
                return nil
            case 36:  // Return
                onSelect(self.selectedIndex)
                return nil
            case 53:  // Escape
                onDismiss()
                return nil
            default:
                return event
            }
        }
    }

    func stopMonitoring() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - 메인 사이드바 뷰

struct FloatingSidebarView: View {
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var providerManager: ProviderManager
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var roomManager: RoomManager

    @State private var inputText = ""
    @State private var previousInputText = ""
    @State private var pendingAttachments: [ImageAttachment] = []
    @State private var showSlashMenu = false
    @State private var filteredCommands: [SlashCommand] = SlashCommand.all
    @StateObject private var slashMenu = SlashMenuState()
    @FocusState private var isInputFocused: Bool
    /// Room 목록 높이 (pt 단위, 드래그로 조절)
    @State private var roomListHeight: CGFloat = 160
    @State private var roomDragStartHeight: CGFloat = 160
    /// 윈도우 드래그 시작 시 마우스-윈도우 간 오프셋
    @State private var windowDragOffset: CGFloat = 0
    @State private var isDraggingWindow = false
    /// 드래그 앤 드롭 재정렬
    @State private var draggingAgentID: UUID?
    @State private var dropTargetAgentID: UUID?
    @State private var hoveredAgentID: UUID?
    /// 아바타 확대 보기
    @State private var enlargedAvatarAgent: Agent?
    @State private var showEnlargedProfile = false

    private var masterAgent: Agent? { agentStore.masterAgent }
    private var masterID: UUID? { masterAgent?.id }

    /// 서브에이전트만 (로스터에 표시, 마스터/DevAgent 제외)
    private var allRosterAgents: [Agent] {
        agentStore.subAgents
    }

    // MARK: - 커스텀 구분선

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    @State private var sectionHandleHovered = false
    /// 방 열기 프로그레스 (nil이면 비활성)
    @State private var roomOpenProgress: CGFloat?
    @State private var pendingRoomToOpen: UUID?
    @State private var showCancelledMark = false

    /// 상단 드래그 핸들 — AppKit performDrag가 실제 이동을 처리
    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.primary.opacity(0.15))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.openHand.push() }
                else { NSCursor.pop() }
            }
    }

    var body: some View {
        GeometryReader { sidebarGeo in
            VStack(spacing: 0) {
                // ── 드래그 핸들 ──
                dragHandle

                // ── 헤더 ──
                header

                // ── 에이전트 로스터 (가로 스크롤) ──
                agentRoster
                    .padding(.vertical, 10)

                separator

                // ── 방 목록 (높이 조절 가능) ──
                VStack(spacing: 0) {
                    RoomListView(
                        onCreateRoom: { openCreateRoomWindow() },
                        onRoomTap: { roomID in openRoomChatWindow(roomID: roomID) }
                    )
                }
                .frame(height: roomListHeight)
                .clipped()

                // ── 섹션 리사이즈 핸들 ──
                sectionResizeHandle(sidebarHeight: sidebarGeo.size.height)

                // ── 채팅 영역 (항상 마스터 채팅, 남은 공간 차지) ──
                if let id = masterID {
                    masterChatArea(agentID: id)
                }

                // ── 토스트 ──
                if chatVM.showToast, let msg = chatVM.toastMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.red.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .continuousRadius(DesignTokens.Sidebar.cornerRadius)
        .shadow(color: .black.opacity(DesignTokens.Sidebar.shadowOpacity), radius: DesignTokens.Sidebar.shadowRadius, x: -4, y: 0)
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .animation(.dgSlow, value: chatVM.showToast)
        .onChange(of: roomManager.pendingAutoOpenRoomID) { _, newID in
            if let roomID = newID {
                roomManager.pendingAutoOpenRoomID = nil
                pendingRoomToOpen = roomID
                roomOpenProgress = 0
                // 타이머로 0→1 점진 증가 (2.5초 동안 ~60 프레임)
                let totalDuration: Double = 2.5
                let interval: Double = 1.0 / 60.0
                let step: CGFloat = CGFloat(interval / totalDuration)
                Task {
                    while let current = roomOpenProgress, current < 1.0 {
                        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                        await MainActor.run {
                            if roomOpenProgress != nil {
                                roomOpenProgress = min((roomOpenProgress ?? 0) + step, 1.0)
                            }
                        }
                    }
                    await MainActor.run {
                        guard pendingRoomToOpen != nil else { return }
                        openRoomChatWindow(roomID: roomID)
                        roomOpenProgress = nil
                        pendingRoomToOpen = nil
                    }
                }
            }
        }
        .sheet(item: $enlargedAvatarAgent) { agent in
            avatarEnlargedView(agent: agent)
        }
        .sheet(isPresented: $showEnlargedProfile) {
            profileEnlargedView
        }
    }

    // MARK: - 섹션 리사이즈 핸들 (Room ↔ Chat)

    private func sectionResizeHandle(sidebarHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 14)
            .overlay(
                Capsule()
                    .fill(Color.primary.opacity(sectionHandleHovered ? 0.3 : 0.12))
                    .frame(width: 36, height: 4)
                    .animation(.dgFast, value: sectionHandleHovered)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newHeight = roomDragStartHeight + value.translation.height
                        let minH: CGFloat = 120
                        let maxH: CGFloat = sidebarHeight * 0.5
                        withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.9)) {
                            roomListHeight = min(maxH, max(minH, newHeight))
                        }
                    }
                    .onEnded { _ in
                        roomDragStartHeight = roomListHeight
                    }
            )
            .onHover { hovering in
                sectionHandleHovered = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: 10) {
            // 프로필 이미지
            ProfileImageView(size: 28)
                .onTapGesture { showEnlargedProfile = true }
            Text("DOUGLAS")
                .font(.system(size: 14, weight: .semibold))
                .tracking(1.5)
            Spacer()
            Button(action: { openAddAgentWindow() }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("에이전트 추가")

            Button(action: { openWorkLogWindow() }) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("작업일지")

            Button(action: { openProviderWindow() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("API 설정")

            // 사이드바 숨기기
            Button(action: {
                NotificationCenter.default.post(name: .sidebarHideRequested, object: nil)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .background(DesignTokens.Colors.closeButton)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("사이드바 닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 에이전트 로스터 (가로 스크롤)

    private var agentRoster: some View {
        Group {
            if allRosterAgents.isEmpty {
                // 빈 상태: 에이전트 추가 유도
                Button(action: { openAddAgentWindow() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.dashed")
                            .font(.system(size: 14))
                        Text("에이전트 추가")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Layout.rosterSpacing) {
                ForEach(allRosterAgents) { agent in
                    rosterItem(agent)
                        .padding(.top, 6)  // 뱃지 잘림 방지
                        .opacity(draggingAgentID == agent.id ? 0.4 : 1.0)
                        .scaleEffect(draggingAgentID == agent.id ? 0.85 : (dropTargetAgentID == agent.id ? 1.08 : 1.0))
                        // 호버 시 하이라이트
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(hoveredAgentID == agent.id ? Color.accentColor.opacity(0.08) : Color.clear)
                                .padding(-4)
                        )
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredAgentID = isHovered ? agent.id : nil
                            }
                        }
                        .onDrag {
                            draggingAgentID = agent.id
                            return NSItemProvider(object: agent.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: AgentReorderDropDelegate(
                            targetID: agent.id,
                            draggingID: $draggingAgentID,
                            dropTargetID: $dropTargetAgentID,
                            onReorder: { from, to in
                                agentStore.moveSubAgent(fromID: from, toID: to)
                            }
                        ))
                        .contextMenu {
                            Button {
                                openEditWindow(for: agent)
                            } label: {
                                Label("편집", systemImage: "pencil")
                            }
                            Button {
                                openInfoWindow(for: agent)
                            } label: {
                                Label("정보", systemImage: "info.circle")
                            }
                            if !agent.isMaster {
                                Divider()
                                Button(role: .destructive) {
                                    agentStore.removeAgent(agent)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .animation(.easeInOut(duration: 0.2), value: allRosterAgents.map(\.id))
        }
            } // else
        } // Group
    }

    /// 개별 에이전트 로스터 아이템: 아바타 + 상태 표시등 + 이름 + 방 수 뱃지
    private func rosterItem(_ agent: Agent) -> some View {
        let roomCount = roomManager.activeRoomCount(for: agent.id)

        return VStack(spacing: DesignTokens.Spacing.sm) {
            AgentAvatarView(agent: agent, size: DesignTokens.AvatarSize.lg)
                .onTapGesture {
                    if agent.hasImage {
                        enlargedAvatarAgent = agent
                    } else {
                        openInfoWindow(for: agent)
                    }
                }
                // 상태 표시등 (우하단)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(statusColor(agent))
                        .frame(width: DesignTokens.Layout.statusIndicatorSize,
                               height: DesignTokens.Layout.statusIndicatorSize)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: 1.5)
                        )
                        .offset(x: 2, y: 2)
                }
                // 방 수 뱃지 (우상단, 1개 이상)
                .overlay(alignment: .topTrailing) {
                    if roomCount >= 1 {
                        Text("\(roomCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
                // 작업중 테두리
                .overlay {
                    if agent.status == .working || agent.status == .busy {
                        Circle().stroke(
                            DesignTokens.StatusColor.color(for: agent.status).opacity(0.5),
                            lineWidth: 2
                        )
                    }
                }

            Text(agent.name)
                .font(.caption2)
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: DesignTokens.Layout.rosterItemWidth)
                .onTapGesture { openInfoWindow(for: agent) }
        }
    }

    private func statusColor(_ agent: Agent) -> Color {
        DesignTokens.StatusColor.color(for: agent.status)
    }

    /// 아바타 확대 보기 시트
    private func avatarEnlargedView(agent: Agent) -> some View {
        VStack(spacing: 16) {
            if let data = agent.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text(agent.name)
                .font(.headline)

            Button("닫기") { enlargedAvatarAgent = nil }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 320, height: 380)
    }

    /// 프로필 이미지 확대 보기 시트
    private var profileEnlargedView: some View {
        VStack(spacing: 16) {
            ProfileImageView(size: 240)

            Text("DOUGLAS")
                .font(.headline)

            Button("닫기") { showEnlargedProfile = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 320, height: 380)
    }

    // MARK: - 마스터 채팅 영역

    private func masterChatArea(agentID: UUID) -> some View {
            VStack(spacing: 0) {
                // 메시지 목록
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if chatVM.messages(for: agentID).isEmpty {
                                VStack(spacing: 8) {
                                    Spacer(minLength: 40)
                                    Text("어떤 작업을 해볼까요?")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                    Text("메시지를 입력하면 팀이 작업을 시작합니다")
                                        .font(.caption)
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity)
                            }

                            let lastDelegationID = chatVM.messages(for: agentID).last(where: { $0.messageType == .delegation })?.id
                            ForEach(chatVM.messages(for: agentID)) { message in
                                if message.id == lastDelegationID && pendingRoomToOpen != nil {
                                    HStack(alignment: .center, spacing: 8) {
                                        MessageBubble(message: message)
                                        RoomOpenProgressRing(
                                            progress: roomOpenProgress ?? 0,
                                            onCancel: { cancelPendingRoomOpen() }
                                        )
                                    }
                                    .id(message.id)
                                } else if message.id == lastDelegationID && showCancelledMark {
                                    HStack(alignment: .center, spacing: 8) {
                                        MessageBubble(message: message)
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.red.opacity(0.6))
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                    .id(message.id)
                                } else {
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }

                            if chatVM.loadingAgentIDs.contains(agentID) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("처리 중...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button(action: { chatVM.cancelTask(for: agentID) }) {
                                        Image(systemName: "stop.circle.fill")
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                    .help("작업 취소")
                                }
                                .padding(.horizontal)
                                .id("loading")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: chatVM.messages(for: agentID).count) { _, _ in
                        if let last = chatVM.messages(for: agentID).last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                separator

                // 슬래시 커맨드 메뉴
                if showSlashMenu {
                    slashCommandMenu(agentID: agentID)
                }

                // 입력 영역
                VStack(spacing: 4) {
                    // 첨부 이미지 미리보기
                    if !pendingAttachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(pendingAttachments) { att in
                                    AttachmentThumbnail(attachment: att) {
                                        att.delete()
                                        pendingAttachments.removeAll { $0.id == att.id }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                        }
                    }

                    HStack(spacing: 8) {
                        // 이미지 첨부 버튼
                        Button(action: pickImage) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("이미지 첨부 (JPG, PNG, GIF, WebP)")

                        TextField("Tell Don't Ask", text: $inputText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...5)
                            .focused($isInputFocused)
                            .onSubmit {
                                if NSEvent.modifierFlags.contains(.shift) {
                                    inputText += "\n"
                                } else {
                                    sendToMaster()
                                }
                            }
                            .onChange(of: inputText) { _, newValue in
                                // 드롭된 파일 경로 감지 → 이미지 첨부로 변환
                                if let remaining = extractDroppedImagePath(from: newValue) {
                                    inputText = remaining
                                    previousInputText = remaining
                                    return
                                }
                                previousInputText = newValue

                                let matched = SlashCommand.filtered(by: newValue)
                                let shouldShow = newValue.hasPrefix("/") && !matched.isEmpty
                                withAnimation(.dgFast) {
                                    filteredCommands = matched
                                    showSlashMenu = shouldShow
                                }
                                if shouldShow {
                                    slashMenu.startMonitoring(
                                        commandCount: matched.count,
                                        onSelect: { idx in executeSlashCommand(matched[idx]) },
                                        onDismiss: { inputText = ""; showSlashMenu = false }
                                    )
                                } else {
                                    slashMenu.stopMonitoring()
                                }
                            }

                        SendButton(
                            canSend: canSend,
                            isLoading: chatVM.loadingAgentIDs.contains(agentID),
                            action: sendToMaster
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(DesignTokens.Colors.inputBackground)
                .continuousRadius(DesignTokens.Radius.lg)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .disabled(pendingRoomToOpen != nil)
                .opacity(pendingRoomToOpen != nil ? 0.5 : 1.0)
                .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                    handleImageDrop(providers)
                    return true
                }
            }
    }

    // MARK: - 슬래시 커맨드 메뉴

    private func slashCommandMenu(agentID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { idx, cmd in
                Button {
                    executeSlashCommand(cmd)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: cmd.icon)
                            .font(.caption)
                            .foregroundColor(cmd.iconColor)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cmd.label)
                                .font(.caption.bold())
                            Text(cmd.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if cmd.takesArgument {
                            Text("메시지 입력")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(slashMenu.selectedIndex == idx
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(DesignTokens.Colors.inputBackground)
        .continuousRadius(DesignTokens.Radius.xl)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - 슬래시 커맨드 실행

    private func executeSlashCommand(_ cmd: SlashCommand) {
        guard masterID != nil else { return }

        switch cmd.id {
        case "clear":
            if let id = masterID {
                chatVM.clearMessages(for: id)
            }
            inputText = ""
            showSlashMenu = false
            slashMenu.stopMonitoring()

        default:
            break
        }
    }

    // MARK: - 전송

    /// 전송 가능 여부 (텍스트 또는 첨부 이미지가 있으면 true)
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    private func sendToMaster() {
        guard let id = masterID else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }

        // /clear 처리
        if text.lowercased() == "/clear" {
            chatVM.clearMessages(for: id)
            inputText = ""
            previousInputText = ""
            pendingAttachments = []
            showSlashMenu = false
            slashMenu.stopMonitoring()
            return
        }

        let attachments = pendingAttachments.isEmpty ? nil : pendingAttachments
        inputText = ""
        previousInputText = ""
        pendingAttachments = []
        showSlashMenu = false
        slashMenu.stopMonitoring()
        chatVM.sendMessage(text.isEmpty ? "[이미지]" : text, agentID: id, attachments: attachments)
    }

    // MARK: - 이미지 첨부

    private func pickImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .gif, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "첨부할 이미지를 선택하세요"
        panel.level = .modalPanel
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addImageFromURL(url)
        }
    }

    private func addImageFromURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let mime = ImageAttachment.mimeType(for: data) else { return }
        guard let attachment = try? ImageAttachment.save(data: data, mimeType: mime) else { return }
        pendingAttachments.append(attachment)
    }

    /// 이전 텍스트와 비교하여 드롭으로 삽입된 이미지 경로를 감지 → 첨부로 변환
    /// 성공 시 경로를 제거한 텍스트 반환, 실패 시 nil
    private func extractDroppedImagePath(from text: String) -> String? {
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp"])

        // 이전 텍스트와 비교하여 삽입된 부분 추출
        let oldText = previousInputText
        guard text.count > oldText.count + 3 else { return nil } // 최소 경로 길이

        // 삽입된 텍스트 추출: 이전 텍스트를 제거하면 삽입된 부분만 남음
        var inserted = text
        for char in oldText {
            if let idx = inserted.firstIndex(of: char) {
                inserted.remove(at: idx)
            }
        }
        inserted = inserted.trimmingCharacters(in: .whitespacesAndNewlines)

        // 삽입된 텍스트에서 경로 추출 시도
        var path = inserted

        // file:// URL 처리
        if path.hasPrefix("file://") {
            path = path.replacingOccurrences(of: "file://", with: "")
        }
        path = path.removingPercentEncoding ?? path

        // 이미지 확장자 확인
        let ext = (path as NSString).pathExtension.lowercased()
        guard imageExtensions.contains(ext) else { return nil }

        // 파일 존재 확인
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }

        // 이미지 로드 + 첨부 생성
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let mime = ImageAttachment.mimeType(for: data),
              let attachment = try? ImageAttachment.save(data: data, mimeType: mime) else { return nil }

        pendingAttachments.append(attachment)
        return oldText // 삽입 전 텍스트로 복원
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data = data,
                          let mime = ImageAttachment.mimeType(for: data),
                          let attachment = try? ImageAttachment.save(data: data, mimeType: mime) else { return }
                    DispatchQueue.main.async {
                        pendingAttachments.append(attachment)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let fileData = try? Data(contentsOf: url),
                          let mime = ImageAttachment.mimeType(for: fileData),
                          let attachment = try? ImageAttachment.save(data: fileData, mimeType: mime) else { return }
                    DispatchQueue.main.async {
                        pendingAttachments.append(attachment)
                    }
                }
            }
        }
    }

    // attachmentThumbnail → SharedComponents.AttachmentThumbnail 사용

    // MARK: - 윈도우 열기 헬퍼

    private func openAddAgentWindow() {
        UtilityWindowManager.shared.open(title: "새 에이전트",
            width: DesignTokens.WindowSize.agentSheet.width, height: DesignTokens.WindowSize.agentSheet.height,
            agentStore: agentStore, providerManager: providerManager, chatVM: chatVM) {
            AddAgentSheet()
        }
    }

    private func openProviderWindow() {
        UtilityWindowManager.shared.open(title: "API 설정",
            width: DesignTokens.WindowSize.providerSheet.width, height: DesignTokens.WindowSize.providerSheet.height,
            agentStore: agentStore, providerManager: providerManager, chatVM: chatVM) {
            AddProviderSheet()
        }
    }

    private func openEditWindow(for agent: Agent) {
        UtilityWindowManager.shared.open(title: "\(agent.name) 편집",
            width: DesignTokens.WindowSize.agentSheet.width, height: DesignTokens.WindowSize.agentSheet.height,
            agentStore: agentStore, providerManager: providerManager, chatVM: chatVM) {
            EditAgentSheet(agent: agent)
        }
    }

    private func openInfoWindow(for agent: Agent) {
        UtilityWindowManager.shared.open(title: "\(agent.name) 정보",
            width: DesignTokens.WindowSize.agentInfoSheet.width, height: DesignTokens.WindowSize.agentInfoSheet.height,
            agentStore: agentStore, providerManager: providerManager, chatVM: chatVM) {
            AgentInfoSheet(agent: agent)
        }
    }

    private func cancelPendingRoomOpen() {
        pendingRoomToOpen = nil
        roomOpenProgress = nil
        showCancelledMark = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) { showCancelledMark = false }
            }
        }
    }

    private func openRoomChatWindow(roomID: UUID) {
        let title = roomManager.rooms.first(where: { $0.id == roomID })?.title ?? "방"
        UtilityWindowManager.shared.open(title: title, identifier: roomID.uuidString,
            width: DesignTokens.WindowSize.roomChat.width, height: DesignTokens.WindowSize.roomChat.height,
            agentStore: agentStore, providerManager: providerManager, chatVM: chatVM, roomManager: roomManager) {
            RoomChatView(roomID: roomID)
        }
    }

    private func openWorkLogWindow() {
        UtilityWindowManager.shared.open(title: "작업일지",
            width: DesignTokens.WindowSize.workLog.width, height: DesignTokens.WindowSize.workLog.height,
            agentStore: agentStore, providerManager: providerManager, chatVM: chatVM, roomManager: roomManager) {
            WorkLogView()
        }
    }

    private func openCreateRoomWindow() {
        UtilityWindowManager.shared.open(title: "새 방 만들기",
            width: DesignTokens.WindowSize.createRoomSheet.width, height: DesignTokens.WindowSize.createRoomSheet.height,
            agentStore: agentStore, providerManager: providerManager, chatVM: chatVM, roomManager: roomManager) {
            CreateRoomSheet()
        }
    }
}

// MARK: - 프로필 이미지

struct ProfileImageView: View {
    let size: CGFloat

    private var nsImage: NSImage? {
        // 1. Bundle.module (SPM 리소스)
        if let url = Bundle.module.url(forResource: "douglas_profile", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // 2. Contents/Resources/ 내 번들
        for name in ["DOUGLAS_DOUGLAS.bundle", "DOUGLAS_DOUGLASLib.bundle"] {
            if let url = Bundle.main.resourceURL?
                .appendingPathComponent(name)
                .appendingPathComponent("douglas_profile.png"),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        // 3. Bundle.main 직접
        if let url = Bundle.main.url(forResource: "douglas_profile", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }

    var body: some View {
        if let img = nsImage {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            // 폴백: 이니셜
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text("D")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.blue)
                )
        }
    }
}

// MARK: - 에이전트 정보 시트

struct AgentInfoSheet: View {
    let agent: Agent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AgentAvatarView(agent: agent, size: 40)
                VStack(alignment: .leading) {
                    Text(agent.name)
                        .font(.title2.bold())
                    if agent.isMaster {
                        Text("총괄")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
                Spacer()
            }
            .padding()

            Divider()

            List {
                Section("모델") {
                    LabeledContent("API", value: agent.providerName)
                    LabeledContent("모델", value: agent.modelName)
                    LabeledContent("상태", value: statusText)
                }

                Section("역할 설명") {
                    Text(agent.persona)
                        .font(.body)
                        .textSelection(.enabled)
                }

                if let rules = agent.workingRules, !rules.isEmpty {
                    Section("작업 규칙") {
                        if !rules.inlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(rules.inlineText)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        ForEach(rules.filePaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "doc.text")
                                Text((path as NSString).lastPathComponent)
                                    .font(.body)
                                Spacer()
                                Text(path)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }

                if let err = agent.errorMessage {
                    Section("최근 오류") {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 480, height: 480)
    }

    private var statusText: String {
        switch agent.status {
        case .idle:    return "대기"
        case .working: return "작업중"
        case .busy:    return "바쁨"
        case .error:   return "오류"
        }
    }
}

// MARK: - 에이전트 로스터 드래그 앤 드롭

struct AgentReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: UUID?
    @Binding var dropTargetID: UUID?
    let onReorder: (UUID, UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.easeOut(duration: 0.2)) {
            draggingID = nil
            dropTargetID = nil
        }
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let from = draggingID, from != targetID else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            dropTargetID = targetID
            onReorder(from, targetID)
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeOut(duration: 0.15)) {
            if dropTargetID == targetID {
                dropTargetID = nil
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - 방 열기 원형 프로그레스 (숫자 + 링, hover 시 정지 버튼)

struct RoomOpenProgressRing: View {
    let progress: CGFloat
    var onCancel: (() -> Void)?
    private let size: CGFloat = 30
    private let lineWidth: CGFloat = 3
    @State private var isHovered = false

    var body: some View {
        ZStack {
            if isHovered {
                // hover 시: 정지 버튼
                Circle()
                    .fill(Color.red.opacity(0.12))
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)
            } else {
                // 기본: 프로그레스 링 + 숫자
                Circle()
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress * 100))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onHover { isHovered = $0 }
        .onTapGesture { onCancel?() }
        .help(isHovered ? "작업 취소" : "")
    }
}
