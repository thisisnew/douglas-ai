import SwiftUI
import AppKit

/// 폼용 고성능 텍스트 편집기 (NSTextView 기반)
/// SwiftUI TextEditor의 긴 텍스트 성능 문제를 해결
struct FormTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Container {
        let container = Container(coordinator: context.coordinator, font: font, initialText: text)
        return container
    }

    func updateNSView(_ container: Container, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        let tv = container.textView
        guard !coord.isUpdating, tv.string != text else { return }
        coord.isUpdating = true
        tv.string = text
        coord.isUpdating = false
    }

    // MARK: - Container (NSView + NSScrollView + NSTextView)

    final class Container: NSView {
        let scrollView: NSScrollView
        let textView: NSTextView

        init(coordinator: Coordinator, font: NSFont, initialText: String) {
            let sv = NSScrollView()
            sv.hasVerticalScroller = true
            sv.autohidesScrollers = true
            sv.borderType = .noBorder
            sv.drawsBackground = false
            sv.translatesAutoresizingMaskIntoConstraints = false

            let tc = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            tc.widthTracksTextView = true

            let lm = NSLayoutManager()
            lm.allowsNonContiguousLayout = true
            lm.addTextContainer(tc)

            let ts = NSTextStorage()
            ts.addLayoutManager(lm)

            let tv = NSTextView(frame: .zero, textContainer: tc)
            tv.delegate = coordinator
            tv.isRichText = false
            tv.font = font
            tv.textColor = .labelColor
            tv.insertionPointColor = .labelColor
            tv.drawsBackground = false
            tv.string = initialText
            tv.textContainerInset = NSSize(width: 2, height: 4)
            tv.isVerticallyResizable = true
            tv.isHorizontallyResizable = false
            tv.autoresizingMask = [.width]
            tv.minSize = NSSize(width: 0, height: 0)
            tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            // 불필요한 텍스트 분석 비활성화
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isContinuousSpellCheckingEnabled = false
            tv.isGrammarCheckingEnabled = false
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticLinkDetectionEnabled = false
            tv.isAutomaticDataDetectionEnabled = false
            tv.isAutomaticTextCompletionEnabled = false

            sv.documentView = tv

            self.scrollView = sv
            self.textView = tv

            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false

            addSubview(sv)
            NSLayoutConstraint.activate([
                sv.topAnchor.constraint(equalTo: topAnchor),
                sv.bottomAnchor.constraint(equalTo: bottomAnchor),
                sv.leadingAnchor.constraint(equalTo: leadingAnchor),
                sv.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            let clipWidth = scrollView.contentView.bounds.width
            if clipWidth > 0, abs(textView.frame.width - clipWidth) > 1 {
                textView.frame.size.width = clipWidth
                textView.textContainer?.containerSize.width = clipWidth
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FormTextEditor
        var isUpdating = false

        init(_ parent: FormTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = tv.string
            isUpdating = false
        }
    }
}
