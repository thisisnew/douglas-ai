import SwiftUI

// MARK: - 시트 네비게이션 헤더

/// 시트 상단 공통 헤더 (취소/제목/액션)
struct SheetNavHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: DesignTokens.FontSize.bodyMd, weight: .bold, design: .rounded))
                HStack {
                    leading()
                    Spacer()
                    trailing()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.primary.opacity(0.06), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }
}

// MARK: - 카드 컨테이너

/// RoomChatView 내 카드 공통 래퍼 (배경 + cornerRadius + 패딩)
struct CardContainer<Content: View>: View {
    @Environment(\.colorPalette) private var palette
    var accentColor: Color = .primary
    var opacity: Double = DesignTokens.Opacity.subtle
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(DesignTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                    .fill(palette.panelGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                            .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1.5)
                    )
            )
            .shadow(color: palette.sidebarShadow, radius: 6, y: 3)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

// MARK: - 첨부 파일 썸네일

/// 48x48 파일 미리보기 + 삭제 버튼 (이미지: 썸네일, 문서: 아이콘+파일명)
struct AttachmentThumbnail: View {
    @Environment(\.colorPalette) private var palette
    let attachment: FileAttachment
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if attachment.isImage {
                imagePreview
            } else {
                documentPreview
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .background(Circle().fill(palette.thumbnailDelete))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let data = try? attachment.loadData(), let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .continuousRadius(DesignTokens.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.12), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "photo").foregroundColor(.secondary.opacity(0.5)))
        }
    }

    private var documentPreview: some View {
        VStack(spacing: 2) {
            Image(systemName: attachment.fileIcon)
                .font(.system(size: 16))
                .foregroundColor(palette.accent)
            Text(attachment.displayName)
                .font(.system(size: 8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(width: 56, height: 48)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(palette.inputBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - 전송 버튼

/// arrow.up.circle.fill 전송 버튼
struct SendButton: View {
    @Environment(\.colorPalette) private var palette
    let canSend: Bool
    let isLoading: Bool
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(canSend
                        ? LinearGradient(colors: [palette.accent.opacity(0.85), palette.accent],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [palette.stepInactive.opacity(0.5), palette.stepInactive.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 30)

                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(canSend ? .white : .secondary.opacity(0.4))
            }
            .shadow(
                color: canSend ? palette.buttonShadow.opacity(0.25) : .clear,
                radius: 3, y: 2
            )
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(!canSend || isLoading)
        .keyboardShortcut(.return, modifiers: .command)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - 섹션 라벨

/// 시트 폼 내 섹션 제목
func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(.subheadline, design: .rounded).weight(.bold))
        .foregroundColor(.secondary)
}

/// 시트 폼 내 섹션 제목 + 필수/선택 표시
func sectionLabel(_ text: String, required: Bool) -> some View {
    HStack(spacing: 4) {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundColor(.secondary)
        if required {
            Text("*")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.red.opacity(0.7))
        } else {
            Text("(선택)")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
}

// MARK: - 설정 행

/// 시트 내 레이블 + 컨텐츠 행
struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
