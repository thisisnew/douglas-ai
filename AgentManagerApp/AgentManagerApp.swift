import SwiftUI
import AppKit
import AgentManagerLib

@main
struct AgentManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 메뉴바에 토글 버튼 제공
        MenuBarExtra("Tell, Don't Ask", systemImage: "paperplane.fill") {
            Button("사이드바") {
                appDelegate.toggleSidebar()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("커맨드 바 열기") {
                appDelegate.toggleCommandBar()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()

            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        // 빈 Settings 씬 (없으면 경고 발생)
        Settings {
            EmptyView()
        }
    }
}
