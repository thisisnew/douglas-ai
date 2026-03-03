import SwiftUI

// MARK: - 코지 게임 버튼 스타일

/// 3D 눌림 효과가 있는 게임 스타일 버튼
/// `.buttonStyle(CozyButtonStyle(.pink))` 형태로 사용
struct CozyButtonStyle: ButtonStyle {
    @Environment(\.colorPalette) private var palette

    enum Variant {
        case accent, cream, blue, green
    }

    let variant: Variant

    init(_ variant: Variant = .accent) {
        self.variant = variant
    }

    func makeBody(configuration: Configuration) -> some View {
        let colors = resolveColors(palette: palette)
        configuration.label
            .font(.system(size: DesignTokens.FontSize.body, weight: .bold, design: .rounded))
            .foregroundColor(colors.text)
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [colors.top, colors.bottom],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                            .strokeBorder(colors.border.opacity(0.3), lineWidth: 2)
                    )
            )
            .shadow(
                color: colors.shadow.opacity(configuration.isPressed ? 0.1 : 0.25),
                radius: configuration.isPressed ? 1 : 3,
                y: configuration.isPressed ? DesignTokens.CozyGame.buttonPressedY : DesignTokens.CozyGame.buttonShadowY
            )
            .offset(y: configuration.isPressed ? DesignTokens.CozyGame.buttonPressedY : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.dgBounce, value: configuration.isPressed)
    }

    private struct ButtonColors {
        let top: Color, bottom: Color, border: Color, shadow: Color, text: Color
    }

    private func resolveColors(palette: ColorPalette) -> ButtonColors {
        switch variant {
        case .accent:
            return ButtonColors(
                top: palette.accent.opacity(0.85),
                bottom: palette.accent,
                border: palette.accent,
                shadow: palette.buttonShadow,
                text: palette.userBubbleText
            )
        case .cream:
            return ButtonColors(
                top: palette.panelGradientStart,
                bottom: palette.panelGradientEnd,
                border: palette.cardBorder,
                shadow: palette.cardBorder,
                text: palette.textPrimary
            )
        case .blue:
            return ButtonColors(
                top: Color(hex: "DFF0FA"),
                bottom: Color(hex: "A2D5F2"),
                border: Color(hex: "5BA4C9"),
                shadow: Color(hex: "4A8AAA"),
                text: Color(hex: "3A7A9A")
            )
        case .green:
            return ButtonColors(
                top: Color(hex: "E0F5E4"),
                bottom: Color(hex: "8ECF99"),
                border: Color(hex: "5AAD6A"),
                shadow: Color(hex: "4A8A50"),
                text: Color(hex: "3A7A40")
            )
        }
    }
}

// MARK: - 코지 패널 모디파이어

/// 그라데이션 배경 + 소프트 테두리 + 드롭 섀도 패널
struct CozyPanelModifier: ViewModifier {
    @Environment(\.colorPalette) private var palette

    enum Variant {
        case `default`, pink, blue, purple, dark
    }

    let variant: Variant

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.panelRadius, style: .continuous)
                    .fill(gradientForVariant)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CozyGame.panelRadius, style: .continuous)
                            .strokeBorder(borderColor.opacity(0.25), lineWidth: DesignTokens.CozyGame.borderWidth)
                    )
            )
            .shadow(
                color: palette.sidebarShadow,
                radius: DesignTokens.CozyGame.panelShadowRadius,
                y: DesignTokens.CozyGame.panelShadowY
            )
    }

    private var gradientForVariant: LinearGradient {
        switch variant {
        case .default:
            return palette.panelGradient
        case .pink:
            return LinearGradient(
                colors: [Color(hex: "FFF4F7"), Color(hex: "FFE0E8")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .blue:
            return LinearGradient(
                colors: [Color(hex: "F0F8FF"), Color(hex: "D6EEF8")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .purple:
            return LinearGradient(
                colors: [Color(hex: "F8F0FF"), Color(hex: "E8DCF5")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color(hex: "3A3548"), Color(hex: "2E2A3A")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch variant {
        case .default: return palette.cardBorder
        case .pink:    return Color(hex: "FFB8C6")
        case .blue:    return Color(hex: "A2D5F2")
        case .purple:  return Color(hex: "C5A3E0")
        case .dark:    return Color(hex: "4A4558")
        }
    }
}

extension View {
    /// 코지 게임 패널 스타일 적용
    func cozyPanel(_ variant: CozyPanelModifier.Variant = .default) -> some View {
        modifier(CozyPanelModifier(variant: variant))
    }
}

// MARK: - 코지 프로그레스 바

/// 둥근 게임 스타일 프로그레스 바 (그라데이션 fill + 상단 하이라이트)
struct CozyProgressBar: View {
    let progress: Double
    var fillColor: Color = Color(hex: "FF8FAB")
    var fillEndColor: Color?
    var trackColor: Color?

    @Environment(\.colorPalette) private var palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.progressBarRadius, style: .continuous)
                    .fill(trackColor ?? palette.separator.opacity(0.5))

                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.progressBarRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [fillColor, fillEndColor ?? fillColor.opacity(0.8)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(min(progress, 1.0))))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CozyGame.progressBarRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [palette.progressHighlight, .clear],
                                    startPoint: .top, endPoint: .center
                                )
                            )
                            .frame(width: max(0, geo.size.width * CGFloat(min(progress, 1.0))))
                    , alignment: .leading)
            }
        }
        .frame(height: DesignTokens.CozyGame.progressBarHeight)
    }
}

// MARK: - 코지 토글

/// 둥근 pill 모양 토글 스위치
struct CozyToggle: View {
    @Binding var isOn: Bool
    var onColor: Color = Color(hex: "8ECF99")

    @Environment(\.colorPalette) private var palette

    var body: some View {
        Button {
            withAnimation(.dgSpring) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? onColor : palette.separator)
                    .frame(width: 48, height: 28)
                    .overlay(
                        Capsule().strokeBorder(
                            (isOn ? onColor : palette.cardBorder).opacity(0.3),
                            lineWidth: 2
                        )
                    )

                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 코지 체크박스

/// 둥근 사각 체크박스
struct CozyCheckbox: View {
    @Binding var isChecked: Bool
    var label: String = ""
    var checkedColor: Color = Color(hex: "A2D5F2")

    @Environment(\.colorPalette) private var palette

    var body: some View {
        Button {
            withAnimation(.dgBounce) { isChecked.toggle() }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isChecked ? checkedColor : palette.panelGradientStart)
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isChecked ? checkedColor : palette.cardBorder,
                                lineWidth: 2
                            )
                    )
                    .overlay(
                        Group {
                            if isChecked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    )
                    .scaleEffect(isChecked ? 1.0 : 0.95)

                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
