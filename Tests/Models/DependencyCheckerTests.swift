import Testing
import Foundation
@testable import DOUGLAS

@Suite("DependencyChecker Tests")
@MainActor
struct DependencyCheckerTests {

    @Test("init - 기본 의존성 목록 로드")
    func initLoadsDependencies() {
        let checker = DependencyChecker()
        #expect(checker.dependencies.count == 1)
        #expect(checker.dependencies[0].name == "Node.js / npm")
    }

    @Test("allRequiredFound - 모두 미발견 시 false")
    func allRequiredFoundInitiallyFalse() {
        let checker = DependencyChecker()
        #expect(checker.allRequiredFound == false)
    }

    @Test("allRequiredFound - 필수만 발견 시 true")
    func allRequiredFoundWhenRequired() {
        let checker = DependencyChecker()
        for i in checker.dependencies.indices {
            if checker.dependencies[i].isRequired {
                checker.dependencies[i].isFound = true
            }
        }
        #expect(checker.allRequiredFound == true)
    }

    @Test("Node.js - 필수 의존성")
    func nodeIsRequired() {
        let checker = DependencyChecker()
        let node = checker.dependencies.first { $0.name == "Node.js / npm" }
        #expect(node?.isRequired == true)
        #expect(node?.downloadURL == "https://nodejs.org")
        #expect(node?.binaryNames == ["node", "npm"])
    }

    @Test("isChecking - 초기값 false")
    func isCheckingInitial() {
        let checker = DependencyChecker()
        #expect(checker.isChecking == false)
    }

    @Test("checkAll - 실행 후 isChecking은 false")
    func checkAllCompletesWithFalse() async {
        await ProcessRunner.withMock({ _, args, _, _ in
            if args.contains(where: { $0.contains("command -v") }) {
                return (exitCode: 0, stdout: "node:/usr/local/bin/node\nnpm:/usr/local/bin/npm\n", stderr: "")
            }
            return (exitCode: 0, stdout: "", stderr: "")
        }) {
            let checker = DependencyChecker()
            await checker.checkAll()
            #expect(checker.isChecking == false)
        }
    }

    @Test("Dependency - foundPath 초기값 nil")
    func foundPathInitiallyNil() {
        let checker = DependencyChecker()
        for dep in checker.dependencies {
            #expect(dep.foundPath == nil)
        }
    }

    // MARK: - runInstallCommand (크래시 없이 실행되는지 확인)

    @Test("runInstallCommand - 크래시 없이 실행")
    func runInstallCommandNoCrash() async {
        await ProcessRunner.withMock({ _, _, _, _ in
            (exitCode: 0, stdout: "test-install-command\n", stderr: "")
        }) {
            let checker = DependencyChecker()
            checker.runInstallCommand("echo test-install-command")
            // mock이므로 즉시 완료 — 짧은 대기만 필요
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Dependency 구조체

    @Test("Dependency - Identifiable")
    func dependencyIdentifiable() {
        let checker = DependencyChecker()
        let ids = checker.dependencies.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(uniqueIDs.count == ids.count)
    }

    @Test("Dependency - isFound 설정 가능")
    func dependencyIsFoundSettable() {
        let checker = DependencyChecker()
        checker.dependencies[0].isFound = true
        checker.dependencies[0].foundPath = "/test/path"
        #expect(checker.dependencies[0].isFound == true)
        #expect(checker.dependencies[0].foundPath == "/test/path")
    }
}
