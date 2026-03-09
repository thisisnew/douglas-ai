import SwiftUI
import AppKit

/// 폼용 고성능 텍스트 편집기 (NSTextView 기반)
/// SwiftUI TextEditor의 긴 텍스트 성능 문제를 해결
struct FormTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false

        let tc = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true

        let lm = NSLayoutManager()
        lm.allowsNonContiguousLayout = true
        lm.addTextContainer(tc)

        let ts = NSTextStorage()
        ts.addLayoutManager(lm)

        let tv = NSTextView(frame: .zero, textContainer: tc)
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = font
        tv.drawsBackground = false
        tv.string = text
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]

        // 불필요한 텍스트 분석 비활성화 (성능 향상)
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
        context.coordinator.textView = tv
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        guard !coord.isUpdating,
              let tv = coord.textView,
              tv.string != text else { return }
        coord.isUpdating = true
        tv.string = text
        coord.isUpdating = false
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FormTextEditor
        var isUpdating = false
        weak var textView: NSTextView?

        init(_ parent: FormTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = tv.string
            isUpdating = false
        }
    }
}
