import SwiftUI

struct AddProviderSheet: View {
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

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            ZStack {
                Text("API 설정")
                    .font(.headline)
                HStack {
                    Spacer()
                    Button("완료") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

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
                                    Text("GPT-4o, GPT-4o-mini")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                testResultBadge(for: .openAI)
                            }

                            SecureField("API Key (sk-...)", text: $openAIKey)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)
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
                                    Text("Gemini 2.0 Flash, Pro")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                testResultBadge(for: .google)
                            }

                            SecureField("API Key (AIza...)", text: $googleKey)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)
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
                                    Text("티켓 조회 · web_fetch 자동 인증")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                jiraTestBadge
                            }

                            TextField("도메인 (company.atlassian.net)", text: $jiraDomain)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)

                            TextField("이메일", text: $jiraEmail)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)

                            SecureField("API Token", text: $jiraToken)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)

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
        .frame(width: 460, height: 680)
    }

    // MARK: - Components

    private func providerCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(10)
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
                .cornerRadius(4)
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
                .cornerRadius(4)
        }
    }

    // MARK: - Logic

    private func saveKey(_ type: ProviderType, key: String) {
        if var config = providerManager.configs.first(where: { $0.type == type }) {
            config.apiKey = key
            providerManager.updateConfig(config)
            testResults[type] = "저장 완료"
        }
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
        let cleanToken = jiraToken.trimmingCharacters(in: .whitespacesAndNewlines)
        var config = JiraConfig(domain: cleanDomain, email: jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines))
        config.apiToken = cleanToken
        JiraConfig.shared = config
        jiraTestResult = "저장 완료"
    }

    private func testJira() {
        isTestingJira = true
        jiraTestResult = nil

        // 도메인 정규화: https://, http://, 후행 슬래시 제거
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
            jiraTestResult = "잘못된 도메인"
            isTestingJira = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let displayName = json["displayName"] as? String {
                    jiraTestResult = "성공 · \(displayName)"
                } else {
                    jiraTestResult = "실패 (HTTP \(status))"
                }
            } catch {
                jiraTestResult = "실패"
            }
            isTestingJira = false
        }
    }
}
