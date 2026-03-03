import AppKit
import SwiftUI

extension Notification.Name {
    static let sidebarHideRequested = Notification.Name("sidebarHideRequested")
    static let roomMinimizeRequested = Notification.Name("roomMinimizeRequested")
}

class ClickThroughPanel: NSPanel {
    /// 상단 드래그 영역 높이 (SwiftUI 드래그 핸들 + 헤더 영역)
    private let dragZoneHeight: CGFloat = 24

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        // 상단 드래그 영역에서 좌클릭 → 윈도우 드래그
        if event.type == .leftMouseDown {
            let loc = event.locationInWindow
            if loc.y >= frame.height - dragZoneHeight {
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
    }

    // 시스템 프레임 제약 비활성화 (듀얼 모니터에서 잘못된 화면으로 끌려가는 문제 방지)
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var sidebarPanel: NSPanel!

    let agentStore = AgentStore()
    let providerManager = ProviderManager()
    let chatVM = ChatViewModel()
    let roomManager = RoomManager()
    private var statusItem: NSStatusItem?
    private var sidebarHotkeyMonitor: Any?
    private var sidebarGlobalMonitor: Any?

    private var isSidebarVisible = false
    private var panelWidth: CGFloat = 400
    /// 현재 사이드바가 표시 중인 화면
    private weak var currentScreen: NSScreen?
    /// 온보딩 윈도우
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 구 도메인(AgentManager) → 신 도메인(DOUGLAS) 마이그레이션
        migrateUserDefaultsIfNeeded()

        // RoomManager 먼저 설정
        roomManager.configure(agentStore: agentStore, providerManager: providerManager)
        roomManager.loadRooms()

        // ChatViewModel에 RoomManager 포함하여 설정
        chatVM.configure(agentStore: agentStore, providerManager: providerManager, roomManager: roomManager)
        chatVM.loadMessages()

        // 에이전트 삭제 시 채팅 기록 + 첨부 파일 정리
        agentStore.onAgentRemoved = { [weak self] agentID in
            self?.chatVM.clearMessages(for: agentID)
        }

        // 고아 데이터 정리 (존재하지 않는 에이전트의 채팅 + 미참조 첨부 파일)
        cleanupOrphanedData()

        // 기존 사용자 감지: 이미 프로바이더가 설정되어 있으면 온보딩 스킵
        if !OnboardingViewModel.isCompleted {
            let hasConfigured = providerManager.configs.contains { config in
                config.type == .claudeCode || config.apiKey != nil
            }
            if hasConfigured {
                OnboardingViewModel.isCompleted = true
            }
        }

        // 온보딩 필요 시 → 온보딩 먼저, 완료 후 사이드바 시작
        if !OnboardingViewModel.isCompleted {
            showOnboardingWindow()
            return
        }

        // 정상 시작
        startNormalFlow()
    }

    /// 사이드바 + 알림 + 상태바 아이콘 시작
    private func startNormalFlow() {
        createSidebarPanel()
        setupNotifications()
        setupStatusItem()
        registerSidebarHotkey()
        // 사이드바 자동 표시
        showSidebar()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .sidebarHideRequested, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hideSidebar()
            }
        }
    }

    // MARK: - 상태바 아이콘 (클릭 → 사이드바 토글)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            if let profileImage = loadProfileImage() {
                let size: CGFloat = 18
                let resized = NSImage(size: NSSize(width: size, height: size))
                resized.lockFocus()
                // 원형 클리핑
                let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size))
                path.addClip()
                profileImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
                resized.unlockFocus()
                resized.isTemplate = false
                button.image = resized
            } else {
                button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "DOUGLAS")
            }
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func loadProfileImage() -> NSImage? {
        // SPM 리소스 번들 이름은 DOUGLAS_DOUGLAS.bundle
        let bundleNames = ["DOUGLAS_DOUGLAS.bundle", "DOUGLAS_DOUGLASLib.bundle"]
        for name in bundleNames {
            if let url = Bundle.main.resourceURL?
                .appendingPathComponent(name)
                .appendingPathComponent("douglas_profile.png"),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        if let url = Bundle.main.url(forResource: "douglas_profile", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else if event.clickCount == 2 {
            // 더블클릭: 오른쪽 사이드바 위치로 스냅
            snapSidebarToRight()
        } else {
            toggleSidebar()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    // MARK: - 사이드바 핫키 (Cmd+Shift+E)

    private func registerSidebarHotkey() {
        sidebarGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isSidebarHotkey(event) {
                Task { @MainActor [weak self] in self?.toggleSidebar() }
            }
        }
        sidebarHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isSidebarHotkey(event) {
                Task { @MainActor [weak self] in self?.toggleSidebar() }
                return nil
            }
            return event
        }
    }

    private static func isSidebarHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 0x0E && flags == [.command, .shift] // 0x0E = 'e'
    }

    // MARK: - 온보딩

    private func showOnboardingWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "DOUGLAS 설정"
        window.center()

        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.startNormalFlow()
        })
        .environmentObject(providerManager)
        .environmentObject(agentStore)

        window.contentView = NSHostingView(rootView: onboardingView)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 강제 종료 시 디바운스 대기 중인 데이터 손실 방지 — 동기 저장
        roomManager.saveRooms()
        chatVM.saveMessages()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - 고아 데이터 정리

    /// 앱 시작 시 미참조 채팅 기록 및 첨부 이미지 파일 삭제
    private func cleanupOrphanedData() {
        // 1) 존재하지 않는 에이전트의 채팅 기록 삭제
        let validAgentIDs = Set(agentStore.agents.map { $0.id })
        chatVM.pruneOrphanedChats(validAgentIDs: validAgentIDs)

        // 2) 어디에도 참조되지 않는 첨부 이미지 파일 삭제
        var referencedFilenames: Set<String> = []
        // 채팅 메시지의 첨부
        for (_, messages) in chatVM.messagesByAgent {
            for msg in messages {
                msg.attachments?.forEach { referencedFilenames.insert($0.filename) }
            }
        }
        // 방 메시지의 첨부
        for room in roomManager.rooms {
            for msg in room.messages {
                msg.attachments?.forEach { referencedFilenames.insert($0.filename) }
            }
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let attachDir = appSupport?.appendingPathComponent("DOUGLAS/attachments") else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: attachDir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            if !referencedFilenames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - UserDefaults 마이그레이션

    /// AgentManager → DOUGLAS 리네이밍 시 UserDefaults 도메인 마이그레이션
    private func migrateUserDefaultsIfNeeded() {
        let migrated = UserDefaults.standard.bool(forKey: "migrated_from_AgentManager")
        guard !migrated else { return }

        // 구 도메인에서 데이터 읽기
        guard let oldDefaults = UserDefaults(suiteName: "AgentManager") else { return }
        let oldDict = oldDefaults.dictionaryRepresentation()

        // 마이그레이션 대상 키
        let keysToMigrate = ["onboardingCompleted", "savedAgents", "providerConfigs"]
        var didMigrate = false
        for key in keysToMigrate {
            if let value = oldDict[key], UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(value, forKey: key)
                didMigrate = true
            }
        }

        if didMigrate {
            UserDefaults.standard.set(true, forKey: "migrated_from_AgentManager")
        }
    }

    // MARK: - 사이드바 패널

    func createSidebarPanel() {
        guard let screen = NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame

        let panelFrame = NSRect(
            x: screenFrame.maxX - panelWidth,
            y: screenFrame.minY,
            width: panelWidth,
            height: screenFrame.height
        )

        sidebarPanel = ClickThroughPanel(
            contentRect: panelFrame,
            styleMask: [.nonactivatingPanel, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )

        sidebarPanel.title = "Tell, Don't Ask"
        sidebarPanel.level = .normal
        sidebarPanel.isFloatingPanel = false
        sidebarPanel.hidesOnDeactivate = false
        sidebarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sidebarPanel.isMovableByWindowBackground = false
        sidebarPanel.backgroundColor = .clear
        sidebarPanel.isOpaque = false
        sidebarPanel.titlebarAppearsTransparent = true
        sidebarPanel.titleVisibility = .hidden
        sidebarPanel.hasShadow = false
        sidebarPanel.minSize = NSSize(width: 320, height: 400)
        sidebarPanel.maxSize = NSSize(width: 800, height: screenFrame.height)

        let sidebarView = FloatingSidebarView()
            .environmentObject(agentStore)
            .environmentObject(providerManager)
            .environmentObject(chatVM)
            .environmentObject(roomManager)

        let hostingView = ClickThroughHostingView(rootView: sidebarView)
        sidebarPanel.contentView = hostingView

        // SwiftUI에서 머티리얼 + 라운딩 처리 (AppKit 레벨 불필요)
        hostingView.wantsLayer = true

        sidebarPanel.setFrame(panelFrame, display: true)

        sidebarPanel.alphaValue = 0
        sidebarPanel.ignoresMouseEvents = true
        sidebarPanel.orderFront(nil)
        isSidebarVisible = false
    }

    // MARK: - 사이드바 Show / Hide

    /// 사용자가 리사이즈한 현재 너비
    private var currentPanelWidth: CGFloat {
        sidebarPanel?.frame.width ?? panelWidth
    }

    private func showSidebar(on screen: NSScreen? = nil) {
        guard !isSidebarVisible else { return }
        guard let screen = screen ?? NSScreen.screens.first else { return }
        isSidebarVisible = true
        currentScreen = screen
        sidebarPanel.ignoresMouseEvents = false
        let sf = screen.visibleFrame
        let w = currentPanelWidth
        let targetX = sf.maxX - w
        // 8pt 오른쪽에서 시작 → 원위치로 슬라이드
        sidebarPanel.setFrame(NSRect(x: targetX + 8, y: sf.minY, width: w, height: sf.height), display: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.sidebarPanel.animator().alphaValue = 1.0
            self.sidebarPanel.animator().setFrame(
                NSRect(x: targetX, y: sf.minY, width: w, height: sf.height),
                display: true
            )
        }
    }

    private func hideSidebar() {
        guard isSidebarVisible else { return }
        isSidebarVisible = false
        sidebarPanel.ignoresMouseEvents = true
        let w = currentPanelWidth
        if let screen = currentScreen ?? NSScreen.screens.first {
            let sf = screen.visibleFrame
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.sidebarPanel.animator().alphaValue = 0.0
                self.sidebarPanel.animator().setFrame(
                    NSRect(x: sf.maxX - w + 8, y: sf.minY, width: w, height: sf.height),
                    display: true
                )
            })
        }
        currentScreen = nil
    }

    /// 사이드바를 오른쪽 끝으로 스냅 (더블클릭 시)
    private func snapSidebarToRight() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.screens.first
        guard let screen = screen else { return }
        let sf = screen.visibleFrame
        let w = currentPanelWidth
        let targetX = sf.maxX - w

        if !isSidebarVisible {
            // 숨겨져 있으면 오른쪽에서 표시
            showSidebar(on: screen)
        } else {
            // 이미 표시 중이면 오른쪽으로 애니메이션 이동
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.sidebarPanel.animator().setFrame(
                    NSRect(x: targetX, y: sf.minY, width: w, height: sf.height),
                    display: true
                )
            }
            currentScreen = screen
        }
    }

    // MARK: - 수동 토글

    func toggleSidebar() {
        if isSidebarVisible {
            hideSidebar()
        } else {
            // 마우스가 있는 화면에 표시
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            showSidebar(on: screen)
        }
    }

}
