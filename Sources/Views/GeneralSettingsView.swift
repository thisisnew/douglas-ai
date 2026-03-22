import SwiftUI
import AppKit

/// 일반 설정 — 문서 저장 경로, 업데이트 등
struct GeneralSettingsView: View {
    var isEmbedded = false

    @Environment(\.colorPalette) private var palette
    @EnvironmentObject private var updateManager: UpdateManager
    @EnvironmentObject private var hookManager: HookManager
    @State private var documentSavePath: String = UserDefaults.standard.string(forKey: "documentSaveDirectory") ?? ""
    @State private var showingUpdateAlert = false
    @State private var showNoUpdateToast = false
    @State private var showAddHookSheet = false
    @State private var showAddSafetyRuleSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !isEmbedded {
                    Text("일반")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                }

                // 문서 저장 경로
                documentSaveSection

                // Hook 설정
                hookSection

                // 안전 규칙
                safetySection

                // 소프트웨어 업데이트
                updateSection
            }
            .padding(isEmbedded ? 24 : 16)
        }
        .frame(maxWidth: isEmbedded ? .infinity : nil, maxHeight: isEmbedded ? .infinity : nil)
        .onChange(of: showingUpdateAlert) { show in
            guard show, let release = updateManager.latestVersion else { return }
            showingUpdateAlert = false

            let alert = NSAlert()
            alert.messageText = "새로운 버전이 있습니다"
            alert.informativeText = "현재: \(updateManager.appVersion) → 최신: \(release.version)\n\n\(release.releaseNotes)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "다운로드")
            alert.addButton(withTitle: "나중에")

            if alert.runModal() == .alertFirstButtonReturn {
                updateManager.openDownloadPage()
            }
        }
        .overlay(alignment: .top) {
            if showNoUpdateToast {
                noUpdateToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showNoUpdateToast = false }
                        }
                    }
            }
        }
    }

    // MARK: - 문서 저장 경로

    private var documentSaveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("문서 저장 폴더", systemImage: "folder.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Text("문서 내보내기 시 이 폴더에 자동 저장됩니다. 미설정 시 저장 위치를 매번 묻습니다.")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)

            HStack(spacing: 8) {
                // 경로 표시
                HStack(spacing: 6) {
                    Image(systemName: saveDirectoryIcon)
                        .font(.system(size: 12))
                        .foregroundColor(saveDirectoryIconColor)

                    Text(displayPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(documentSavePath.isEmpty ? palette.textSecondary.opacity(0.5) : palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !documentSavePath.isEmpty {
                        if case .inaccessible = DocumentExporter.checkSaveDirectoryStatus() {
                            Text("접근 불가")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1), in: Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                )

                // 폴더 선택 버튼
                Button {
                    pickFolder()
                } label: {
                    Label("선택", systemImage: "folder.badge.plus")
                        .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundColor(palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.accent.opacity(0.1), in: Capsule())

                // 초기화 버튼
                if !documentSavePath.isEmpty {
                    Button {
                        documentSavePath = ""
                        UserDefaults.standard.removeObject(forKey: "documentSaveDirectory")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(palette.textSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("저장 경로 초기화 (매번 위치 묻기)")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surfaceSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
        )
    }

    private var saveDirectoryIcon: String {
        if documentSavePath.isEmpty { return "questionmark.folder" }
        if case .inaccessible = DocumentExporter.checkSaveDirectoryStatus() {
            return "exclamationmark.triangle.fill"
        }
        return "folder.fill"
    }

    private var saveDirectoryIconColor: Color {
        if documentSavePath.isEmpty { return palette.textSecondary.opacity(0.5) }
        if case .inaccessible = DocumentExporter.checkSaveDirectoryStatus() {
            return .red
        }
        return palette.accent
    }

    private var displayPath: String {
        if documentSavePath.isEmpty { return "미설정" }
        // ~/... 형태로 축약
        let home = NSHomeDirectory()
        if documentSavePath.hasPrefix(home) {
            return "~" + documentSavePath.dropFirst(home.count)
        }
        return documentSavePath
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "문서를 저장할 기본 폴더를 선택하세요"
        panel.prompt = "선택"

        if !documentSavePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: documentSavePath)
        } else if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = docsURL
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        documentSavePath = url.path
        UserDefaults.standard.set(url.path, forKey: "documentSaveDirectory")

        // Security Bookmark 저장 (앱 재시작 후에도 폴더 접근 권한 유지)
        if let bookmarkData = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmarkData, forKey: "documentSaveDirectoryBookmark")
        }
    }

    // MARK: - 소프트웨어 업데이트

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("소프트웨어 업데이트", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Toggle("앱 시작 시 자동으로 업데이트 확인", isOn: $updateManager.autoCheckEnabled)
                .font(.system(size: 12))
                .foregroundColor(palette.textPrimary)
                .toggleStyle(.switch)
                .controlSize(.small)

            HStack(spacing: 8) {
                Button {
                    Task {
                        try? await updateManager.checkForUpdate()
                        if updateManager.isUpdateAvailable {
                            showingUpdateAlert = true
                        } else if updateManager.lastError == nil {
                            withAnimation { showNoUpdateToast = true }
                        }
                    }
                } label: {
                    if updateManager.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("업데이트 확인", systemImage: "arrow.clockwise")
                            .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.accent.opacity(0.1), in: Capsule())
                .disabled(updateManager.isChecking)

                if let error = updateManager.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Text("현재 버전: \(updateManager.appVersion)")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surfaceSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
        )
    }

    private var noUpdateToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("최신 버전입니다")
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(palette.background)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .padding(.top, 8)
    }

    // MARK: - Hook 설정

    private var hookSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hook", systemImage: "bolt.circle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Text("특정 이벤트 발생 시 자동으로 실행할 동작을 설정합니다.")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)

            // 등록된 Hook 목록
            if hookManager.hooks.isEmpty {
                Text("등록된 Hook이 없습니다")
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSecondary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(hookManager.hooks) { hook in
                        HStack(spacing: 8) {
                            Image(systemName: hook.trigger.icon)
                                .font(.system(size: 11))
                                .foregroundColor(hook.isEnabled ? palette.accent : palette.textSecondary.opacity(0.4))
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(hook.name)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(hook.isEnabled ? palette.textPrimary : palette.textSecondary.opacity(0.5))
                                Text("\(hook.trigger.displayName) → \(hook.action.displayName)")
                                    .font(.system(size: 10))
                                    .foregroundColor(palette.textSecondary.opacity(0.7))
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { hook.isEnabled },
                                set: { _ in hookManager.toggleHook(id: hook.id) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            Button {
                                hookManager.removeHook(id: hook.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(palette.textSecondary.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.inputBackground)
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                // 템플릿에서 추가
                Menu {
                    ForEach(UserHook.templates, id: \.name) { template in
                        Button(template.name) {
                            hookManager.installTemplate(template)
                        }
                    }
                } label: {
                    Label("템플릿 추가", systemImage: "plus.circle")
                        .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundColor(palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.accent.opacity(0.1), in: Capsule())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surfaceSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - 안전 규칙 설정

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("안전 규칙", systemImage: "shield.checkered")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Text("에이전트의 명령 실행을 제한합니다. 시스템 기본 규칙(rm -rf, fork bomb 등)은 항상 차단됩니다.")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)

            // 프로젝트 규칙 목록
            let rules = SafetyRuleStore.loadRules()
            if rules.isEmpty {
                Text("프로젝트 규칙이 없습니다 (시스템 기본 규칙만 적용)")
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSecondary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(rules) { rule in
                        HStack(spacing: 8) {
                            Text(rule.risk.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(rule.risk == .block ? .red : .orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (rule.risk == .block ? Color.red : Color.orange).opacity(0.1),
                                    in: Capsule()
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.pattern)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(palette.textPrimary)
                                Text(rule.reason)
                                    .font(.system(size: 10))
                                    .foregroundColor(palette.textSecondary)
                            }

                            Spacer()

                            Button {
                                SafetyRuleStore.removeRule(id: rule.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(palette.textSecondary.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.inputBackground)
                        )
                    }
                }
            }

            Button {
                showAddSafetyRuleSheet = true
            } label: {
                Label("규칙 추가", systemImage: "plus.circle")
                    .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundColor(palette.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(palette.accent.opacity(0.1), in: Capsule())
            .sheet(isPresented: $showAddSafetyRuleSheet) {
                AddSafetyRuleSheet(isPresented: $showAddSafetyRuleSheet)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surfaceSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - 안전 규칙 추가 시트

struct AddSafetyRuleSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.colorPalette) private var palette
    @State private var pattern = ""
    @State private var reason = ""
    @State private var risk: CommandRisk = .block

    var body: some View {
        VStack(spacing: 16) {
            Text("안전 규칙 추가")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("차단 패턴 (정규식)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.textSecondary)
                TextField("예: production|DROP TABLE", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("사유")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.textSecondary)
                TextField("예: 프로덕션 환경 접근 금지", text: $reason)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            Picker("위험도", selection: $risk) {
                Text("차단").tag(CommandRisk.block)
                Text("확인 필요").tag(CommandRisk.confirm)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("취소") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundColor(palette.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(palette.surfaceSecondary.opacity(0.6), in: Capsule())

                Spacer()

                Button("추가") {
                    guard !pattern.isEmpty, !reason.isEmpty else { return }
                    SafetyRuleStore.addRule(SafetyRule(pattern: pattern, risk: risk, reason: reason))
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(pattern.isEmpty || reason.isEmpty ? Color.gray : palette.accent, in: Capsule())
                .disabled(pattern.isEmpty || reason.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(palette.background)
    }
}
