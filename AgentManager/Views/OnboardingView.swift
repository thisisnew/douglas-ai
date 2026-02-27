import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @EnvironmentObject var providerManager: ProviderManager
    @EnvironmentObject var agentStore: AgentStore

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 단계 인디케이터
            stepIndicator
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            // 콘텐츠
            switch viewModel.currentStep {
            case .claudeSetup:
                claudeSetupView
            case .providerSelection:
                selectionView
            case .apiKeyInput:
                apiKeyView
            case .complete:
                Color.clear.onAppear { finishOnboarding() }
            }
        }
        .frame(width: 520, height: 560)
        .background(Color.white)
        .task {
            await viewModel.startClaudeSetup()
        }
    }

    // MARK: - 단계 인디케이터

    private var stepIndicator: some View {
        let step: Int = {
            switch viewModel.currentStep {
            case .claudeSetup: return 0
            case .providerSelection: return 1
            case .apiKeyInput: return 2
            case .complete: return 3
            }
        }()

        return HStack(spacing: 8) {
            stepDot(active: true)
            stepLine(active: step >= 1)
            stepDot(active: step >= 1)
            stepLine(active: step >= 2)
            stepDot(active: step >= 2)
        }
    }

    private func stepDot(active: Bool) -> some View {
        Circle()
            .fill(active ? Color.accentColor : Color.black.opacity(0.1))
            .frame(width: 8, height: 8)
    }

    private func stepLine(active: Bool) -> some View {
        Rectangle()
            .fill(active ? Color.accentColor : Color.black.opacity(0.1))
            .frame(width: 40, height: 2)
    }

    // MARK: - Claude Setup 화면

    private var claudeSetupView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // 아이콘
                Image(systemName: "terminal")
                    .font(.system(size: 40))
                    .foregroundColor(.purple)
                    .frame(width: 80, height: 80)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("마스터 에이전트 설정")
                    .font(.title3.bold())

                Text("AgentManager는 Claude Code CLI를\n마스터 에이전트로 사용합니다")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // 의존성 체크리스트
                dependencyChecklist

                // 상태별 UI
                claudeStateContent
            }
            .padding(.horizontal, 40)

            Spacer()

            // 하단 버튼
            claudeSetupButtons
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
    }

    // MARK: - 의존성 체크리스트

    private var dependencyChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("환경 확인")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                if viewModel.dependencyChecker.isChecking {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }

            ForEach(viewModel.dependencyChecker.dependencies) { dep in
                HStack(spacing: 8) {
                    Image(systemName: dep.isFound ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 13))
                        .foregroundColor(dep.isFound ? .green : (dep.isRequired ? .red : .orange))

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(dep.name)
                                .font(.caption)
                            if !dep.isRequired {
                                Text("(선택)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if dep.isFound, let path = dep.foundPath {
                            Text(path)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if !dep.isFound {
                        if let url = dep.downloadURL, let link = URL(string: url) {
                            Link("다운로드", destination: link)
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        } else if let hint = dep.installHint {
                            Text(hint)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var claudeStateContent: some View {
        switch viewModel.claudeInstaller.state {
        case .checking:
            ProgressView()
                .scaleEffect(1.0)
            Text("Claude Code 확인 중...")
                .font(.caption)
                .foregroundColor(.secondary)

        case .found(let path):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            Text("Claude Code가 설치되어 있습니다")
                .font(.callout.weight(.medium))
                .foregroundColor(.green)
            Text(path)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)

        case .notFound:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text("Claude Code가 설치되어 있지 않습니다")
                .font(.callout.weight(.medium))
            Text("자동으로 설치하거나, 건너뛰고 다른 AI를 사용할 수 있습니다")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

        case .installing(let step):
            ProgressView()
                .scaleEffect(1.0)
            Text(step)
                .font(.callout.weight(.medium))
            if !viewModel.claudeInstaller.installLog.isEmpty {
                Text(String(viewModel.claudeInstaller.installLog.suffix(200)))
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

        case .needsAuth:
            Image(systemName: "person.badge.key")
                .font(.system(size: 28))
                .foregroundColor(.blue)
            Text("인증이 필요합니다")
                .font(.callout.weight(.medium))
            Text("터미널에서 `claude` 명령을 한 번 실행하여\nAnthropic 계정으로 로그인해주세요")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            Text("Claude Code 준비 완료!")
                .font(.callout.weight(.medium))
                .foregroundColor(.green)

        case .failed(let message):
            Image(systemName: "xmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.red)
            Text("설치 실패")
                .font(.callout.weight(.medium))
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
    }

    @ViewBuilder
    private var claudeSetupButtons: some View {
        switch viewModel.claudeInstaller.state {
        case .checking:
            EmptyView()

        case .found:
            HStack {
                Spacer()
                Button(action: {
                    Task { await viewModel.finishClaudeSetup() }
                }) {
                    nextButtonLabel("다음")
                }
                .buttonStyle(.plain)
            }

        case .notFound:
            HStack {
                Button("건너뛰기") {
                    Task { await viewModel.skipClaudeSetup() }
                }
                .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    Task { await viewModel.installClaudeCode() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.caption)
                        Text("설치")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

        case .installing:
            EmptyView()

        case .needsAuth:
            HStack {
                Button("건너뛰기") {
                    Task { await viewModel.skipClaudeSetup() }
                }
                .foregroundColor(.secondary)

                Spacer()

                Button("인증 완료") {
                    viewModel.claudeInstaller.confirmAuth()
                    Task { await viewModel.finishClaudeSetup() }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

        case .ready:
            HStack {
                Spacer()
                Button(action: {
                    Task { await viewModel.finishClaudeSetup() }
                }) {
                    nextButtonLabel("다음")
                }
                .buttonStyle(.plain)
            }

        case .failed:
            HStack {
                Button("건너뛰기") {
                    Task { await viewModel.skipClaudeSetup() }
                }
                .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    Task { await viewModel.installClaudeCode() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                        Text("다시 시도")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 선택 화면

    private var selectionView: some View {
        VStack(spacing: 0) {
            // 헤더
            VStack(spacing: 6) {
                if viewModel.claudeSkipped {
                    Text("사용할 AI를 선택하세요")
                        .font(.title3.bold())
                } else {
                    Text("서브 에이전트용 AI 선택")
                        .font(.title3.bold())
                    Text("마스터: Claude Code (자동 설정됨)")
                        .font(.caption)
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if viewModel.isDetecting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !viewModel.detectedProviders.isEmpty {
                    let subDetected = viewModel.detectedProviders.filter { $0.type != .claudeCode }
                    if !subDetected.isEmpty {
                        Text("\(subDetected.count)개의 추가 AI가 감지되었습니다")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 16)

            // 프로바이더 리스트
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(viewModel.allProviderTypes, id: \.self) { type in
                        let detected = viewModel.detectedProviders.first { $0.type == type }
                        providerSelectionRow(type: type, detected: detected)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)

            // 하단 버튼
            HStack {
                Button("나중에 설정") {
                    viewModel.skipOnboarding()
                    onComplete()
                }
                .foregroundColor(.secondary)

                Spacer()

                Button(action: { viewModel.goToNext() }) {
                    nextButtonLabel(viewModel.selectedTypes.isEmpty || (!viewModel.claudeSkipped && viewModel.selectedTypes == [.claudeCode])
                                    ? "건너뛰기" : "다음")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private func providerSelectionRow(type: ProviderType, detected: DetectedProvider?) -> some View {
        let isSelected = viewModel.selectedTypes.contains(type)
        let isMaster = viewModel.masterProviderType == type
        let showMasterSelector = viewModel.claudeSkipped

        return HStack(spacing: 12) {
            // 체크박스
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : Color.black.opacity(0.15))
                .font(.title3)
                .onTapGesture { viewModel.toggleProvider(type) }

            // 아이콘
            providerIcon(type)
                .frame(width: 32, height: 32)

            // 정보
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(detected?.displayName ?? type.rawValue)
                        .font(.callout.weight(.medium))
                    if detected != nil {
                        Text("감지됨")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Text("수동")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(detected?.detail ?? type.label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 마스터 선택 라디오 (Claude 건너뛴 경우에만)
            if showMasterSelector && isSelected {
                Button(action: { viewModel.setMaster(type) }) {
                    HStack(spacing: 4) {
                        Image(systemName: isMaster ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundColor(isMaster ? .orange : .secondary.opacity(0.4))
                        if isMaster {
                            Text("마스터")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("마스터 에이전트로 사용")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.04) : Color.black.opacity(0.02))
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleProvider(type) }
    }

    // MARK: - API 키 입력 화면

    private var apiKeyView: some View {
        VStack(spacing: 0) {
            // 헤더
            VStack(spacing: 6) {
                Text("API 키 설정")
                    .font(.title3.bold())
                Text("선택한 AI의 API 키를 입력하세요")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 16)

            ScrollView {
                VStack(spacing: 16) {
                    // API 키 필요한 것
                    ForEach(viewModel.selectedProvidersNeedingKey, id: \.self) { type in
                        apiKeyCard(type: type)
                    }

                    // 키 불필요한 것
                    if !viewModel.selectedProvidersNoKey.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.selectedProvidersNoKey, id: \.self) { type in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text(type.rawValue)
                                        .font(.caption)
                                    Text("키 불필요")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)

            // 하단 버튼
            HStack {
                Button(action: { viewModel.goBack() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.caption)
                        Text("이전")
                    }
                }
                .foregroundColor(.secondary)

                Spacer()

                Button(action: { viewModel.goToNext() }) {
                    HStack(spacing: 4) {
                        Text("완료")
                        Image(systemName: "checkmark")
                            .font(.caption)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private func apiKeyCard(type: ProviderType) -> some View {
        let detected = viewModel.detectedProviders.first { $0.type == type }
        let hasDetectedKey = detected?.prefilledAPIKey != nil

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                providerIcon(type)
                    .frame(width: 24, height: 24)
                Text(type.rawValue)
                    .font(.callout.weight(.medium))
                Spacer()
                if hasDetectedKey {
                    Text("자동 감지됨")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            if hasDetectedKey {
                // 환경변수로 감지된 키
                HStack(spacing: 8) {
                    Text(detected?.maskedKey ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Toggle("사용", isOn: Binding(
                        get: { viewModel.useDetectedKey[type] ?? true },
                        set: { viewModel.useDetectedKey[type] = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if !(viewModel.useDetectedKey[type] ?? true) {
                    SecureField(keyPlaceholder(type), text: Binding(
                        get: { viewModel.apiKeys[type] ?? "" },
                        set: { viewModel.apiKeys[type] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                // 수동 입력
                SecureField(keyPlaceholder(type), text: Binding(
                    get: { viewModel.apiKeys[type] ?? "" },
                    set: { viewModel.apiKeys[type] = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("나중에 설정할 수 있습니다")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 완료

    private func finishOnboarding() {
        viewModel.apply(providerManager: providerManager, agentStore: agentStore)
        onComplete()
    }

    // MARK: - 헬퍼

    private func nextButtonLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "arrow.right")
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.accentColor)
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func providerIcon(_ type: ProviderType) -> some View {
        let (icon, color): (String, Color) = {
            switch type {
            case .claudeCode: return ("terminal", .purple)
            case .openAI:     return ("brain", .green)
            case .anthropic:  return ("sparkles", .orange)
            case .google:     return ("globe", .blue)
            case .ollama:     return ("desktopcomputer", .teal)
            case .lmStudio:   return ("cpu", .indigo)
            case .custom:     return ("puzzlepiece", .gray)
            }
        }()

        return Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundColor(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func keyPlaceholder(_ type: ProviderType) -> String {
        switch type {
        case .openAI:    return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .google:    return "AIza..."
        default:         return "API Key"
        }
    }
}
