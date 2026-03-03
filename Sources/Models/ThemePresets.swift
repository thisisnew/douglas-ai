import SwiftUI

/// 테마 ID
enum ThemeID: String, Codable, CaseIterable, Equatable, Hashable {
    case cozyGame
    case pastel
    case dark
    case warmCozy
    case custom

    var displayName: String {
        switch self {
        case .cozyGame: return "코지 게임"
        case .pastel:   return "파스텔"
        case .dark:     return "다크"
        case .warmCozy: return "따뜻한"
        case .custom:   return "커스텀"
        }
    }
}

/// 내장 테마 프리셋 정의
enum ThemePresets {

    // MARK: - 파스텔 (기본)
    /// 라벤더-핑크 기반 부드러운 파스텔 톤
    static let pastel = ColorPalette(
        background: Color(red: 0.97, green: 0.95, blue: 0.98),
        inputBackground: Color(red: 0.94, green: 0.92, blue: 0.96),
        surfaceSecondary: Color(red: 0.95, green: 0.93, blue: 0.97),
        surfaceTertiary: Color(red: 0.96, green: 0.94, blue: 0.98),
        hoverBackground: Color(red: 0.92, green: 0.89, blue: 0.95),
        activeRowBackground: Color(red: 0.94, green: 0.91, blue: 0.96),
        systemMessageBackground: Color(red: 0.96, green: 0.94, blue: 0.98),
        messageBubbleBackground: Color(red: 0.94, green: 0.92, blue: 0.96),
        avatarFallback: Color(red: 0.92, green: 0.89, blue: 0.95),
        overlay: Color(red: 0.91, green: 0.88, blue: 0.94),
        separator: Color(red: 0.89, green: 0.86, blue: 0.92),
        closeButton: Color(red: 0.92, green: 0.89, blue: 0.95),
        thumbnailDelete: Color.black.opacity(0.4),
        stepInactive: Color(red: 0.89, green: 0.86, blue: 0.92),
        accent: Color(red: 0.70, green: 0.55, blue: 0.82),
        userBubble: Color(red: 0.70, green: 0.55, blue: 0.82),
        userBubbleText: .white,
        textPrimary: Color(red: 0.22, green: 0.18, blue: 0.28),
        textSecondary: Color(red: 0.50, green: 0.45, blue: 0.58),
        statusIdle: Color(red: 0.68, green: 0.73, blue: 0.80),
        statusWorking: Color(red: 0.93, green: 0.73, blue: 0.52),
        statusBusy: Color(red: 0.88, green: 0.52, blue: 0.58),
        statusError: Color(red: 0.88, green: 0.52, blue: 0.58),
        roomPlanning: Color(red: 0.75, green: 0.62, blue: 0.86),
        roomInProgress: Color(red: 0.93, green: 0.73, blue: 0.52),
        roomAwaitingApproval: Color(red: 0.93, green: 0.86, blue: 0.52),
        roomAwaitingUserInput: Color(red: 0.55, green: 0.78, blue: 0.85),
        roomCompleted: Color(red: 0.55, green: 0.80, blue: 0.62),
        roomFailed: Color(red: 0.88, green: 0.52, blue: 0.58),
        messageError: Color(red: 0.88, green: 0.52, blue: 0.58),
        messageSummary: Color(red: 0.75, green: 0.62, blue: 0.86),
        messageChainProgress: Color(red: 0.52, green: 0.68, blue: 0.86),
        messageDelegation: Color(red: 0.93, green: 0.73, blue: 0.52),
        messageSuggestion: Color(red: 0.93, green: 0.73, blue: 0.52),
        messageToolActivity: Color(red: 0.68, green: 0.73, blue: 0.80),
        messageBuildStatus: Color(red: 0.93, green: 0.73, blue: 0.52),
        messageQaStatus: Color(red: 0.52, green: 0.76, blue: 0.76),
        messageApprovalRequest: Color(red: 0.93, green: 0.86, blue: 0.52),
        messageProgress: Color(red: 0.52, green: 0.68, blue: 0.86),
        messageDefault: Color(red: 0.68, green: 0.73, blue: 0.80),
        sidebarBackground: Color(red: 0.97, green: 0.95, blue: 0.98),
        sidebarShadow: Color.black.opacity(0.06),
        panelGradientStart: Color(red: 0.97, green: 0.95, blue: 0.98),
        panelGradientEnd: Color(red: 0.95, green: 0.93, blue: 0.97),
        buttonShadow: Color(red: 0.55, green: 0.42, blue: 0.65),
        cardBorder: Color(red: 0.89, green: 0.86, blue: 0.92),
        progressHighlight: Color.white.opacity(0.4),
        avatarBorder: Color(red: 0.89, green: 0.86, blue: 0.92)
    )

    // MARK: - 다크
    /// 어두운 톤, 부드러운 채도
    static let dark = ColorPalette(
        background: Color(red: 0.11, green: 0.11, blue: 0.14),
        inputBackground: Color(red: 0.15, green: 0.15, blue: 0.19),
        surfaceSecondary: Color(red: 0.14, green: 0.14, blue: 0.18),
        surfaceTertiary: Color(red: 0.13, green: 0.13, blue: 0.16),
        hoverBackground: Color(red: 0.18, green: 0.18, blue: 0.22),
        activeRowBackground: Color(red: 0.16, green: 0.16, blue: 0.20),
        systemMessageBackground: Color(red: 0.13, green: 0.13, blue: 0.16),
        messageBubbleBackground: Color(red: 0.15, green: 0.15, blue: 0.19),
        avatarFallback: Color(red: 0.18, green: 0.18, blue: 0.22),
        overlay: Color(red: 0.20, green: 0.20, blue: 0.24),
        separator: Color(red: 0.22, green: 0.22, blue: 0.26),
        closeButton: Color(red: 0.18, green: 0.18, blue: 0.22),
        thumbnailDelete: Color.black.opacity(0.6),
        stepInactive: Color(red: 0.22, green: 0.22, blue: 0.26),
        accent: Color(red: 0.60, green: 0.50, blue: 0.82),
        userBubble: Color(red: 0.55, green: 0.45, blue: 0.75),
        userBubbleText: .white,
        textPrimary: Color(red: 0.90, green: 0.88, blue: 0.93),
        textSecondary: Color(red: 0.58, green: 0.55, blue: 0.65),
        statusIdle: Color(red: 0.45, green: 0.48, blue: 0.55),
        statusWorking: Color(red: 0.85, green: 0.65, blue: 0.40),
        statusBusy: Color(red: 0.80, green: 0.42, blue: 0.48),
        statusError: Color(red: 0.80, green: 0.42, blue: 0.48),
        roomPlanning: Color(red: 0.62, green: 0.50, blue: 0.78),
        roomInProgress: Color(red: 0.85, green: 0.65, blue: 0.40),
        roomAwaitingApproval: Color(red: 0.85, green: 0.78, blue: 0.40),
        roomAwaitingUserInput: Color(red: 0.40, green: 0.68, blue: 0.78),
        roomCompleted: Color(red: 0.40, green: 0.70, blue: 0.50),
        roomFailed: Color(red: 0.80, green: 0.42, blue: 0.48),
        messageError: Color(red: 0.80, green: 0.42, blue: 0.48),
        messageSummary: Color(red: 0.62, green: 0.50, blue: 0.78),
        messageChainProgress: Color(red: 0.42, green: 0.58, blue: 0.78),
        messageDelegation: Color(red: 0.85, green: 0.65, blue: 0.40),
        messageSuggestion: Color(red: 0.85, green: 0.65, blue: 0.40),
        messageToolActivity: Color(red: 0.45, green: 0.48, blue: 0.55),
        messageBuildStatus: Color(red: 0.85, green: 0.65, blue: 0.40),
        messageQaStatus: Color(red: 0.42, green: 0.68, blue: 0.68),
        messageApprovalRequest: Color(red: 0.85, green: 0.78, blue: 0.40),
        messageProgress: Color(red: 0.42, green: 0.58, blue: 0.78),
        messageDefault: Color(red: 0.45, green: 0.48, blue: 0.55),
        sidebarBackground: Color(red: 0.11, green: 0.11, blue: 0.14),
        sidebarShadow: Color.black.opacity(0.3),
        panelGradientStart: Color(red: 0.14, green: 0.14, blue: 0.18),
        panelGradientEnd: Color(red: 0.11, green: 0.11, blue: 0.14),
        buttonShadow: Color.black.opacity(0.4),
        cardBorder: Color(red: 0.22, green: 0.22, blue: 0.26),
        progressHighlight: Color.white.opacity(0.15),
        avatarBorder: Color(red: 0.22, green: 0.22, blue: 0.26)
    )

    // MARK: - 따뜻한 톤
    /// 베이지-브라운 기반의 포근한 톤
    static let warmCozy = ColorPalette(
        background: Color(red: 0.97, green: 0.95, blue: 0.92),
        inputBackground: Color(red: 0.94, green: 0.91, blue: 0.87),
        surfaceSecondary: Color(red: 0.95, green: 0.92, blue: 0.88),
        surfaceTertiary: Color(red: 0.96, green: 0.93, blue: 0.90),
        hoverBackground: Color(red: 0.92, green: 0.88, blue: 0.83),
        activeRowBackground: Color(red: 0.94, green: 0.90, blue: 0.86),
        systemMessageBackground: Color(red: 0.96, green: 0.93, blue: 0.90),
        messageBubbleBackground: Color(red: 0.94, green: 0.91, blue: 0.87),
        avatarFallback: Color(red: 0.92, green: 0.88, blue: 0.83),
        overlay: Color(red: 0.90, green: 0.86, blue: 0.80),
        separator: Color(red: 0.88, green: 0.84, blue: 0.78),
        closeButton: Color(red: 0.92, green: 0.88, blue: 0.83),
        thumbnailDelete: Color.black.opacity(0.4),
        stepInactive: Color(red: 0.88, green: 0.84, blue: 0.78),
        accent: Color(red: 0.72, green: 0.55, blue: 0.40),
        userBubble: Color(red: 0.72, green: 0.55, blue: 0.40),
        userBubbleText: .white,
        textPrimary: Color(red: 0.25, green: 0.20, blue: 0.16),
        textSecondary: Color(red: 0.52, green: 0.46, blue: 0.40),
        statusIdle: Color(red: 0.72, green: 0.68, blue: 0.62),
        statusWorking: Color(red: 0.90, green: 0.70, blue: 0.45),
        statusBusy: Color(red: 0.85, green: 0.50, blue: 0.45),
        statusError: Color(red: 0.85, green: 0.50, blue: 0.45),
        roomPlanning: Color(red: 0.72, green: 0.60, blue: 0.78),
        roomInProgress: Color(red: 0.90, green: 0.70, blue: 0.45),
        roomAwaitingApproval: Color(red: 0.90, green: 0.82, blue: 0.45),
        roomAwaitingUserInput: Color(red: 0.52, green: 0.72, blue: 0.78),
        roomCompleted: Color(red: 0.52, green: 0.75, blue: 0.55),
        roomFailed: Color(red: 0.85, green: 0.50, blue: 0.45),
        messageError: Color(red: 0.85, green: 0.50, blue: 0.45),
        messageSummary: Color(red: 0.72, green: 0.60, blue: 0.78),
        messageChainProgress: Color(red: 0.52, green: 0.65, blue: 0.80),
        messageDelegation: Color(red: 0.90, green: 0.70, blue: 0.45),
        messageSuggestion: Color(red: 0.90, green: 0.70, blue: 0.45),
        messageToolActivity: Color(red: 0.72, green: 0.68, blue: 0.62),
        messageBuildStatus: Color(red: 0.90, green: 0.70, blue: 0.45),
        messageQaStatus: Color(red: 0.52, green: 0.72, blue: 0.72),
        messageApprovalRequest: Color(red: 0.90, green: 0.82, blue: 0.45),
        messageProgress: Color(red: 0.52, green: 0.65, blue: 0.80),
        messageDefault: Color(red: 0.72, green: 0.68, blue: 0.62),
        sidebarBackground: Color(red: 0.97, green: 0.95, blue: 0.92),
        sidebarShadow: Color.black.opacity(0.08),
        panelGradientStart: Color(red: 0.97, green: 0.95, blue: 0.92),
        panelGradientEnd: Color(red: 0.95, green: 0.92, blue: 0.88),
        buttonShadow: Color(red: 0.58, green: 0.44, blue: 0.32),
        cardBorder: Color(red: 0.88, green: 0.84, blue: 0.78),
        progressHighlight: Color.white.opacity(0.35),
        avatarBorder: Color(red: 0.88, green: 0.84, blue: 0.78)
    )

    // MARK: - 코지 게임
    /// 부드럽고 둥근 2D 게임 스타일 파스텔 톤
    static let cozyGame = ColorPalette(
        background: Color(hex: "FFF8F0"),
        inputBackground: Color(hex: "F5EDE4"),
        surfaceSecondary: Color(hex: "FFF0E8"),
        surfaceTertiary: Color(hex: "FFF5EE"),
        hoverBackground: Color(hex: "FFE8DC"),
        activeRowBackground: Color(hex: "FFF0E8"),
        systemMessageBackground: Color(hex: "FFF5EE"),
        messageBubbleBackground: Color(hex: "FFF0E8"),
        avatarFallback: Color(hex: "FFE0D0"),
        overlay: Color(hex: "F0E6F6"),
        separator: Color(hex: "E8DCD0"),
        closeButton: Color(hex: "E8DCD0"),
        thumbnailDelete: Color.black.opacity(0.4),
        stepInactive: Color(hex: "D8CCC0"),
        accent: Color(hex: "FF8FAB"),
        userBubble: Color(hex: "FF8FAB"),
        userBubbleText: .white,
        textPrimary: Color(hex: "4A3A2E"),
        textSecondary: Color(hex: "8A7A6E"),
        statusIdle: Color(hex: "A2D5F2"),
        statusWorking: Color(hex: "FFD666"),
        statusBusy: Color(hex: "FF8FAB"),
        statusError: Color(hex: "F06878"),
        roomPlanning: Color(hex: "C5A3E0"),
        roomInProgress: Color(hex: "FFB366"),
        roomAwaitingApproval: Color(hex: "FFD666"),
        roomAwaitingUserInput: Color(hex: "A2D5F2"),
        roomCompleted: Color(hex: "8ECF99"),
        roomFailed: Color(hex: "F06878"),
        messageError: Color(hex: "F06878"),
        messageSummary: Color(hex: "C5A3E0"),
        messageChainProgress: Color(hex: "A2D5F2"),
        messageDelegation: Color(hex: "FFB366"),
        messageSuggestion: Color(hex: "FFB366"),
        messageToolActivity: Color(hex: "A2D5F2"),
        messageBuildStatus: Color(hex: "FFB366"),
        messageQaStatus: Color(hex: "8ECF99"),
        messageApprovalRequest: Color(hex: "FFD666"),
        messageProgress: Color(hex: "A2D5F2"),
        messageDefault: Color(hex: "D4B896"),
        sidebarBackground: Color(hex: "FFF0E8"),
        sidebarShadow: Color(hex: "D4A880").opacity(0.12),
        panelGradientStart: Color(hex: "FFF8F0"),
        panelGradientEnd: Color(hex: "FFF0E8"),
        buttonShadow: Color(hex: "D4687F"),
        cardBorder: Color(hex: "E8D0C0"),
        progressHighlight: Color.white.opacity(0.4),
        avatarBorder: Color(hex: "FFD0B8")
    )

    /// ThemeID로 프리셋 팔레트 가져오기
    static func palette(for id: ThemeID, customAccent: Color = .purple) -> ColorPalette {
        switch id {
        case .cozyGame: return cozyGame
        case .pastel:   return pastel
        case .dark:     return dark
        case .warmCozy: return warmCozy
        case .custom:   return .custom(accent: customAccent)
        }
    }
}
