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

    // MARK: - 시스템 폰트 크기 (semantic font 외 특수 용도)

    enum FontSize {
        /// 뱃지 숫자, 상태 텍스트
        static let badge: CGFloat = 9
        /// 아주 작은 라벨
        static let micro: CGFloat = 9
        /// 상태 뱃지 텍스트
        static let status: CGFloat = 10
        /// 타이머 표시
        static let timer: CGFloat = 11
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
        static func color(for status: AgentStatus) -> Color {
            switch status {
            case .idle:    return .gray
            case .working: return .orange
            case .busy:    return .red
            case .error:   return .red
            }
        }
    }

    // MARK: - 방 상태 색상

    enum RoomStatusColor {
        static func color(for status: RoomStatus) -> Color {
            switch status {
            case .planning:          return .purple
            case .inProgress:        return .orange
            case .awaitingApproval:  return .yellow
            case .completed:         return .green
            case .failed:            return .red
            }
        }

        static func label(for status: RoomStatus) -> String {
            switch status {
            case .planning:          return "계획 중"
            case .inProgress:        return "진행중"
            case .awaitingApproval:  return "승인 대기"
            case .completed:         return "완료"
            case .failed:            return "실패"
            }
        }
    }

    // MARK: - 메시지 타입별 색상

    enum MessageColor {
        static func background(for type: MessageType) -> Color {
            switch type {
            case .error:           return .red
            case .summary:         return .purple
            case .chainProgress:   return .blue
            case .delegation:      return .orange
            case .suggestion:      return .orange
            case .text:            return .gray
            case .discussionRound: return .gray
            case .toolActivity:    return .gray
            case .buildStatus:     return .orange
            case .qaStatus:        return .teal
            case .approvalRequest: return .yellow
            }
        }

        static func foreground(for type: MessageType) -> Color {
            switch type {
            case .error:         return .red
            case .summary:       return .purple
            case .chainProgress: return .blue
            case .delegation:    return .orange
            case .suggestion:    return .orange
            default:             return .secondary
            }
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

    // MARK: - 애니메이션 길이

    enum Animation {
        static let fast: Double = 0.15
        static let standard: Double = 0.2
        static let slow: Double = 0.3
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
