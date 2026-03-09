import SwiftUI

/// 확장형 진행 버블: 접힌 상태에서 "~하는 중..." 캡슐, 펼치면 상세 활동 로그 표시
struct ProgressActivityBubble: View {
    @Environment(\.colorPalette) private var palette
    let message: ChatMessage
    let activities: [ChatMessage]
    /// 현재 이 단계가 진행 중인지 (로딩 스피너 표시용)
    var isActive: Bool = false

    @State private var isExpanded = false
    @State private var expandedActivityIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 (항상 보임) — Button으로 ScrollView 내 탭 보장
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                headerView
            }
            .buttonStyle(.plain)

            // 확장 영역
            if isExpanded {
                expandedView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - 헤더 (접힌 상태)

    private var headerView: some View {
        HStack(spacing: 6) {
            Spacer()

            // 진행 아이콘
            if isActive {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green.opacity(0.6))
            }

            Text(message.content)
                .font(.system(size: DesignTokens.FontSize.xs))
                .foregroundColor(.secondary.opacity(0.6))

            // 활동 개수 뱃지 + 화살표
            if !activities.isEmpty {
                Text("\(activities.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
            }

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary.opacity(0.4))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(palette.panelGradient)
                .overlay(Capsule().strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1))
        )
        .shadow(color: palette.sidebarShadow, radius: 4, y: 2)
        .contentShape(Capsule())
    }

    // MARK: - 확장 영역 (활동 로그)

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if activities.isEmpty && isActive {
                // 활동 로그가 아직 없을 때
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 10, height: 10)
                    Text("대기 중...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                    Spacer()
                    Text(elapsedLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }

            ForEach(activities) { activity in
                activityRow(activity)
            }

            // 진행 중이고 활동이 있을 때 — 마지막 활동 요약 + 경과 시간
            if isActive && !activities.isEmpty {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 10, height: 10)
                    Text(lastActivityLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(elapsedLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 20)
    }

    // MARK: - 활동 행

    @ViewBuilder
    private func activityRow(_ activity: ChatMessage) -> some View {
        let hasPreview = activity.toolDetail?.contentPreview != nil
        let isDetailExpanded = expandedActivityIDs.contains(activity.id)

        VStack(alignment: .leading, spacing: 0) {
            // 요약 행 (항상 보임)
            Button {
                guard hasPreview else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isDetailExpanded {
                        expandedActivityIDs.remove(activity.id)
                    } else {
                        expandedActivityIDs.insert(activity.id)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: detailAwareIcon(activity))
                        .font(.system(size: 9))
                        .foregroundColor(detailAwareColor(activity))
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 1) {
                        // 한국어 도구명 + 대상
                        if let detail = activity.toolDetail {
                            Text("\(detail.displayName)\(detail.subject.map { " → \($0)" } ?? "")")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.6))
                                .lineLimit(2)
                        } else {
                            Text(activity.content)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.6))
                                .lineLimit(2)
                        }

                        // 파일 경로 (subject가 경로일 때)
                        if let subject = activity.toolDetail?.subject,
                           subject.hasPrefix("/") || subject.hasPrefix("~/") {
                            Text(subject)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.45))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()

                    if hasPreview {
                        Image(systemName: isDetailExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary.opacity(0.3))
                    }

                    Text(timeLabel(activity.timestamp))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)

            // 상세 미리보기 (확장 시)
            if isDetailExpanded, let preview = activity.toolDetail?.contentPreview {
                toolDetailPreview(preview)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 도구 실행 결과 미리보기
    private func toolDetailPreview(_ preview: String) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(preview)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.inputBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    /// toolDetail이 있으면 도구별 아이콘, 없으면 기존 문자열 매칭
    private func detailAwareIcon(_ activity: ChatMessage) -> String {
        if let detail = activity.toolDetail {
            if detail.isError { return "xmark.circle" }
            switch detail.toolName {
            case "file_read":  return "doc.text"
            case "file_write": return "doc.badge.plus"
            case "shell_exec": return "terminal"
            case "web_search": return "magnifyingglass"
            case "web_fetch":  return "globe"
            case "context_info": return "brain"
            case "llm_call":   return "arrow.up.circle"
            case "llm_result": return "checkmark.circle.fill"
            case "llm_error":  return "xmark.octagon"
            default:           return "checkmark.circle"
            }
        }
        return activityIconFallback(activity.content)
    }

    /// toolDetail이 있으면 상태별 색상, 없으면 기존 문자열 매칭
    private func detailAwareColor(_ activity: ChatMessage) -> Color {
        if let detail = activity.toolDetail {
            return detail.isError ? .red.opacity(0.6) : .green.opacity(0.6)
        }
        return activityColorFallback(activity.content)
    }

    // 기존 문자열 매칭 (하위 호환)
    private func activityIconFallback(_ content: String) -> String {
        if content.contains("도구 호출") { return "wrench.and.screwdriver" }
        if content.contains("성공") { return "checkmark.circle" }
        if content.contains("오류") || content.contains("실패") { return "xmark.circle" }
        return "arrow.right.circle"
    }

    private func activityColorFallback(_ content: String) -> Color {
        if content.contains("성공") { return .green.opacity(0.6) }
        if content.contains("오류") || content.contains("실패") { return .red.opacity(0.6) }
        return .secondary.opacity(0.5)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 마지막 활동 요약 (한국어 도구명 + 대상)
    private var lastActivityLabel: String {
        guard let last = activities.last else { return "실행 중..." }
        if let detail = last.toolDetail {
            let subject = detail.subject.map { " → \($0)" } ?? ""
            return "\(detail.displayName)\(subject)"
        }
        return last.content.isEmpty ? "실행 중..." : last.content
    }

    private var elapsedLabel: String {
        let elapsed = Int(Date().timeIntervalSince(message.timestamp))
        if elapsed < 60 { return "\(elapsed)초" }
        return "\(elapsed / 60)분 \(elapsed % 60)초"
    }
}
