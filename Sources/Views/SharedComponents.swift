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
                Text(title).font(.headline)
                HStack {
                    leading()
                    Spacer()
                    trailing()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
        }
    }
}

// MARK: - 카드 컨테이너

/// RoomChatView 내 카드 공통 래퍼 (배경 + cornerRadius + 패딩)
struct CardContainer<Content: View>: View {
    var accentColor: Color = .primary
    var opacity: Double = DesignTokens.Opacity.subtle
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(DesignTokens.Spacing.md)
            .background(accentColor.opacity(opacity))
            .continuousRadius(DesignTokens.Radius.xl)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

// MARK: - 첨부 이미지 썸네일

/// 48x48 이미지 미리보기 + 삭제 버튼
struct AttachmentThumbnail: View {
    let attachment: ImageAttachment
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let data = try? attachment.loadData(), let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .continuousRadius(DesignTokens.Radius.md)
            } else {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: DesignTokens.FontSize.icon))
                    .foregroundColor(.white)
                    .background(Circle().fill(DesignTokens.Colors.thumbnailDelete))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }
}

// MARK: - 전송 버튼

/// arrow.up.circle.fill 전송 버튼
struct SendButton: View {
    let canSend: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor(canSend ? .accentColor : .gray)
        }
        .buttonStyle(.plain)
        .disabled(!canSend || isLoading)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

// MARK: - 섹션 라벨

/// 시트 폼 내 섹션 제목
func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.subheadline.weight(.medium))
        .foregroundColor(.secondary)
}

/// 시트 폼 내 섹션 제목 + 필수/선택 표시
func sectionLabel(_ text: String, required: Bool) -> some View {
    HStack(spacing: 4) {
        Text(text)
            .font(.subheadline.weight(.medium))
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
