import Foundation
import os.log
import AppKit

private let logger = Logger(subsystem: "com.douglas.app", category: "UpdateManager")

/// Public Gist 기반 자동 업데이트 매니저
@MainActor
final class UpdateManager: ObservableObject {

    // MARK: - Published 상태

    @Published private(set) var latestVersion: VersionInfo?
    @Published private(set) var isUpdateAvailable = false
    @Published private(set) var isChecking = false
    @Published private(set) var lastError: String?

    @Published var autoCheckEnabled: Bool {
        didSet { defaults.set(autoCheckEnabled, forKey: Keys.autoCheckEnabled) }
    }

    // MARK: - Configuration

    /// 버전 정보 JSON URL (Public Gist)
    /// TODO: 실제 Gist 생성 후 URL 교체
    static let versionURL = "https://gist.githubusercontent.com/thefarmersfront/YOUR_GIST_ID/raw/douglas-version.json"

    private let defaults: UserDefaults
    private let currentVersion: String
    private let session: URLSession

    // MARK: - Keys

    private enum Keys {
        static let skippedVersion = "skippedUpdateVersion"
        static let autoCheckEnabled = "autoUpdateCheckEnabled"
        static let lastCheckDate = "lastUpdateCheckDate"
    }

    // MARK: - Init

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String? = nil,
        session: URLSession = .shared
    ) {
        self.defaults = defaults
        self.session = session

        // Info.plist에서 현재 버전 읽기, 없으면 "1.0.0"
        self.currentVersion = currentVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0.0"

        self.autoCheckEnabled = defaults.object(forKey: Keys.autoCheckEnabled) as? Bool ?? true
    }

    // MARK: - Public API

    /// 건너뛴 버전
    var skippedVersion: String? {
        defaults.string(forKey: Keys.skippedVersion)
    }

    /// 버전 건너뛰기 설정
    func skipVersion(_ version: String) {
        let normalized = normalizeVersion(version)
        defaults.set(normalized, forKey: Keys.skippedVersion)
    }

    /// 해당 버전에 대해 업데이트 알림을 표시해야 하는지
    func shouldShowUpdate(for version: String) -> Bool {
        let normalized = normalizeVersion(version)
        return normalized != skippedVersion
    }

    /// 버전 비교: remote가 local보다 새로운지
    func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let r = normalizeVersion(remote)
        let l = normalizeVersion(local)
        return r.compare(l, options: .numeric) == .orderedDescending
    }

    /// Gist에서 최신 버전 정보 확인
    func checkForUpdate() async throws {
        guard !isChecking else { return }

        isChecking = true
        lastError = nil
        defer { isChecking = false }

        guard let url = URL(string: Self.versionURL) else {
            logger.error("잘못된 버전 URL: \(Self.versionURL)")
            lastError = "잘못된 버전 URL입니다."
            return
        }

        var request = URLRequest(url: url)
        request.setValue("DOUGLAS-App/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        // 캐시 무시 (항상 최신 버전 확인)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("잘못된 HTTP 응답")
                lastError = "서버 응답을 처리할 수 없습니다."
                return
            }

            // 404 = 버전 정보 없음 (정상 상황)
            if httpResponse.statusCode == 404 {
                logger.info("버전 정보 없음 (404)")
                return
            }

            // 다른 에러 상태 코드
            guard (200...299).contains(httpResponse.statusCode) else {
                logger.error("HTTP 에러: \(httpResponse.statusCode)")
                lastError = "서버 에러 (\(httpResponse.statusCode))"
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let versionInfo = try decoder.decode(VersionInfo.self, from: data)
            self.latestVersion = versionInfo

            let remoteVersion = versionInfo.version
            self.isUpdateAvailable = isNewerVersion(remoteVersion, than: currentVersion)
                && shouldShowUpdate(for: remoteVersion)

            defaults.set(Date(), forKey: Keys.lastCheckDate)

            logger.info("업데이트 확인 완료: 현재=\(self.currentVersion), 최신=\(remoteVersion), 업데이트필요=\(self.isUpdateAvailable)")

        } catch let error as DecodingError {
            logger.error("JSON 파싱 실패: \(error.localizedDescription)")
            lastError = "버전 정보를 파싱할 수 없습니다."
        } catch {
            logger.error("업데이트 확인 실패: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// 다운로드 페이지 열기
    func openDownloadPage() {
        guard let versionInfo = latestVersion,
              let url = URL(string: versionInfo.downloadURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 현재 앱 버전
    var appVersion: String {
        currentVersion
    }

    // MARK: - Private

    private func normalizeVersion(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }
}
