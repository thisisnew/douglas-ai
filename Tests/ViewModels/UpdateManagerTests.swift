import Testing
import Foundation
@testable import DOUGLAS

@Suite("UpdateManager Tests")
@MainActor
struct UpdateManagerTests {

    // MARK: - 버전 비교 테스트

    @Test("isNewerVersion - 새 버전 감지")
    func compareVersionsNewerAvailable() {
        let defaults = makeTestDefaults()
        let manager = UpdateManager(defaults: defaults)
        #expect(manager.isNewerVersion("1.1.0", than: "1.0.0") == true)
        #expect(manager.isNewerVersion("2.0.0", than: "1.9.9") == true)
        #expect(manager.isNewerVersion("1.0.1", than: "1.0.0") == true)
    }

    @Test("isNewerVersion - 같거나 이전 버전")
    func compareVersionsSameOrOlder() {
        let defaults = makeTestDefaults()
        let manager = UpdateManager(defaults: defaults)
        #expect(manager.isNewerVersion("1.0.0", than: "1.0.0") == false)
        #expect(manager.isNewerVersion("0.9.0", than: "1.0.0") == false)
    }

    @Test("isNewerVersion - v 접두사 처리")
    func compareVersionsWithPrefix() {
        let defaults = makeTestDefaults()
        let manager = UpdateManager(defaults: defaults)
        #expect(manager.isNewerVersion("v1.1.0", than: "1.0.0") == true)
        #expect(manager.isNewerVersion("v1.0.0", than: "v1.0.0") == false)
        #expect(manager.isNewerVersion("1.1.0", than: "v1.0.0") == true)
    }

    // MARK: - 건너뛰기 버전 테스트

    @Test("skippedVersion - 기본값 nil")
    func skippedVersionDefault() {
        let defaults = makeTestDefaults()
        let manager = UpdateManager(defaults: defaults)
        #expect(manager.skippedVersion == nil)
    }

    @Test("skipVersion - 버전 저장")
    func skipVersionSaves() {
        let defaults = makeTestDefaults()
        let manager = UpdateManager(defaults: defaults)
        manager.skipVersion("1.2.0")
        #expect(manager.skippedVersion == "1.2.0")

        // 영속화 확인
        let manager2 = UpdateManager(defaults: defaults)
        #expect(manager2.skippedVersion == "1.2.0")
    }

    @Test("skipVersion - v 접두사 정규화")
    func skipVersionNormalizesPrefix() {
        let defaults = makeTestDefaults()
        let manager = UpdateManager(defaults: defaults)
        manager.skipVersion("v1.2.0")
        #expect(manager.skippedVersion == "1.2.0")
    }

    @Test("shouldShowUpdate - 건너뛴 버전 제외")
    func shouldShowUpdateSkipped() {
        let defaults = makeTestDefaults()
        let manager = UpdateManager(defaults: defaults)
        manager.skipVersion("1.2.0")

        #expect(manager.shouldShowUpdate(for: "1.2.0") == false)
        #expect(manager.shouldShowUpdate(for: "v1.2.0") == false)
        #expect(manager.shouldShowUpdate(for: "1.3.0") == true)
    }

    // MARK: - 자동 확인 설정 테스트

    @Test("autoCheckEnabled - 기본값 true")
    func autoCheckEnabledDefault() {
        let defaults = makeTestDefaults()
        let manager = UpdateManager(defaults: defaults)
        #expect(manager.autoCheckEnabled == true)
    }

    @Test("autoCheckEnabled - 토글 영속화")
    func autoCheckEnabledPersistence() {
        let defaults = makeTestDefaults()
        let manager = UpdateManager(defaults: defaults)
        manager.autoCheckEnabled = false

        let manager2 = UpdateManager(defaults: defaults)
        #expect(manager2.autoCheckEnabled == false)
    }

    // MARK: - HTTP 응답 파싱 테스트

    @Test("checkForUpdate - 성공 시 버전 정보 파싱")
    func checkForUpdateSuccess() async throws {
        let mockJSON = """
        {
            "version": "1.2.0",
            "name": "버전 1.2.0",
            "releaseNotes": "## 변경사항\\n- 새로운 기능 추가",
            "downloadURL": "https://example.com/download/DOUGLAS.dmg",
            "publishedAt": "2024-01-15T10:00:00Z"
        }
        """

        let (session, testID) = makeMockSession { _ in
            return (
                mockHTTPResponse(statusCode: 200),
                Data(mockJSON.utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let defaults = makeTestDefaults()
        let manager = UpdateManager(
            defaults: defaults,
            currentVersion: "1.0.0",
            session: session
        )

        try await manager.checkForUpdate()

        #expect(manager.latestVersion != nil)
        #expect(manager.latestVersion?.version == "1.2.0")
        #expect(manager.isUpdateAvailable == true)
    }

    @Test("checkForUpdate - 현재 버전이 최신이면 업데이트 없음")
    func checkForUpdateNoUpdate() async throws {
        let mockJSON = """
        {
            "version": "1.0.0",
            "name": "버전 1.0.0",
            "releaseNotes": "초기 릴리스",
            "downloadURL": "https://example.com/download/DOUGLAS.dmg",
            "publishedAt": "2024-01-15T10:00:00Z"
        }
        """

        let (session, testID) = makeMockSession { _ in
            return (
                mockHTTPResponse(statusCode: 200),
                Data(mockJSON.utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let defaults = makeTestDefaults()
        let manager = UpdateManager(
            defaults: defaults,
            currentVersion: "1.0.0",
            session: session
        )

        try await manager.checkForUpdate()

        #expect(manager.latestVersion != nil)
        #expect(manager.isUpdateAvailable == false)
    }

    @Test("checkForUpdate - 건너뛴 버전은 업데이트 표시 안 함")
    func checkForUpdateSkippedVersion() async throws {
        let mockJSON = """
        {
            "version": "1.2.0",
            "name": "버전 1.2.0",
            "releaseNotes": "새 기능",
            "downloadURL": "https://example.com/download/DOUGLAS.dmg",
            "publishedAt": "2024-01-15T10:00:00Z"
        }
        """

        let (session, testID) = makeMockSession { _ in
            return (
                mockHTTPResponse(statusCode: 200),
                Data(mockJSON.utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let defaults = makeTestDefaults()
        let manager = UpdateManager(
            defaults: defaults,
            currentVersion: "1.0.0",
            session: session
        )
        manager.skipVersion("1.2.0")

        try await manager.checkForUpdate()

        #expect(manager.latestVersion != nil)
        #expect(manager.isUpdateAvailable == false)
    }

    @Test("checkForUpdate - 404 에러 시 무시")
    func checkForUpdate404() async throws {
        let (session, testID) = makeMockSession { _ in
            return (
                mockHTTPResponse(statusCode: 404),
                Data("{\"error\":\"Not Found\"}".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let defaults = makeTestDefaults()
        let manager = UpdateManager(
            defaults: defaults,
            currentVersion: "1.0.0",
            session: session
        )

        // 에러 없이 완료되어야 함
        try await manager.checkForUpdate()
        #expect(manager.latestVersion == nil)
        #expect(manager.isUpdateAvailable == false)
    }

    @Test("checkForUpdate - 네트워크 에러 시 lastError 설정")
    func checkForUpdateNetworkError() async throws {
        let (session, testID) = makeMockSession { _ in
            return (
                mockHTTPResponse(statusCode: 500),
                Data("{\"error\":\"Internal Server Error\"}".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let defaults = makeTestDefaults()
        let manager = UpdateManager(
            defaults: defaults,
            currentVersion: "1.0.0",
            session: session
        )

        try await manager.checkForUpdate()
        #expect(manager.lastError != nil)
    }
}
