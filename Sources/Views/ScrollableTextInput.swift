import SwiftUI
import AppKit

/// 마우스 휠 스크롤을 지원하는 텍스트 입력 (NSTextView 기반)
/// SwiftUI TextField(axis: .vertical)은 lineLimit 초과 시 마우스 휠 스크롤이 안 되는 문제를 해결
struct ScrollableTextInput: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .systemFont(ofSize: 13)
    var maxHeight: CGFloat = 80
    var onSubmit: (() -> Void)? = nil
    /// 특수 키 처리 (mention autocomplete 등). true 반환 시 이벤트 소비.
    var onSpecialKey: ((SpecialKey) -> Bool)? = nil

    enum SpecialKey {
        case upArrow, downArrow, tab, escape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let container = _Container(coordinator: context.coordinator)
        context.coordinator.container = container
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? _Container else { return }
        let tv = container.textView
        let coord = context.coordinator
        coord.parent = self

        // 외부 text 변경 반영
        if !coord.isUpdating && tv.string != text {
            coord.isUpdating = true
            tv.string = text
            coord.isUpdating = false
            container.updatePlaceholder()
            container.recalcHeight()
        }

        tv.font = font
    }

    // MARK: - Container (NSScrollView + NSTextView + placeholder)

    final class _Container: NSView {
        let scrollView: NSScrollView
        let textView: NSTextView
        private let placeholderField: NSTextField
        private let coordinator: Coordinator
        private var heightConstraint: NSLayoutConstraint?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator

            // ScrollView
            let sv = NSScrollView()
            sv.hasVerticalScroller = true
            sv.autohidesScrollers = true
            sv.borderType = .noBorder
            sv.drawsBackground = false
            sv.translatesAutoresizingMaskIntoConstraints = false

            // TextView
            let tv = NSTextView()
            tv.delegate = coordinator
            tv.isRichText = false
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 0, height: 1)
            tv.textContainer?.lineFragmentPadding = 2
            tv.isVerticallyResizable = true
            tv.isHorizontallyResizable = false
            tv.textContainer?.widthTracksTextView = true
            tv.autoresizingMask = [.width]
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

            let hc = heightAnchor.constraint(equalToConstant: lineHeight)
            hc.priority = .defaultHigh
            hc.isActive = true
            self.heightConstraint = hc
        }

        required init?(coder: NSCoder) { fatalError() }

        private var lineHeight: CGFloat {
            let fh = textView.font?.boundingRectForFont.height ?? 16
            return fh + textView.textContainerInset.height * 2
        }

        func recalcHeight() {
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
            let content = usedRect.height + textView.textContainerInset.height * 2
            let target = max(content, lineHeight)
            let clamped = min(target, coordinator.parent.maxHeight)
            guard heightConstraint?.constant != clamped else { return }
            heightConstraint?.constant = clamped
            invalidateIntrinsicContentSize()
        }

        func updatePlaceholder() {
            placeholderField.isHidden = !textView.string.isEmpty
            placeholderField.stringValue = coordinator.parent.placeholder
            placeholderField.font = coordinator.parent.font
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: heightConstraint?.constant ?? lineHeight)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScrollableTextInput
        var isUpdating = false
        weak var container: _Container?

        init(_ parent: ScrollableTextInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = tv.string
            isUpdating = false
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
                    onSubmit()
                    return true
                }
                return false
            }

            // 특수 키 (mention autocomplete 등)
            if let handler = parent.onSpecialKey {
                let key: SpecialKey?
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
