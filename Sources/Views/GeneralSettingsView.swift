import SwiftUI
import AppKit

/// 일반 설정 — 문서 저장 경로, 업데이트 등
struct GeneralSettingsView: View {
    var isEmbedded = false

    @Environment(\.colorPalette) private var palette
    @EnvironmentObject private var updateManager: UpdateManager
    @State private var documentSavePath: String = UserDefaults.standard.string(forKey: "documentSaveDirectory") ?? ""
    @State private var showingUpdateAlert = false
    @State private var showNoUpdateToast = false

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

                // 소프트웨어 업데이트
                updateSection
            }
            .padding(isEmbedded ? 24 : 16)
        }
        .frame(maxWidth: isEmbedded ? .infinity : nil, maxHeight: isEmbedded ? .infinity : nil)
        .sheet(isPresented: $showingUpdateAlert) {
            UpdateAlertView(onDismiss: { showingUpdateAlert = false })
                .environmentObject(updateManager)
        }
        .overlay(alignment: .top) {
            if showNoUpdateToast {
                noUpdateToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showNoUpdateToast = false }
                        }
                    }
            }
        }
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

        // Security Bookmark 저장 (앱 재시작 후에도 폴더 접근 권한 유지)
        if let bookmarkData = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmarkData, forKey: "documentSaveDirectoryBookmark")
        }
    }

    // MARK: - 소프트웨어 업데이트

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("소프트웨어 업데이트", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Toggle("앱 시작 시 자동으로 업데이트 확인", isOn: $updateManager.autoCheckEnabled)
                .font(.system(size: 12))
                .foregroundColor(palette.textPrimary)
                .toggleStyle(.switch)
                .controlSize(.small)

            HStack(spacing: 8) {
                Button {
                    Task {
                        try? await updateManager.checkForUpdate()
                        if updateManager.isUpdateAvailable {
                            showingUpdateAlert = true
                        } else if updateManager.lastError == nil {
                            withAnimation { showNoUpdateToast = true }
                        }
                    }
                } label: {
                    if updateManager.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("지금 확인", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(updateManager.isChecking)

                if let error = updateManager.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Text("현재 버전: \(updateManager.appVersion)")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
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

    private var noUpdateToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("최신 버전입니다")
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(palette.background)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .padding(.top, 8)
    }
}
