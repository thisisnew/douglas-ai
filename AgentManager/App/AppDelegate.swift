import AppKit
import SwiftUI

extension Notification.Name {
    static let sidebarHideRequested = Notification.Name("sidebarHideRequested")
    static let sidebarPinToggled = Notification.Name("sidebarPinToggled")
}

class ClickThroughPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // 패널 프레임 제한 — 높이만 화면에 맞추고, x 위치는 AppDelegate가 제어
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen = screen ?? NSScreen.screens.first else { return frameRect }
        var rect = frameRect
        rect.origin.y = screen.visibleFrame.minY
        rect.size.height = screen.visibleFrame.height
        return rect
    }
}

class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    var sidebarPanel: NSPanel!

    let agentStore = AgentStore()
    let providerManager = ProviderManager()
    let chatVM = ChatViewModel()
    let roomManager = RoomManager()
    private var commandBarManager: CommandBarManager?

    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isSidebarVisible = false
    private var isSidebarPinned = false
    private let edgeThreshold: CGFloat = 50
    private let panelWidth: CGFloat = 400
    private var hideTimer: Timer?
    /// 현재 사이드바가 표시 중인 화면
    private weak var currentScreen: NSScreen?
    /// 온보딩 윈도우
    private var onboardingWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // RoomManager 먼저 설정
        roomManager.configure(agentStore: agentStore, providerManager: providerManager)
        roomManager.loadRooms()

        // ChatViewModel에 RoomManager 포함하여 설정
        chatVM.configure(agentStore: agentStore, providerManager: providerManager, roomManager: roomManager)
        chatVM.loadMessages()

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

    /// 사이드바 + 마우스 추적 + 알림 + 커맨드바 시작
    private func startNormalFlow() {
        createSidebarPanel()
        startMouseTracking()
        setupNotifications()
        setupCommandBar()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .sidebarHideRequested, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSidebarPinned = false
                self?.hideSidebar()
            }
        }
        NotificationCenter.default.addObserver(forName: .sidebarPinToggled, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSidebarPinned.toggle()
            }
        }
    }

    private func setupCommandBar() {
        commandBarManager = CommandBarManager(
            agentStore: agentStore,
            providerManager: providerManager,
            chatVM: chatVM,
            openChatWindow: { _ in }
        )
        commandBarManager?.registerHotkey()
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
        window.title = "AgentManager 설정"
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

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
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
            styleMask: [.nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        sidebarPanel.title = "Tell, Don't Ask"
        sidebarPanel.level = .floating
        sidebarPanel.isFloatingPanel = true
        sidebarPanel.hidesOnDeactivate = false
        sidebarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sidebarPanel.isMovableByWindowBackground = false
        sidebarPanel.backgroundColor = .clear
        sidebarPanel.isOpaque = false
        sidebarPanel.titlebarAppearsTransparent = true
        sidebarPanel.titleVisibility = .hidden
        sidebarPanel.hasShadow = false

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

    // MARK: - 마우스 감지

    func startMouseTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            DispatchQueue.main.async { self?.handleMouseMove() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            DispatchQueue.main.async { self?.handleMouseMove() }
            return event
        }
    }

    /// 마우스가 위치한 화면 중 오른쪽 끝에 가까운 화면을 반환
    private func screenAtRightEdge(_ mouseLocation: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            let frame = screen.frame
            guard frame.contains(mouseLocation) else { continue }
            let distFromRight = frame.maxX - mouseLocation.x
            if distFromRight <= edgeThreshold {
                return screen
            }
        }
        return nil
    }

    private func handleMouseMove() {
        let mouseLocation = NSEvent.mouseLocation

        if !isSidebarVisible {
            // 어떤 모니터든 오른쪽 끝에 마우스 → 나타남
            if let screen = screenAtRightEdge(mouseLocation) {
                hideTimer?.invalidate()
                showSidebar(on: screen)
            }
        } else {
            if isSidebarPinned { return }
            let mouseInPanel = sidebarPanel.frame.contains(mouseLocation)
            if mouseInPanel {
                // 패널 안에 있으면 숨김 취소
                hideTimer?.invalidate()
            } else {
                // 다른 모니터의 오른쪽 끝에 마우스가 있으면 → 그 모니터로 이동
                if let newScreen = screenAtRightEdge(mouseLocation),
                   newScreen !== currentScreen {
                    hideSidebar()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                        self?.showSidebar(on: newScreen)
                    }
                    return
                }
                // 패널 밖이면 무조건 숨김 예약 (사각지대 없음)
                scheduleHide()
            }
        }
    }

    private func showSidebar(on screen: NSScreen? = nil) {
        guard !isSidebarVisible else { return }
        guard let screen = screen ?? NSScreen.screens.first else { return }
        isSidebarVisible = true
        currentScreen = screen
        hideTimer?.invalidate()
        sidebarPanel.ignoresMouseEvents = false
        let sf = screen.visibleFrame
        let targetX = sf.maxX - panelWidth
        // 8pt 오른쪽에서 시작 → 원위치로 슬라이드
        sidebarPanel.setFrame(NSRect(x: targetX + 8, y: sf.minY, width: panelWidth, height: sf.height), display: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.sidebarPanel.animator().alphaValue = 1.0
            self.sidebarPanel.animator().setFrame(
                NSRect(x: targetX, y: sf.minY, width: self.panelWidth, height: sf.height),
                display: true
            )
        }
    }

    private func scheduleHide() {
        // 이미 타이머가 돌고 있으면 중복 생성하지 않음
        guard hideTimer == nil || !(hideTimer?.isValid ?? false) else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.hideSidebar() }
        }
    }

    private func hideSidebar() {
        hideTimer?.invalidate()
        hideTimer = nil
        if isSidebarPinned { return }
        if !isSidebarVisible { return }
        if sidebarPanel.frame.contains(NSEvent.mouseLocation) { return }
        // 유틸리티 윈도우가 열려있으면 사이드바 숨기지 않음
        if UtilityWindowManager.shared.hasOpenWindows { return }
        isSidebarVisible = false
        sidebarPanel.ignoresMouseEvents = true
        if let screen = currentScreen ?? NSScreen.screens.first {
            let sf = screen.visibleFrame
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.sidebarPanel.animator().alphaValue = 0.0
                // 8pt 오른쪽으로 밀려나며 사라짐
                self.sidebarPanel.animator().setFrame(
                    NSRect(x: sf.maxX - self.panelWidth + 8, y: sf.minY, width: self.panelWidth, height: sf.height),
                    display: true
                )
            })
        }
        currentScreen = nil
    }

    // MARK: - 수동 토글

    public func toggleSidebar() {
        if isSidebarVisible {
            isSidebarPinned = false
            hideSidebar()
        } else {
            // 마우스가 있는 화면에 표시
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            showSidebar(on: screen)
        }
    }

    public func toggleCommandBar() {
        commandBarManager?.toggle()
    }
}
