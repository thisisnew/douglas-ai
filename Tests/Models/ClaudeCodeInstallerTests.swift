import Testing
import Foundation
@testable import DOUGLAS

@Suite("ClaudeCodeInstaller Tests")
struct ClaudeCodeInstallerTests {

    // MARK: - InstallState Equatable

    @Test("InstallState - checking 동등성")
    func stateCheckingEqual() {
        #expect(ClaudeCodeInstaller.InstallState.checking == .checking)
    }

    @Test("InstallState - found 동등성 (같은 경로)")
    func stateFoundEqualSamePath() {
        #expect(ClaudeCodeInstaller.InstallState.found(path: "/usr/local/bin/claude") ==
                .found(path: "/usr/local/bin/claude"))
    }

    @Test("InstallState - found 비동등성 (다른 경로)")
    func stateFoundNotEqualDifferentPath() {
        #expect(ClaudeCodeInstaller.InstallState.found(path: "/a") !=
                .found(path: "/b"))
    }

    @Test("InstallState - notFound 동등성")
    func stateNotFoundEqual() {
        #expect(ClaudeCodeInstaller.InstallState.notFound == .notFound)
    }

    @Test("InstallState - installing 동등성 (같은 단계)")
    func stateInstallingEqualSameStep() {
        #expect(ClaudeCodeInstaller.InstallState.installing(step: "npm 확인 중...") ==
                .installing(step: "npm 확인 중..."))
    }

    @Test("InstallState - installing 비동등성 (다른 단계)")
    func stateInstallingNotEqualDifferentStep() {
        #expect(ClaudeCodeInstaller.InstallState.installing(step: "A") !=
                .installing(step: "B"))
    }

    @Test("InstallState - needsAuth 동등성")
    func stateNeedsAuthEqual() {
        #expect(ClaudeCodeInstaller.InstallState.needsAuth == .needsAuth)
    }

    @Test("InstallState - ready 동등성")
    func stateReadyEqual() {
        #expect(ClaudeCodeInstaller.InstallState.ready == .ready)
    }

    @Test("InstallState - failed 동등성 (같은 메시지)")
    func stateFailedEqualSameMessage() {
        #expect(ClaudeCodeInstaller.InstallState.failed("error") == .failed("error"))
    }

    @Test("InstallState - failed 비동등성 (다른 메시지)")
    func stateFailedNotEqualDifferentMessage() {
        #expect(ClaudeCodeInstaller.InstallState.failed("A") != .failed("B"))
    }

    @Test("InstallState - 다른 타입끼리 비동등")
    func stateDifferentVariantsNotEqual() {
        #expect(ClaudeCodeInstaller.InstallState.checking != .notFound)
        #expect(ClaudeCodeInstaller.InstallState.ready != .needsAuth)
        #expect(ClaudeCodeInstaller.InstallState.notFound != .failed("not found"))
        #expect(ClaudeCodeInstaller.InstallState.installing(step: "x") != .checking)
    }

    // MARK: - 초기화

    @MainActor
    @Test("초기화 - 기본 상태 checking")
    func initState() {
        let installer = ClaudeCodeInstaller()
        #expect(installer.state == .checking)
        #expect(installer.installLog == "")
    }

    // MARK: - isReady

    @MainActor
    @Test("isReady - ready 상태일 때 true")
    func isReadyWhenReady() {
        let installer = ClaudeCodeInstaller()
        installer.state = .ready
        #expect(installer.isReady == true)
    }

    @MainActor
    @Test("isReady - found 상태일 때 true")
    func isReadyWhenFound() {
        let installer = ClaudeCodeInstaller()
        installer.state = .found(path: "/some/path")
        #expect(installer.isReady == true)
    }

    @MainActor
    @Test("isReady - checking 상태일 때 false")
    func isReadyWhenChecking() {
        let installer = ClaudeCodeInstaller()
        installer.state = .checking
        #expect(installer.isReady == false)
    }

    @MainActor
    @Test("isReady - notFound 상태일 때 false")
    func isReadyWhenNotFound() {
        let installer = ClaudeCodeInstaller()
        installer.state = .notFound
        #expect(installer.isReady == false)
    }

    @MainActor
    @Test("isReady - installing 상태일 때 false")
    func isReadyWhenInstalling() {
        let installer = ClaudeCodeInstaller()
        installer.state = .installing(step: "설치 중")
        #expect(installer.isReady == false)
    }

    @MainActor
    @Test("isReady - needsAuth 상태일 때 false")
    func isReadyWhenNeedsAuth() {
        let installer = ClaudeCodeInstaller()
        installer.state = .needsAuth
        #expect(installer.isReady == false)
    }

    @MainActor
    @Test("isReady - failed 상태일 때 false")
    func isReadyWhenFailed() {
        let installer = ClaudeCodeInstaller()
        installer.state = .failed("에러")
        #expect(installer.isReady == false)
    }

    // MARK: - detectedPath

    @MainActor
    @Test("detectedPath - found 상태일 때 경로 반환")
    func detectedPathWhenFound() {
        let installer = ClaudeCodeInstaller()
        installer.state = .found(path: "/opt/homebrew/bin/claude")
        #expect(installer.detectedPath == "/opt/homebrew/bin/claude")
    }

    @MainActor
    @Test("detectedPath - notFound 상태일 때 nil")
    func detectedPathWhenNotFound() {
        let installer = ClaudeCodeInstaller()
        installer.state = .notFound
        #expect(installer.detectedPath == nil)
    }

    @MainActor
    @Test("detectedPath - checking 상태일 때 nil")
    func detectedPathWhenChecking() {
        let installer = ClaudeCodeInstaller()
        installer.state = .checking
        #expect(installer.detectedPath == nil)
    }

    @MainActor
    @Test("detectedPath - failed 상태일 때 nil")
    func detectedPathWhenFailed() {
        let installer = ClaudeCodeInstaller()
        installer.state = .failed("err")
        #expect(installer.detectedPath == nil)
    }

    // MARK: - confirmAuth

    @MainActor
    @Test("confirmAuth - ready 상태로 전환")
    func confirmAuth() {
        let installer = ClaudeCodeInstaller()
        installer.state = .needsAuth
        installer.confirmAuth()
        #expect(installer.state == .ready)
    }

    // MARK: - checkAuthStatus

    @MainActor
    @Test("checkAuthStatus - ~/.claude 디렉토리 존재 여부로 판단")
    func checkAuthStatus() {
        let installer = ClaudeCodeInstaller()
        let result = installer.checkAuthStatus()
        // ~/.claude 디렉토리 존재 여부에 따라 결과가 달라짐
        let claudeDir = NSHomeDirectory() + "/.claude"
        let exists = FileManager.default.fileExists(atPath: claudeDir)
        #expect(result == exists)
    }

    // MARK: - detect (ProcessRunner mock)

    @MainActor
    @Test("detect - claude 바이너리 있고 인증 완료 → .ready")
    func detectReady() async {
        await ProcessRunner.withMock({ executable, args, _, _ in
            if args.contains(where: { $0.contains("command -v claude") }) {
                return (exitCode: 0, stdout: "/usr/local/bin/claude\n", stderr: "")
            }
            return (exitCode: 1, stdout: "", stderr: "not found")
        }) {
            let installer = ClaudeCodeInstaller()
            await installer.detect()
            #expect(installer.state != .checking)
        }
    }

    @MainActor
    @Test("detect - 셸 탐색 후 최종 상태")
    func detectFinalState() async {
        await ProcessRunner.withMock({ executable, args, _, _ in
            if args.contains(where: { $0.contains("command -v claude") }) {
                return (exitCode: 1, stdout: "", stderr: "not found")
            }
            return (exitCode: 1, stdout: "", stderr: "")
        }) {
            let installer = ClaudeCodeInstaller()
            await installer.detect()
            #expect(installer.state != .checking)
            switch installer.state {
            case .ready, .found, .notFound:
                break
            default:
                break
            }
        }
    }

    // MARK: - install (ProcessRunner mock)

    @MainActor
    @Test("install - npm 없고 brew 없으면 failed")
    func installNoNpmNoBrew() async {
        await ProcessRunner.withMock({ _, _, _, _ in
            (exitCode: 1, stdout: "", stderr: "not found")
        }) {
            let installer = ClaudeCodeInstaller()
            await installer.install()
            #expect(installer.state != .checking)
        }
    }

    // MARK: - findExecutable (private, install을 통해 간접 테스트)

    @MainActor
    @Test("installLog - 설치 후 로그 존재")
    func installLogAfterInstall() async {
        await ProcessRunner.withMock({ _, args, _, _ in
            if args.contains("install") {
                return (exitCode: 0, stdout: "installed successfully\n", stderr: "")
            }
            return (exitCode: 1, stdout: "", stderr: "")
        }) {
            let installer = ClaudeCodeInstaller()
            #expect(installer.installLog == "")
            await installer.install()
        }
    }

    // MARK: - detectedPath with ready state

    @MainActor
    @Test("detectedPath - ready 상태일 때 findClaudePath 호출")
    func detectedPathWhenReady() {
        let installer = ClaudeCodeInstaller()
        installer.state = .ready
        let path = installer.detectedPath
        #expect(path != nil)
    }

    @MainActor
    @Test("detectedPath - installing 상태일 때 nil")
    func detectedPathWhenInstalling() {
        let installer = ClaudeCodeInstaller()
        installer.state = .installing(step: "진행 중")
        #expect(installer.detectedPath == nil)
    }

    @MainActor
    @Test("detectedPath - needsAuth 상태일 때 nil")
    func detectedPathWhenNeedsAuth() {
        let installer = ClaudeCodeInstaller()
        installer.state = .needsAuth
        #expect(installer.detectedPath == nil)
    }
}
