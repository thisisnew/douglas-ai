import AppKit

/// Spotlight 스타일 커맨드 바용 NSPanel
/// 화면 상단 중앙에 떠서 마스터 에이전트에게 빠르게 질문할 수 있다.
class CommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    var onResignKey: (() -> Void)?

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
