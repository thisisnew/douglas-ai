import SwiftUI

/// DOUGLAS 테마 시스템의 색상 팔레트
/// 모든 시맨틱 색상을 정의하며, 테마별로 교체 가능
struct ColorPalette: Equatable {

    // MARK: - Surface 색상

    /// 윈도우/시트 메인 배경
    let background: Color
    /// 입력 필드, TextEditor 배경
    let inputBackground: Color
    /// 카드/그룹 배경
    let surfaceSecondary: Color
    /// 약한 카드 배경
    let surfaceTertiary: Color
    /// 호버 상태 배경
    let hoverBackground: Color
    /// 활성 행 배경
    let activeRowBackground: Color
    /// 시스템 메시지 배경
    let systemMessageBackground: Color
    /// 기본 메시지 버블 배경
    let messageBubbleBackground: Color
    /// 아바타 폴백 배경
    let avatarFallback: Color
    /// 슬래시 메뉴/퀵인풋 배경
    let overlay: Color
    /// 구분선
    let separator: Color
    /// 닫기/xmark 버튼 배경
    let closeButton: Color
    /// 썸네일 삭제 버튼 배경
    let thumbnailDelete: Color
    /// 스텝 인디케이터 비활성
    let stepInactive: Color

    // MARK: - 액센트 & 사용자 버블

    /// 주요 강조 색상 (버튼, 링크 등)
    let accent: Color
    /// 사용자 메시지 버블 배경
    let userBubble: Color
    /// 사용자 메시지 버블 텍스트
    let userBubbleText: Color

    // MARK: - 텍스트

    /// 주요 텍스트
    let textPrimary: Color
    /// 보조 텍스트
    let textSecondary: Color

    // MARK: - 에이전트 상태 색상

    let statusIdle: Color
    let statusWorking: Color
    let statusBusy: Color
    let statusError: Color

    // MARK: - 방 상태 색상

    let roomPlanning: Color
    let roomInProgress: Color
    let roomAwaitingApproval: Color
    let roomAwaitingUserInput: Color
    let roomCompleted: Color
    let roomFailed: Color

    // MARK: - 메시지 타입 색상

    let messageError: Color
    let messageSummary: Color
    let messageChainProgress: Color
    let messageDelegation: Color
    let messageSuggestion: Color
    let messageToolActivity: Color
    let messageBuildStatus: Color
    let messageQaStatus: Color
    let messageApprovalRequest: Color
    let messageProgress: Color
    let messageDefault: Color

    // MARK: - 사이드바

    let sidebarBackground: Color
    let sidebarShadow: Color

    // MARK: - 코지 게임 UI (그라데이션 & 장식)

    /// 패널 그라데이션 시작 색상
    let panelGradientStart: Color
    /// 패널 그라데이션 끝 색상
    let panelGradientEnd: Color
    /// 버튼 하단 그림자 색상
    let buttonShadow: Color
    /// 카드/패널 테두리 색상
    let cardBorder: Color
    /// 프로그레스 바 하이라이트 색상
    let progressHighlight: Color
    /// 아바타 테두리 색상
    let avatarBorder: Color
}

// MARK: - 그라데이션 편의 프로퍼티

extension ColorPalette {
    /// 패널 배경용 LinearGradient
    var panelGradient: LinearGradient {
        LinearGradient(
            colors: [panelGradientStart, panelGradientEnd],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - 커스텀 팔레트 생성

extension ColorPalette {
    /// 액센트 컬러 하나로 전체 팔레트를 자동 생성
    static func custom(accent: Color) -> ColorPalette {
        let nsColor = NSColor(accent)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        // 매우 연한 버전 (배경용)
        let veryLight = Color(hue: Double(h), saturation: Double(s) * 0.08, brightness: 0.98)
        let light = Color(hue: Double(h), saturation: Double(s) * 0.12, brightness: 0.96)
        let medium = Color(hue: Double(h), saturation: Double(s) * 0.15, brightness: 0.94)
        let mid = Color(hue: Double(h), saturation: Double(s) * 0.20, brightness: 0.92)

        return ColorPalette(
            background: veryLight,
            inputBackground: light,
            surfaceSecondary: light,
            surfaceTertiary: veryLight,
            hoverBackground: medium,
            activeRowBackground: light,
            systemMessageBackground: veryLight,
            messageBubbleBackground: light,
            avatarFallback: medium,
            overlay: mid,
            separator: mid,
            closeButton: medium,
            thumbnailDelete: Color.black.opacity(0.4),
            stepInactive: mid,
            accent: accent,
            userBubble: accent,
            userBubbleText: .white,
            textPrimary: Color(hue: Double(h), saturation: Double(s) * 0.3, brightness: 0.2),
            textSecondary: Color(hue: Double(h), saturation: Double(s) * 0.15, brightness: 0.5),
            statusIdle: Color(hue: Double(h), saturation: 0.1, brightness: 0.7),
            statusWorking: Color(hue: 0.08, saturation: 0.5, brightness: 0.9),
            statusBusy: Color(hue: 0.0, saturation: 0.45, brightness: 0.85),
            statusError: Color(hue: 0.0, saturation: 0.45, brightness: 0.85),
            roomPlanning: Color(hue: Double(h), saturation: Double(s) * 0.5, brightness: Double(b)),
            roomInProgress: Color(hue: 0.08, saturation: 0.5, brightness: 0.9),
            roomAwaitingApproval: Color(hue: 0.13, saturation: 0.5, brightness: 0.9),
            roomAwaitingUserInput: Color(hue: 0.52, saturation: 0.4, brightness: 0.85),
            roomCompleted: Color(hue: 0.38, saturation: 0.4, brightness: 0.8),
            roomFailed: Color(hue: 0.0, saturation: 0.45, brightness: 0.85),
            messageError: Color(hue: 0.0, saturation: 0.45, brightness: 0.85),
            messageSummary: Color(hue: Double(h), saturation: Double(s) * 0.5, brightness: Double(b)),
            messageChainProgress: Color(hue: 0.58, saturation: 0.4, brightness: 0.85),
            messageDelegation: Color(hue: 0.08, saturation: 0.5, brightness: 0.9),
            messageSuggestion: Color(hue: 0.08, saturation: 0.5, brightness: 0.9),
            messageToolActivity: Color(hue: Double(h), saturation: 0.1, brightness: 0.7),
            messageBuildStatus: Color(hue: 0.08, saturation: 0.5, brightness: 0.9),
            messageQaStatus: Color(hue: 0.48, saturation: 0.35, brightness: 0.8),
            messageApprovalRequest: Color(hue: 0.13, saturation: 0.5, brightness: 0.9),
            messageProgress: Color(hue: 0.58, saturation: 0.4, brightness: 0.85),
            messageDefault: Color(hue: Double(h), saturation: 0.1, brightness: 0.7),
            sidebarBackground: veryLight,
            sidebarShadow: Color.black.opacity(0.06),
            panelGradientStart: veryLight,
            panelGradientEnd: light,
            buttonShadow: Color(hue: Double(h), saturation: Double(s) * 0.4, brightness: Double(b) * 0.7),
            cardBorder: mid,
            progressHighlight: Color.white.opacity(0.4),
            avatarBorder: medium
        )
    }
}

// MARK: - Color ↔ Hex 변환

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(components.redComponent * 255))
        let g = Int(round(components.greenComponent * 255))
        let b = Int(round(components.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
