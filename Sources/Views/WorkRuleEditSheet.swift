import SwiftUI
import AppKit

/// 업무 규칙 레코드 편집 시트
struct WorkRuleEditSheet: View {
    @Environment(\.colorPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let existingRule: WorkRule?
    let onSave: (WorkRule) -> Void

    @State private var name: String
    @State private var summary: String
    @State private var contentType: ContentType
    @State private var inlineText: String
    @State private var filePath: String
    @State private var isAlwaysActive: Bool

    enum ContentType: String, CaseIterable {
        case inline = "직접 입력"
        case file = "파일 참조"
    }

    init(existingRule: WorkRule? = nil, onSave: @escaping (WorkRule) -> Void) {
        self.existingRule = existingRule
        self.onSave = onSave

        if let rule = existingRule {
            _name = State(initialValue: rule.name)
            _summary = State(initialValue: rule.summary)
            _isAlwaysActive = State(initialValue: rule.isAlwaysActive)
            switch rule.content {
            case .inline(let text):
                _contentType = State(initialValue: .inline)
                _inlineText = State(initialValue: text)
                _filePath = State(initialValue: "")
            case .file(let path):
                _contentType = State(initialValue: .file)
                _inlineText = State(initialValue: "")
                _filePath = State(initialValue: path)
            }
        } else {
            _name = State(initialValue: "")
            _summary = State(initialValue: "")
            _contentType = State(initialValue: .inline)
            _inlineText = State(initialValue: "")
            _filePath = State(initialValue: "")
            _isAlwaysActive = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text(existingRule != nil ? "규칙 수정" : "규칙 추가")
                    .font(.system(size: DesignTokens.FontSize.icon, weight: .semibold, design: .rounded))
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(palette.textSecondary)
                Button("저장") { save() }
                    .buttonStyle(.plain)
                    .foregroundColor(isFormValid ? palette.accent : palette.textSecondary.opacity(0.5))
                    .disabled(!isFormValid)
            }
            .padding()

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 이름
                    VStack(alignment: .leading, spacing: 4) {
                        Text("이름")
                            .font(.system(size: DesignTokens.FontSize.xs, weight: .medium))
                            .foregroundColor(palette.textSecondary)
                        TextField("예: 코딩 규칙", text: $name)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(palette.inputBackground)
                            .continuousRadius(DesignTokens.Radius.md)
                    }

                    // 요약 (매칭에 사용)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("요약")
                            .font(.system(size: DesignTokens.FontSize.xs, weight: .medium))
                            .foregroundColor(palette.textSecondary)
                        Text("태스크 매칭에 사용됩니다. 키워드를 포함하세요.")
                            .font(.system(size: 10))
                            .foregroundColor(palette.textSecondary.opacity(0.7))
                        TextField("예: 코딩, 구현, 개발 시 적용하는 규칙", text: $summary)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(palette.inputBackground)
                            .continuousRadius(DesignTokens.Radius.md)
                    }

                    // 항상 활성
                    Toggle(isOn: $isAlwaysActive) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("항상 활성")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .medium))
                            Text("매칭 여부와 관계없이 항상 포함됩니다")
                                .font(.system(size: 10))
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)

                    // 내용 유형
                    VStack(alignment: .leading, spacing: 4) {
                        Text("내용")
                            .font(.system(size: DesignTokens.FontSize.xs, weight: .medium))
                            .foregroundColor(palette.textSecondary)

                        Picker("", selection: $contentType) {
                            ForEach(ContentType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        if contentType == .inline {
                            FormTextEditor(text: $inlineText, font: .systemFont(ofSize: 13))
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(palette.inputBackground)
                                .continuousRadius(DesignTokens.Radius.md)
                                .overlay(
                                    Group {
                                        if inlineText.isEmpty {
                                            Text("규칙 내용을 입력하세요...")
                                                .font(.body)
                                                .foregroundColor(.secondary.opacity(0.5))
                                                .padding(.leading, 12)
                                                .padding(.top, 16)
                                                .allowsHitTesting(false)
                                        }
                                    },
                                    alignment: .topLeading
                                )
                        } else {
                            HStack {
                                TextField("파일 경로", text: $filePath)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .background(palette.inputBackground)
                                    .continuousRadius(DesignTokens.Radius.md)
                                Button("선택") { pickFile() }
                                    .buttonStyle(.plain)
                                    .foregroundColor(palette.accent)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 450)
        .background(palette.inputBackground)
    }

    private var isFormValid: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasContent: Bool
        switch contentType {
        case .inline:
            hasContent = !inlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            hasContent = !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasName && hasContent
    }

    private func save() {
        let content: WorkRuleContent
        switch contentType {
        case .inline: content = .inline(inlineText)
        case .file: content = .file(filePath)
        }

        let rule = WorkRule(
            id: existingRule?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content,
            isAlwaysActive: isAlwaysActive
        )
        onSave(rule)
        dismiss()
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
        }
    }
}
