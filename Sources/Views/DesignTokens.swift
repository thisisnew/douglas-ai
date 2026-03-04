import SwiftUI

/// DOUGLAS 통합 디자인 시스템
enum DesignTokens {

    // MARK: - 간격

    enum Spacing {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24

        /// 컨텐츠 영역 기본 수평 패딩
        static let contentH: CGFloat = 12
        /// 컨텐츠 영역 기본 수직 패딩
        static let contentV: CGFloat = 8
        /// 입력 필드 패딩
        static let inputPadding: CGFloat = 10
    }

    // MARK: - 모서리 반경

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 10
        static let xxl: CGFloat = 16

        /// 메시지 버블
        static let bubble: CGFloat = 16
        /// 뱃지
        static let badge: CGFloat = 6
        /// 사이드바 외곽
        static let sidebar: CGFloat = 16
    }

    // MARK: - 투명도

    enum Opacity {
        /// 매우 연한 배경 (카드)
        static let subtle: Double = 0.05
        /// 연한 배경 (뱃지)
        static let light: Double = 0.1
        /// 중간 배경
        static let medium: Double = 0.15
        /// 반투명
        static let half: Double = 0.5
        /// 강한 투명도
        static let strong: Double = 0.7

        /// 입력 필드 배경
        static let inputBg: Double = 0.04
        /// 컨트롤 배경
        static let controlBg: Double = 0.5
        /// 뱃지 배경
        static let badgeBg: Double = 0.12
    }

    // MARK: - 시맨틱 색상 (다크모드 자동 대응)

    enum Colors {
        /// 윈도우/시트 메인 배경 (Color.white 대체)
        static let background = Color(nsColor: .windowBackgroundColor)
        /// 입력 필드, TextEditor 배경
        static let inputBackground = Color.primary.opacity(0.04)
        /// 카드/그룹 배경
        static let surfaceSecondary = Color.primary.opacity(0.04)
        /// 약한 카드 배경
        static let surfaceTertiary = Color.primary.opacity(0.03)
        /// 호버 상태 배경
        static let hoverBackground = Color.primary.opacity(0.07)
        /// 활성 행 배경
        static let activeRowBackground = Color.primary.opacity(0.04)
        /// 시스템 메시지 배경
        static let systemMessageBackground = Color.primary.opacity(0.03)
        /// 기본 메시지 버블 배경
        static let messageBubbleBackground = Color.primary.opacity(0.05)
        /// 아바타 폴백 배경
        static let avatarFallback = Color.primary.opacity(0.06)
        /// 슬래시 메뉴/퀵인풋 배경
        static let overlay = Color.primary.opacity(0.08)
        /// 구분선
        static let separator = Color.primary.opacity(0.08)
        /// 닫기/xmark 버튼 배경
        static let closeButton = Color.primary.opacity(0.06)
        /// 썸네일 삭제 버튼 배경
        static let thumbnailDelete = Color.black.opacity(0.5)
        /// 스텝 인디케이터 비활성
        static let stepInactive = Color.primary.opacity(0.1)
    }

    // MARK: - 시스템 폰트 크기

    enum FontSize {
        /// 극소 아이콘 보조 텍스트 (8pt)
        static let nano: CGFloat = 8
        /// 뱃지 숫자, 상태 텍스트 (9pt)
        static let badge: CGFloat = 9
        /// 아주 작은 라벨 (9pt)
        static let micro: CGFloat = 9
        /// 보조 레이블, 타임스탬프 (10pt)
        static let xs: CGFloat = 10
        /// 상태 뱃지 텍스트 (10pt)
        static let status: CGFloat = 10
        /// 작은 레이블 (11pt)
        static let sm: CGFloat = 11
        /// 타이머 표시 (11pt)
        static let timer: CGFloat = 11
        /// 작은 본문 (12pt)
        static let body: CGFloat = 12
        /// 기본 본문 — 채팅 버블 (13pt)
        static let bodyMd: CGFloat = 13
        /// 헤더 아이콘/버튼 (14pt)
        static let icon: CGFloat = 14
    }

    // MARK: - 타이포그래피 헬퍼

    enum Typography {
        /// 모노스페이스 폰트
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        /// 모노스페이스 뱃지 (9pt bold)
        static let monoBadge: Font = .system(size: FontSize.badge, weight: .bold, design: .monospaced)
        /// 모노스페이스 상태 (10pt bold)
        static let monoStatus: Font = .system(size: FontSize.xs, weight: .bold, design: .monospaced)
    }

    // MARK: - 아바타 크기

    enum AvatarSize {
        static let xs: CGFloat = 20
        static let sm: CGFloat = 24
        static let md: CGFloat = 28
        static let lg: CGFloat = 36
        static let xl: CGFloat = 40
        static let xxl: CGFloat = 48
    }

    // MARK: - 에이전트 상태 색상

    enum StatusColor {
        static func color(for status: AgentStatus, palette: ColorPalette) -> Color {
            switch status {
            case .idle:    return palette.statusIdle
            case .working: return palette.statusWorking
            case .busy:    return palette.statusBusy
            case .error:   return palette.statusError
            }
        }
        /// 레거시 호환 (palette 없이 호출 시 기본 팔레트 사용)
        static func color(for status: AgentStatus) -> Color {
            color(for: status, palette: ThemePresets.pastel)
        }
    }

    // MARK: - 방 상태 색상

    enum RoomStatusColor {
        static func color(for status: RoomStatus, palette: ColorPalette) -> Color {
            switch status {
            case .planning:          return palette.roomPlanning
            case .inProgress:        return palette.roomInProgress
            case .awaitingApproval:  return palette.roomAwaitingApproval
            case .awaitingUserInput: return palette.roomAwaitingUserInput
            case .completed:         return palette.roomCompleted
            case .failed:            return palette.roomFailed
            }
        }
        /// 레거시 호환
        static func color(for status: RoomStatus) -> Color {
            color(for: status, palette: ThemePresets.pastel)
        }

        static func label(for status: RoomStatus) -> String {
            switch status {
            case .planning:          return "계획 중"
            case .inProgress:        return "진행중"
            case .awaitingApproval:  return "승인 대기"
            case .awaitingUserInput: return "입력 대기"
            case .completed:         return "완료"
            case .failed:            return "실패"
            }
        }
    }

    // MARK: - 메시지 타입별 색상

    enum MessageColor {
        static func background(for type: MessageType, palette: ColorPalette) -> Color {
            switch type {
            case .error:           return palette.messageError
            case .summary:         return palette.messageSummary
            case .chainProgress:   return palette.messageChainProgress
            case .delegation:      return palette.messageDelegation
            case .suggestion:      return palette.messageSuggestion
            case .text:            return palette.messageDefault
            case .discussionRound: return palette.messageDefault
            case .toolActivity:    return palette.messageToolActivity
            case .buildStatus:     return palette.messageBuildStatus
            case .qaStatus:        return palette.messageQaStatus
            case .approvalRequest: return palette.messageApprovalRequest
            case .fileWriteApproval: return palette.messageApprovalRequest
            case .userQuestion:    return palette.roomAwaitingUserInput
            case .phaseTransition: return palette.messageSummary
            case .assumption:      return palette.messageDelegation
            case .progress:        return palette.messageProgress
            case .discussion:      return palette.messageDefault
            }
        }
        /// 레거시 호환
        static func background(for type: MessageType) -> Color {
            background(for: type, palette: ThemePresets.pastel)
        }

        static func foreground(for type: MessageType, palette: ColorPalette) -> Color {
            switch type {
            case .error:         return palette.messageError
            case .summary:       return palette.messageSummary
            case .chainProgress: return palette.messageChainProgress
            case .delegation:    return palette.messageDelegation
            case .suggestion:    return palette.messageSuggestion
            default:             return palette.textSecondary
            }
        }
        /// 레거시 호환
        static func foreground(for type: MessageType) -> Color {
            foreground(for: type, palette: ThemePresets.pastel)
        }

        static func icon(for type: MessageType) -> String? {
            switch type {
            case .delegation:    return "arrow.turn.up.right"
            case .summary:       return "text.document"
            case .chainProgress: return "link"
            case .suggestion:    return "sparkles"
            case .error:         return "exclamationmark.triangle"
            default:             return nil
            }
        }
    }

    // MARK: - 코지 게임 UI 토큰

    enum CozyGame {
        /// 패널 외곽 모서리 반경
        static let panelRadius: CGFloat = 18
        /// 버튼 모서리 반경
        static let buttonRadius: CGFloat = 14
        /// 카드 모서리 반경
        static let cardRadius: CGFloat = 16
        /// 버튼 하단 그림자 Y 오프셋
        static let buttonShadowY: CGFloat = 4
        /// 버튼 눌림 시 Y 오프셋
        static let buttonPressedY: CGFloat = 2
        /// 카드/패널 테두리 두께
        static let borderWidth: CGFloat = 2.5
        /// 아바타 둥근 사각 반경 비율 (size * 0.28)
        static let avatarRadiusRatio: CGFloat = 0.28
        /// 프로그레스 바 높이
        static let progressBarHeight: CGFloat = 14
        /// 프로그레스 바 모서리 반경
        static let progressBarRadius: CGFloat = 7
        /// 패널 그림자 반경
        static let panelShadowRadius: CGFloat = 10
        /// 패널 그림자 Y
        static let panelShadowY: CGFloat = 4
    }

    // MARK: - 애니메이션 길이

    enum Animation {
        static let fast: Double = 0.15
        static let standard: Double = 0.2
        static let slow: Double = 0.3
        static let springResponse: Double = 0.35
        static let springDamping: Double = 0.7
    }

    // MARK: - 윈도우 크기 상수

    enum WindowSize {
        static let agentSheet = CGSize(width: 480, height: 560)
        static let createRoomSheet = CGSize(width: 480, height: 560)
        static let providerSheet = CGSize(width: 480, height: 560)
        static let agentInfoSheet = CGSize(width: 480, height: 480)
        static let roomChat = CGSize(width: 520, height: 600)
        static let workLog = CGSize(width: 520, height: 560)
        static let onboarding = CGSize(width: 520, height: 560)
        static let settingsSheet = CGSize(width: 500, height: 620)
    }

    // MARK: - 레이아웃 상수

    enum Layout {
        static let sidebarWidth: CGFloat = 400
        static let rosterItemWidth: CGFloat = 48
        static let rosterSpacing: CGFloat = 12
        static let statusIndicatorSize: CGFloat = 10
        static let maxRoomListHeight: CGFloat = 220
    }

    // MARK: - 사이드바 전용 토큰
    // FlowLayout은 아래 파일 하단에 정의

    enum Sidebar {
        /// 외곽 모서리 반경
        static let cornerRadius: CGFloat = 16
        /// 화면 우측 끝에서의 여백
        static let insetTrailing: CGFloat = 6
        /// 화면 좌측(콘텐츠 쪽)의 여백
        static let insetLeading: CGFloat = 4
        /// 상하 여백
        static let insetVertical: CGFloat = 8
        /// 그림자 반경
        static let shadowRadius: CGFloat = 20
        /// 그림자 투명도
        static let shadowOpacity: Double = 0.12
        /// 섹션 구분선 투명도
        static let separatorOpacity: Double = 0.08
        /// 섹션 구분선 높이
        static let separatorHeight: CGFloat = 0.5
        /// 섹션 구분선 좌우 인셋
        static let separatorInset: CGFloat = 16
    }
}

// MARK: - FlowLayout (자동 줄바꿈 레이아웃)

/// 자식 뷰를 수평으로 배치하되, 폭이 넘으면 자동으로 다음 줄로 내린다.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        var maxWidth: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.height }.max() ?? 0
            height += rowHeight
            if i > 0 { height += spacing }
            let rowWidth = row.map { $0.width }.reduce(0, +) + CGFloat(max(row.count - 1, 0)) * spacing
            maxWidth = max(maxWidth, rowWidth)
        }
        return CGSize(width: proposal.width ?? maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY
        var subviewIndex = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.height }.max() ?? 0
            if i > 0 { y += spacing }
            var x = bounds.minX
            for size in row {
                guard subviewIndex < subviews.count else { break }
                subviews[subviewIndex].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                subviewIndex += 1
            }
            y += rowHeight
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[CGSize]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var currentRowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].isEmpty && currentRowWidth + spacing + size.width > maxWidth {
                rows.append([size])
                currentRowWidth = size.width
            } else {
                if !rows[rows.count - 1].isEmpty { currentRowWidth += spacing }
                rows[rows.count - 1].append(size)
                currentRowWidth += size.width
            }
        }
        return rows
    }
}

// MARK: - SwiftUI Animation 편의 확장

extension SwiftUI.Animation {
    static let dgFast = SwiftUI.Animation.easeInOut(duration: DesignTokens.Animation.fast)
    static let dgStandard = SwiftUI.Animation.easeInOut(duration: DesignTokens.Animation.standard)
    static let dgSlow = SwiftUI.Animation.easeInOut(duration: DesignTokens.Animation.slow)
    static let dgSpring = SwiftUI.Animation.spring(
        response: DesignTokens.Animation.springResponse,
        dampingFraction: DesignTokens.Animation.springDamping
    )
    static let dgBounce = SwiftUI.Animation.spring(response: 0.2, dampingFraction: 0.5)
}

// MARK: - 연속 곡선 RoundedRectangle 편의 확장

extension View {
    /// `.cornerRadius(n)` 대체 — `.continuous` 스쿼클 곡선 적용
    func continuousRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
