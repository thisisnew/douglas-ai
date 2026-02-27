import AppKit
import SwiftUI

/// 글로벌 커맨드 바 관리: 핫키 등록, 패널 생명주기, show/dismiss 애니메이션
@MainActor
final class CommandBarManager {
    private var panel: CommandBarPanel?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?
    private var isVisible = false

    private let agentStore: AgentStore
    private let providerManager: ProviderManager
    private let chatVM: ChatViewModel
    private let openChatWindow: (Agent) -> Void

    init(
        agentStore: AgentStore,
        providerManager: ProviderManager,
        chatVM: ChatViewModel,
        openChatWindow: @escaping (Agent) -> Void
    ) {
        self.agentStore = agentStore
        self.providerManager = providerManager
        self.chatVM = chatVM
        self.openChatWindow = openChatWindow
    }

    // MARK: - 핫키 등록

    func registerHotkey() {
        // Cmd+Shift+A — 글로벌 (앱 비활성 시)
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isCommandBarHotkey(event) {
                DispatchQueue.main.async { self?.toggle() }
            }
        }

        // 로컬 (앱 활성 시)
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isCommandBarHotkey(event) {
                DispatchQueue.main.async { self?.toggle() }
                return nil // 이벤트 소비
            }
            return event
        }
    }

    private static func isCommandBarHotkey(_ event: NSEvent) -> Bool {
        // keyCode 0x00 = 'a'
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 0x00 && flags == [.command, .shift]
    }

    // MARK: - 토글

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    // MARK: - 표시

    func show() {
        createPanelIfNeeded()
        guard let panel else { return }
        guard !isVisible else { return }

        isVisible = true

        // 화면 중앙 상단에 배치
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let panelWidth: CGFloat = 600
            let panelHeight: CGFloat = 360
            let x = sf.midX - panelWidth / 2
            let y = sf.midY + sf.height * 0.1
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        panel.alphaValue = 0
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
    }

    // MARK: - 닫기

    func dismiss() {
        guard let panel, isVisible else { return }
        isVisible = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }) { [weak panel] in
            panel?.orderOut(nil)
        }
    }

    // MARK: - 패널 생성

    private func createPanelIfNeeded() {
        guard panel == nil else { return }

        let p = CommandBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 360),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.hasShadow = true
        p.isOpaque = false

        // 외부 클릭 시 닫기
        p.onResignKey = { [weak self] in
            DispatchQueue.main.async { self?.dismiss() }
        }

        let commandBarView = CommandBarView(
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onOpenFullChat: { [weak self] agent in
                self?.openChatWindow(agent)
            }
        )
        .environmentObject(agentStore)
        .environmentObject(providerManager)
        .environmentObject(chatVM)

        p.contentView = NSHostingView(rootView: commandBarView)
        panel = p
    }

    deinit {
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
