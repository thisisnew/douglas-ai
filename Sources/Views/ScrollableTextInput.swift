import SwiftUI
import AppKit

/// 마우스 휠 스크롤을 지원하는 텍스트 입력 (NSTextView 기반)
/// SwiftUI TextField(axis: .vertical)은 lineLimit 초과 시 마우스 휠 스크롤이 안 되는 문제를 해결
struct ScrollableTextInput: View {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .systemFont(ofSize: 13)
    var maxHeight: CGFloat = 80
    var onSubmit: (() -> Void)? = nil
    /// 특수 키 처리 (mention autocomplete 등). true 반환 시 이벤트 소비.
    var onSpecialKey: ((SpecialKey) -> Bool)? = nil
    /// 외부에서 NSTextView → SwiftUI 바인딩 동기화를 트리거하기 위한 핸들
    var accessor: Accessor? = nil

    enum SpecialKey {
        case upArrow, downArrow, tab, escape
    }

    /// 외부에서 텍스트 동기화를 트리거하는 핸들 (전송 버튼 등)
    final class Accessor {
        fileprivate var syncAction: (() -> Void)?
        /// NSTextView의 현재 텍스트를 SwiftUI 바인딩에 즉시 동기화
        func sync() { syncAction?() }
    }

    @State private var dynamicHeight: CGFloat = 20

    var body: some View {
        _Representable(
            text: $text,
            placeholder: placeholder,
            font: font,
            maxHeight: maxHeight,
            dynamicHeight: $dynamicHeight,
            onSubmit: onSubmit,
            onSpecialKey: onSpecialKey,
            accessor: accessor
        )
        .frame(height: dynamicHeight)
    }
}

// MARK: - NSViewRepresentable 구현

private struct _Representable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont
    var maxHeight: CGFloat
    @Binding var dynamicHeight: CGFloat
    var onSubmit: (() -> Void)?
    var onSpecialKey: ((ScrollableTextInput.SpecialKey) -> Bool)?
    var accessor: ScrollableTextInput.Accessor?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> _Container {
        let container = _Container(coordinator: context.coordinator)
        context.coordinator.container = container

        // Accessor에 sync 클로저 연결
        let coord = context.coordinator
        accessor?.syncAction = { [weak coord] in
            coord?.syncText()
        }

        // 초기 높이 설정
        DispatchQueue.main.async {
            dynamicHeight = container.lineHeight
        }

        return container
    }

    func updateNSView(_ container: _Container, context: Context) {
        let tv = container.textView
        let coord = context.coordinator
        coord.parent = self

        // Accessor sync 클로저 갱신 (coordinator 참조 유지)
        accessor?.syncAction = { [weak coord] in
            coord?.syncText()
        }

        // 외부 text 변경 반영 (전송 후 text="" 등)
        if !coord.isUpdating && tv.string != text {
            coord.isUpdating = true
            tv.string = text
            coord.isUpdating = false
            container.updatePlaceholder()
            container.recalcHeight()
        }

        // font가 변경된 경우에만 설정 (불필요한 레이아웃 재계산 방지)
        if tv.font != font {
            tv.font = font
        }
    }

    // MARK: - SwiftUI 스크롤 이벤트 가로채기 방지 NSScrollView

    final class _ScrollView: NSScrollView {
        override func scrollWheel(with event: NSEvent) {
            if let docView = documentView, docView.frame.height > contentView.bounds.height {
                super.scrollWheel(with: event)
            }
            // 스크롤할 내용이 없으면 이벤트를 SwiftUI로 전파하지 않음
        }
    }

    // MARK: - Container (NSScrollView + NSTextView + placeholder)

    final class _Container: NSView {
        let scrollView: _ScrollView
        let textView: NSTextView
        private let placeholderField: NSTextField
        let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator

            // ScrollView
            let sv = _ScrollView()
            sv.hasVerticalScroller = true
            sv.autohidesScrollers = true
            sv.borderType = .noBorder
            sv.drawsBackground = false
            sv.translatesAutoresizingMaskIntoConstraints = false

            // TextContainer → LayoutManager → TextStorage → TextView (수동 정밀 설정)
            let tc = NSTextContainer(containerSize: NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
            tc.widthTracksTextView = true

            let lm = NSLayoutManager()
            lm.addTextContainer(tc)

            let ts = NSTextStorage()
            ts.addLayoutManager(lm)

            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20), textContainer: tc)
            tv.minSize = NSSize(width: 0, height: 20)
            tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.isVerticallyResizable = true
            tv.isHorizontallyResizable = false
            tv.autoresizingMask = [.width]

            tv.delegate = coordinator
            tv.isRichText = false
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isContinuousSpellCheckingEnabled = false
            tv.isGrammarCheckingEnabled = false
            tv.isAutomaticLinkDetectionEnabled = false
            tv.isAutomaticDataDetectionEnabled = false
            tv.isAutomaticTextCompletionEnabled = false
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 0, height: 1)
            tc.lineFragmentPadding = 2
            tv.font = coordinator.parent.font

            sv.documentView = tv

            // Placeholder
            let ph = NSTextField(labelWithString: coordinator.parent.placeholder)
            ph.font = coordinator.parent.font
            ph.textColor = .placeholderTextColor
            ph.isEditable = false
            ph.isSelectable = false
            ph.drawsBackground = false
            ph.isBordered = false
            ph.translatesAutoresizingMaskIntoConstraints = false

            self.scrollView = sv
            self.textView = tv
            self.placeholderField = ph

            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false

            addSubview(sv)
            addSubview(ph)

            NSLayoutConstraint.activate([
                sv.topAnchor.constraint(equalTo: topAnchor),
                sv.bottomAnchor.constraint(equalTo: bottomAnchor),
                sv.leadingAnchor.constraint(equalTo: leadingAnchor),
                sv.trailingAnchor.constraint(equalTo: trailingAnchor),
                ph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                ph.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            ])
        }

        required init?(coder: NSCoder) { fatalError() }

        var lineHeight: CGFloat {
            let fh = textView.font?.boundingRectForFont.height ?? 16
            return fh + textView.textContainerInset.height * 2
        }

        func recalcHeight() {
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
            let content = usedRect.height + textView.textContainerInset.height * 2
            let target = max(content, lineHeight)
            let clamped = min(target, coordinator.parent.maxHeight)

            // 값이 동일하면 SwiftUI 재렌더 방지
            guard abs(coordinator.parent.dynamicHeight - clamped) > 0.5 else { return }

            // SwiftUI에 높이 변경 전달
            DispatchQueue.main.async { [weak self] in
                self?.coordinator.parent.dynamicHeight = clamped
            }
        }

        func updatePlaceholder() {
            placeholderField.isHidden = !textView.string.isEmpty
            placeholderField.stringValue = coordinator.parent.placeholder
            placeholderField.font = coordinator.parent.font
        }

        /// placeholder가 마우스 이벤트를 가로채지 않도록 hitTest 재정의
        override func hitTest(_ point: NSPoint) -> NSView? {
            // scrollView(textView) 영역이면 scrollView로 전달
            let converted = convert(point, to: scrollView)
            if let hit = scrollView.hitTest(converted) { return hit }
            return super.hitTest(point)
        }

        /// SwiftUI가 스크롤 이벤트를 가로채지 않도록 NSScrollView로 직접 전달
        override func scrollWheel(with event: NSEvent) {
            scrollView.scrollWheel(with: event)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: _Representable
        var isUpdating = false
        weak var container: _Container?
        /// 이전 텍스트 길이 (붙여넣기/드롭 감지용)
        private var previousLength = 0

        init(_ parent: _Representable) {
            self.parent = parent
        }

        /// NSTextView → SwiftUI 바인딩 즉시 동기화
        func syncText() {
            guard let tv = container?.textView, !isUpdating else { return }
            isUpdating = true
            parent.text = tv.string
            isUpdating = false
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }

            let newText = tv.string
            let lengthDelta = abs(newText.count - previousLength)
            previousLength = newText.count

            // 즉시 동기화가 필요한 경우만:
            // - "/" 시작: 슬래시 명령 자동완성 트리거
            // - 길이 급변(>3): 붙여넣기/드롭 → onChange 파일경로 감지 필요
            // - 텍스트 비움: placeholder 등 UI 상태 반영
            // 일반 타이핑은 전송 시점(syncText)까지 SwiftUI 바인딩을 건드리지 않음
            if newText.hasPrefix("/") || lengthDelta > 3 || newText.isEmpty {
                isUpdating = true
                parent.text = newText
                isUpdating = false
            }

            container?.updatePlaceholder()
            container?.recalcHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            // Enter → submit (Shift/Option+Enter → 줄바꿈)
            if sel == #selector(NSResponder.insertNewline(_:)) {
                let mods = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
                if mods.contains(.shift) || mods.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                if let onSubmit = parent.onSubmit {
                    syncText()  // submit 직전 바인딩 동기화
                    onSubmit()
                    return true
                }
                return false
            }

            // 특수 키 (mention autocomplete 등)
            if let handler = parent.onSpecialKey {
                let key: ScrollableTextInput.SpecialKey?
                switch sel {
                case #selector(NSResponder.moveUp(_:)):       key = .upArrow
                case #selector(NSResponder.moveDown(_:)):     key = .downArrow
                case #selector(NSResponder.insertTab(_:)):    key = .tab
                case #selector(NSResponder.cancelOperation(_:)): key = .escape
                default: key = nil
                }
                if let key, handler(key) {
                    return true
                }
            }

            return false
        }
    }
}
