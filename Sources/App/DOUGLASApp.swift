import SwiftUI
import AppKit

@main
struct DOUGLASApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 빈 Settings 씬 (없으면 경고 발생)
        // 상태바 아이콘은 AppDelegate에서 NSStatusItem으로 직접 관리
        Settings {
            EmptyView()
        }
    }
}
