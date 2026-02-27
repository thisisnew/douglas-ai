import AppKit
import SwiftUI

extension Notification.Name {
    static let sidebarHideRequested = Notification.Name("sidebarHideRequested")
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
    private var statusItem: NSStatusItem?
    private var sidebarHotkeyMonitor: Any?
    private var sidebarGlobalMonitor: Any?

    private var isSidebarVisible = false
    private let panelWidth: CGFloat = 400
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

    /// 사이드바 + 알림 + 상태바 아이콘 시작
    private func startNormalFlow() {
        createSidebarPanel()
        setupNotifications()
        setupStatusItem()
        registerSidebarHotkey()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .sidebarHideRequested, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.hideSidebar()
            }
        }
    }

    // MARK: - 상태바 아이콘 (클릭 → 사이드바 토글)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "DOUGLAS")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusMenu()
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
                DispatchQueue.main.async { self?.toggleSidebar() }
            }
        }
        sidebarHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isSidebarHotkey(event) {
                DispatchQueue.main.async { self?.toggleSidebar() }
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

    // MARK: - 사이드바 Show / Hide

    private func showSidebar(on screen: NSScreen? = nil) {
        guard !isSidebarVisible else { return }
        guard let screen = screen ?? NSScreen.screens.first else { return }
        isSidebarVisible = true
        currentScreen = screen
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

    private func hideSidebar() {
        guard isSidebarVisible else { return }
        isSidebarVisible = false
        sidebarPanel.ignoresMouseEvents = true
        if let screen = currentScreen ?? NSScreen.screens.first {
            let sf = screen.visibleFrame
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.sidebarPanel.animator().alphaValue = 0.0
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
            hideSidebar()
        } else {
            // 마우스가 있는 화면에 표시
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            showSidebar(on: screen)
        }
    }

}
