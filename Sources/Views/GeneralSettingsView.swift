import SwiftUI
import AppKit

/// 일반 설정 — 문서 저장 경로 등
struct GeneralSettingsView: View {
    var isEmbedded = false

    @Environment(\.colorPalette) private var palette
    @State private var documentSavePath: String = UserDefaults.standard.string(forKey: "documentSaveDirectory") ?? ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !isEmbedded {
                    Text("일반")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                }

                // 문서 저장 경로
                documentSaveSection
            }
            .padding(isEmbedded ? 24 : 16)
        }
        .frame(maxWidth: isEmbedded ? .infinity : nil, maxHeight: isEmbedded ? .infinity : nil)
    }

    // MARK: - 문서 저장 경로

    private var documentSaveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("문서 저장 폴더", systemImage: "folder.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Text("문서 내보내기 시 이 폴더에 자동 저장됩니다. 미설정 시 저장 위치를 매번 묻습니다.")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)

            HStack(spacing: 8) {
                // 경로 표시
                HStack(spacing: 6) {
                    Image(systemName: documentSavePath.isEmpty ? "questionmark.folder" : "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(documentSavePath.isEmpty ? palette.textSecondary.opacity(0.5) : palette.accent)

                    Text(displayPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(documentSavePath.isEmpty ? palette.textSecondary.opacity(0.5) : palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                )

                // 폴더 선택 버튼
                Button {
                    pickFolder()
                } label: {
                    Label("선택", systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                // 초기화 버튼
                if !documentSavePath.isEmpty {
                    Button {
                        documentSavePath = ""
                        UserDefaults.standard.removeObject(forKey: "documentSaveDirectory")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(palette.textSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("저장 경로 초기화 (매번 위치 묻기)")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surfaceSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
        )
    }

    private var displayPath: String {
        if documentSavePath.isEmpty { return "미설정" }
        // ~/... 형태로 축약
        let home = NSHomeDirectory()
        if documentSavePath.hasPrefix(home) {
            return "~" + documentSavePath.dropFirst(home.count)
        }
        return documentSavePath
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "문서를 저장할 기본 폴더를 선택하세요"
        panel.prompt = "선택"

        if !documentSavePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: documentSavePath)
        } else if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = docsURL
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        documentSavePath = url.path
        UserDefaults.standard.set(url.path, forKey: "documentSaveDirectory")
    }
}
