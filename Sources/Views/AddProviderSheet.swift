import SwiftUI

struct AddProviderSheet: View {
    var isEmbedded = false

    @Environment(\.colorPalette) private var palette
    @EnvironmentObject var providerManager: ProviderManager
    @Environment(\.dismiss) private var dismiss

    @State private var openAIKey = ""
    @State private var googleKey = ""
    @State private var testResults: [ProviderType: String] = [:]
    @State private var isTesting: [ProviderType: Bool] = [:]

    // Jira
    @State private var jiraDomain = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jiraTestResult: String?
    @State private var isTestingJira = false
    @State private var showJiraToken = false


    var body: some View {
        VStack(spacing: 0) {
            if !isEmbedded {
                SheetNavHeader(title: "API 설정") {
                    EmptyView()
                } trailing: {
                    Button("완료") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.plain)
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.userBubbleText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(palette.accent, in: Capsule())
                        .contentShape(Capsule())
                }
            }

            ScrollView {
                VStack(spacing: 20) {
                    // Claude Code
                    providerCard {
                        HStack(spacing: 12) {
                            providerIcon("terminal", color: .purple)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Claude Code")
                                    .font(.body.weight(.medium))
                                if let config = providerManager.configs.first(where: { $0.type == .claudeCode }) {
                                    Text(config.baseURL)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Label("연결됨", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Label("미설치", systemImage: "xmark.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }

                    // OpenAI
                    providerCard {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                providerIcon("brain", color: .green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("OpenAI")
                                        .font(.body.weight(.medium))
                                    if hasValidKey(.openAI) {
                                        Label("연동됨", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                                Spacer()
                                testResultBadge(for: .openAI)
                            }

                            SecureField("API Key (sk-...)", text: $openAIKey)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(10)
                                .background(palette.inputBackground)
                                .continuousRadius(DesignTokens.CozyGame.cardRadius)
                                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))
                                .onAppear {
                                    openAIKey = providerManager.configs.first(where: { $0.type == .openAI })?.apiKey ?? ""
                                }

                            HStack(spacing: 8) {
                                Spacer()
                                Button("테스트") { testProvider(.openAI) }
                                    .controlSize(.small)
                                    .disabled(openAIKey.isEmpty || isTesting[.openAI] == true)
                                Button("저장") { saveKey(.openAI, key: openAIKey) }
                                    .controlSize(.small)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(openAIKey.isEmpty)
                            }
                        }
                    }

                    // Google
                    providerCard {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                providerIcon("sparkle", color: .blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Google Gemini")
                                        .font(.body.weight(.medium))
                                    if hasValidKey(.google) {
                                        Label("연동됨", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                                Spacer()
                                testResultBadge(for: .google)
                            }

                            SecureField("API Key (AIza...)", text: $googleKey)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(10)
                                .background(palette.inputBackground)
                                .continuousRadius(DesignTokens.CozyGame.cardRadius)
                                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))
                                .onAppear {
                                    googleKey = providerManager.configs.first(where: { $0.type == .google })?.apiKey ?? ""
                                }

                            HStack(spacing: 8) {
                                Spacer()
                                Button("테스트") { testProvider(.google) }
                                    .controlSize(.small)
                                    .disabled(googleKey.isEmpty || isTesting[.google] == true)
                                Button("저장") { saveKey(.google, key: googleKey) }
                                    .controlSize(.small)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(googleKey.isEmpty)
                            }
                        }
                    }

                    // Jira
                    providerCard {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                providerIcon("link.circle", color: .blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Jira Cloud")
                                        .font(.body.weight(.medium))
                                    if JiraConfig.shared.isConfigured {
                                        Text(JiraConfig.shared.domain)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        Label("연동됨", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("티켓 조회 · web_fetch 자동 인증")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                jiraTestBadge
                            }

                            TextField("도메인 (company.atlassian.net)", text: $jiraDomain)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(palette.inputBackground)
                                .continuousRadius(DesignTokens.CozyGame.cardRadius)
                                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))

                            TextField("이메일", text: $jiraEmail)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(palette.inputBackground)
                                .continuousRadius(DesignTokens.CozyGame.cardRadius)
                                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))

                            HStack(spacing: 0) {
                                Group {
                                    if showJiraToken {
                                        TextField("API Token", text: $jiraToken)
                                    } else {
                                        SecureField("API Token", text: $jiraToken)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.tail)

                                Button {
                                    showJiraToken.toggle()
                                } label: {
                                    Image(systemName: showJiraToken ? "eye.slash" : "eye")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(palette.inputBackground)
                            .continuousRadius(DesignTokens.CozyGame.cardRadius)
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))

                            if !jiraToken.isEmpty {
                                Text("\(jiraToken.count)자")
                                    .font(.caption2)
                                    .foregroundColor(jiraToken.count < 170 ? .orange : .secondary)
                            }

                            HStack(spacing: 8) {
                                Spacer()
                                Button("테스트") { testJira() }
                                    .controlSize(.small)
                                    .disabled(jiraDomain.isEmpty || jiraEmail.isEmpty || jiraToken.isEmpty || isTestingJira)
                                Button("저장") { saveJira() }
                                    .controlSize(.small)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(jiraDomain.isEmpty || jiraEmail.isEmpty || jiraToken.isEmpty)
                            }
                        }
                    }
                    .onAppear { loadJiraConfig() }
                }
                .padding(24)
            }
        }
        .frame(
            width: isEmbedded ? nil : DesignTokens.WindowSize.providerSheet.width,
            height: isEmbedded ? nil : DesignTokens.WindowSize.providerSheet.height
        )
        .frame(maxWidth: isEmbedded ? .infinity : nil, maxHeight: isEmbedded ? .infinity : nil)
    }

    // MARK: - Components

    private func providerCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(palette.surfaceTertiary)
            .continuousRadius(DesignTokens.Radius.xl)
    }

    private func providerIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.title3)
            .foregroundColor(color)
            .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private func testResultBadge(for type: ProviderType) -> some View {
        if isTesting[type] == true {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        } else if let result = testResults[type] {
            Text(result)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(result.contains("성공") || result.contains("완료") ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .foregroundColor(result.contains("성공") || result.contains("완료") ? .green : .red)
                .continuousRadius(DesignTokens.Radius.sm)
        }
    }

    @ViewBuilder
    private var jiraTestBadge: some View {
        if isTestingJira {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        } else if let result = jiraTestResult {
            Text(result)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(result.contains("성공") || result.contains("완료") ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .foregroundColor(result.contains("성공") || result.contains("완료") ? .green : .red)
                .continuousRadius(DesignTokens.Radius.sm)
        }
    }

    // MARK: - Logic

    private func hasValidKey(_ type: ProviderType) -> Bool {
        // 테스트 성공 시에만 "연동됨" 표시
        guard let result = testResults[type] else { return false }
        return result.contains("성공")
    }

    private func saveKey(_ type: ProviderType, key: String) {
        if var config = providerManager.configs.first(where: { $0.type == type }) {
            config.apiKey = key
            providerManager.updateConfig(config)
        }
        // 저장 후 자동 테스트
        testProvider(type)
    }

    private func testProvider(_ type: ProviderType) {
        isTesting[type] = true
        testResults[type] = nil

        let key = type == .openAI ? openAIKey : googleKey
        guard var config = providerManager.configs.first(where: { $0.type == type }) else {
            testResults[type] = "설정 없음"
            isTesting[type] = false
            return
        }
        config.apiKey = key
        let provider = providerManager.createProvider(from: config)

        Task {
            do {
                let models = try await provider.fetchModels()
                testResults[type] = "성공 · \(models.count)개 모델"
            } catch let error as AIProviderError {
                switch error {
                case .noAPIKey: testResults[type] = "키 없음"
                case .httpError(let code, _) where code == 400 || code == 401 || code == 403:
                    testResults[type] = "인증 실패"
                default: testResults[type] = "실패"
                }
            } catch {
                testResults[type] = "실패"
            }
            isTesting[type] = false
        }
    }

    // MARK: - Jira

    private func loadJiraConfig() {
        let config = JiraConfig.shared
        jiraDomain = config.domain
        jiraEmail = config.email
        jiraToken = config.apiToken ?? ""
    }

    private func saveJira() {
        let cleanDomain = jiraDomain
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let cleanEmail = jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = jiraToken.trimmingCharacters(in: .whitespacesAndNewlines)

        var config = JiraConfig(domain: cleanDomain, email: cleanEmail)
        config.apiToken = cleanToken
        JiraConfig.shared = config

        // 저장 확인 — 다시 읽어서 검증
        let saved = JiraConfig.shared
        if saved.domain == cleanDomain && saved.email == cleanEmail && saved.apiToken == cleanToken {
            jiraTestResult = "저장 완료"
        } else if saved.apiToken != cleanToken {
            jiraTestResult = "저장 실패 (토큰 저장 오류)"
        } else {
            jiraTestResult = "저장 실패"
        }
    }

    private func testJira() {
        // 먼저 저장
        saveJira()

        isTestingJira = true
        jiraTestResult = nil

        let cleanDomain = jiraDomain
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let cleanEmail = jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = jiraToken.trimmingCharacters(in: .whitespacesAndNewlines)

        let credentials = "\(cleanEmail):\(cleanToken)"
        let auth = "Basic \(Data(credentials.utf8).base64EncodedString())"
        let urlString = "https://\(cleanDomain)/rest/api/3/myself"

        guard let url = URL(string: urlString) else {
            jiraTestResult = "잘못된 도메인: \(cleanDomain)"
            isTestingJira = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let displayName = json["displayName"] as? String {
                    jiraTestResult = "성공 · \(displayName)"
                } else if status == 401 {
                    jiraTestResult = "인증 실패 — 토큰을 다시 확인하세요 (\(cleanToken.count)자)"
                } else if status == 403 {
                    jiraTestResult = "권한 없음 (HTTP 403)"
                } else {
                    jiraTestResult = "실패 (HTTP \(status))"
                }
            } catch {
                jiraTestResult = "연결 실패: \(error.localizedDescription.prefix(50))"
            }
            isTestingJira = false
        }
    }
}
