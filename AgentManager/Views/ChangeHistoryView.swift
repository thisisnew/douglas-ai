import SwiftUI

struct ChangeHistoryView: View {
    @EnvironmentObject var devAgentManager: DevAgentManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.green)
                Text("변경 이력")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            if devAgentManager.changeHistory.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("변경 이력이 없습니다")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(devAgentManager.changeHistory.reversed()) { record in
                    ChangeRecordRow(record: record)
                }
            }

            Divider()

            HStack {
                if !devAgentManager.isGitInitialized {
                    Label("버전 관리 미설정", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }
}

struct ChangeRecordRow: View {
    let record: ChangeRecord
    @EnvironmentObject var devAgentManager: DevAgentManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                statusIcon
                Text(record.description)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                Text(record.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Commit: \(record.commitHash)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)

                if !record.filesChanged.isEmpty {
                    Text("(\(record.filesChanged.count)개 파일)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if record.status == .applied {
                Button("되돌리기") {
                    Task {
                        try? await devAgentManager.revertChange(record)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            } else if record.status == .rolledBack {
                Text("되돌림")
                    .font(.caption2)
                    .foregroundColor(.orange)
            } else if record.status == .failed {
                Text("실패")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch record.status {
        case .applied:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .rolledBack:
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundColor(.orange)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }
}
