import SwiftUI

// MARK: - 작업일지 뷰 (날짜별 그룹)

struct WorkLogView: View {
    @EnvironmentObject var roomManager: RoomManager

    private var logsByDate: [(String, [WorkLog])] {
        let logs = roomManager.rooms
            .compactMap { $0.workLog }
            .sorted { $0.createdAt > $1.createdAt }

        let grouped = Dictionary(grouping: logs) { log in
            Self.sectionFormatter.string(from: log.createdAt)
        }

        return grouped
            .sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text("작업일지")
                    .font(.headline)
                Spacer()
                Text("\(roomManager.rooms.compactMap(\.workLog).count)건")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if logsByDate.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("아직 완료된 작업이 없습니다")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(logsByDate, id: \.0) { dateString, logs in
                            Section {
                                ForEach(logs) { log in
                                    LogEntryRow(log: log)
                                    if log.id != logs.last?.id {
                                        Divider().padding(.leading, 52)
                                    }
                                }
                            } header: {
                                dateSectionHeader(dateString)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(width: 520, height: 560)
    }

    private func dateSectionHeader(_ dateString: String) -> some View {
        HStack {
            Text(dateString)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private static let sectionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 (E)"
        return f
    }()
}

// MARK: - 개별 로그 엔트리

struct LogEntryRow: View {
    let log: WorkLog
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 요약 행
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    // 시간
                    Text(Self.timeFormatter.string(from: log.createdAt))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 38, alignment: .leading)

                    // 내용
                    VStack(alignment: .leading, spacing: 3) {
                        Text(log.roomTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(log.outcome.components(separatedBy: "\n").first ?? "")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? 10 : 1)
                    }

                    Spacer()

                    // 소요 시간 + 참여자 수
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDuration(log.durationSeconds))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(log.participants.count)명")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 확장 내용
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // 참여자
                    logDetail(label: "참여자", value: log.participants.joined(separator: ", "))

                    // 작업 내용
                    logDetail(label: "작업", value: log.task)

                    // 전체 결과
                    if !log.outcome.isEmpty {
                        logDetail(label: "결과", value: log.outcome)
                    }

                    // 토론 요약
                    if !log.discussionSummary.isEmpty {
                        logDetail(label: "토론", value: log.discussionSummary)
                    }

                    // 계획 요약
                    if !log.planSummary.isEmpty {
                        logDetail(label: "계획", value: log.planSummary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.leading, 48)
                .padding(.bottom, 12)
            }
        }
    }

    private func logDetail(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary.opacity(0.6))
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.8))
                .textSelection(.enabled)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)초" }
        let min = seconds / 60
        if min < 60 { return "\(min)분" }
        let hr = min / 60
        let remainMin = min % 60
        return "\(hr)시간 \(remainMin)분"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
