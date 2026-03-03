import SwiftUI

/// 확장형 진행 버블: 접힌 상태에서 "~하는 중..." 캡슐, 펼치면 상세 활동 로그 표시
struct ProgressActivityBubble: View {
    @Environment(\.colorPalette) private var palette
    let message: ChatMessage
    let activities: [ChatMessage]
    /// 현재 이 단계가 진행 중인지 (로딩 스피너 표시용)
    var isActive: Bool = false

    @State private var isExpanded = false

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
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(palette.systemMessageBackground)
        .clipShape(Capsule())
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

            // 진행 중이고 활동이 있을 때 — 마지막 행 아래에 경과 시간
            if isActive && !activities.isEmpty {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 10, height: 10)
                    Text("실행 중...")
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
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 20)
    }

    // MARK: - 활동 행

    private func activityRow(_ activity: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: activityIcon(activity.content))
                .font(.system(size: 9))
                .foregroundColor(activityColor(activity.content))
                .frame(width: 12)

            Text(activity.content)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
                .lineLimit(2)

            Spacer()

            Text(timeLabel(activity.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private func activityIcon(_ content: String) -> String {
        if content.contains("도구 호출") { return "wrench.and.screwdriver" }
        if content.contains("성공") { return "checkmark.circle" }
        if content.contains("오류") || content.contains("실패") { return "xmark.circle" }
        return "arrow.right.circle"
    }

    private func activityColor(_ content: String) -> Color {
        if content.contains("성공") { return .green.opacity(0.6) }
        if content.contains("오류") || content.contains("실패") { return .red.opacity(0.6) }
        return .secondary.opacity(0.5)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private var elapsedLabel: String {
        let elapsed = Int(Date().timeIntervalSince(message.timestamp))
        if elapsed < 60 { return "\(elapsed)초" }
        return "\(elapsed / 60)분 \(elapsed % 60)초"
    }
}
