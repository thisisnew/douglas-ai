import SwiftUI
import MarkdownUI

/// 업데이트 알림 시트
struct UpdateAlertView: View {
    @EnvironmentObject private var updateManager: UpdateManager
    @Environment(\.colorPalette) private var palette

    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            header
                .padding(20)

            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, palette.separator.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 1)

            // 릴리스 노트
            releaseNotesSection

            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, palette.separator.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 1)

            // 버튼
            buttonBar
                .padding(16)
        }
        .frame(width: 480, height: 420)
        .background(palette.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.accent, palette.accent.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("새로운 버전이 있습니다")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.textPrimary)

                if let release = updateManager.latestVersion {
                    HStack(spacing: 8) {
                        Text("현재: \(updateManager.appVersion)")
                            .foregroundColor(palette.textSecondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(palette.textSecondary)
                        Text("최신: \(release.version)")
                            .foregroundColor(palette.accent)
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 13))
                }
            }

            Spacer()
        }
    }

    // MARK: - Release Notes

    private var releaseNotesSection: some View {
        ScrollView {
            if let release = updateManager.latestVersion {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(release.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.textPrimary)

                        Spacer()

                        Text(release.publishedAt, style: .date)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(palette.textSecondary.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(palette.surfaceSecondary.opacity(0.5), in: Capsule())
                    }

                    Markdown(release.releaseNotes)
                        .markdownTextStyle {
                            ForegroundColor(palette.textPrimary)
                            FontSize(13)
                        }
                        .markdownTextStyle(\.code) {
                            FontFamilyVariant(.monospaced)
                            FontSize(12)
                            ForegroundColor(palette.accent)
                        }
                }
                .padding(20)
            } else {
                Text("릴리스 노트를 불러올 수 없습니다.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(palette.textSecondary)
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.surfaceSecondary.opacity(0.15))
    }

    // MARK: - Buttons

    private var buttonBar: some View {
        HStack(spacing: 12) {
            Button {
                if let release = updateManager.latestVersion {
                    updateManager.skipVersion(release.version)
                }
                onDismiss()
            } label: {
                Text("이 버전 건너뛰기")
                    .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundColor(palette.textSecondary.opacity(0.6))

            Spacer()

            Button(action: onDismiss) {
                Text("나중에")
                    .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(palette.surfaceSecondary.opacity(0.6), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                updateManager.openDownloadPage()
                onDismiss()
            } label: {
                Label("다운로드", systemImage: "arrow.down.to.line")
                    .font(.system(size: DesignTokens.FontSize.xs, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
