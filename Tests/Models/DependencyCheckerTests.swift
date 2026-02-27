import Testing
import Foundation
@testable import DOUGLAS

@Suite("DependencyChecker Tests")
@MainActor
struct DependencyCheckerTests {

    @Test("init - 기본 의존성 목록 로드")
    func initLoadsDependencies() {
        let checker = DependencyChecker()
        #expect(checker.dependencies.count == 3)
        #expect(checker.dependencies[0].name == "Node.js / npm")
        #expect(checker.dependencies[1].name == "Git")
        #expect(checker.dependencies[2].name == "Homebrew")
    }

    @Test("allRequiredFound - 모두 미발견 시 false")
    func allRequiredFoundInitiallyFalse() {
        let checker = DependencyChecker()
        #expect(checker.allRequiredFound == false)
    }

    @Test("allRequiredFound - 필수만 발견 시 true")
    func allRequiredFoundWhenRequired() {
        let checker = DependencyChecker()
        // Node.js와 Git만 found로 표시 (Homebrew는 선택)
        for i in checker.dependencies.indices {
            if checker.dependencies[i].isRequired {
                checker.dependencies[i].isFound = true
            }
        }
        #expect(checker.allRequiredFound == true)
    }

    @Test("allRequiredFound - 선택 의존성은 영향 없음")
    func optionalDoesNotAffectRequired() {
        let checker = DependencyChecker()
        // 필수만 found로 표시, Homebrew는 미발견
        for i in checker.dependencies.indices {
            if checker.dependencies[i].isRequired {
                checker.dependencies[i].isFound = true
            }
        }
        // Homebrew는 isRequired == false이므로 미발견이어도 allRequiredFound
        let homebrew = checker.dependencies.first { $0.name == "Homebrew" }
        #expect(homebrew?.isRequired == false)
        #expect(homebrew?.isFound == false)
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

    @Test("Git - 선택 의존성, installHint 포함")
    func gitIsOptional() {
        let checker = DependencyChecker()
        let git = checker.dependencies.first { $0.name == "Git" }
        #expect(git?.isRequired == false)
        #expect(git?.installHint == "xcode-select --install")
        #expect(git?.downloadURL == nil)
    }

    @Test("Homebrew - 선택 의존성")
    func homebrewIsOptional() {
        let checker = DependencyChecker()
        let brew = checker.dependencies.first { $0.name == "Homebrew" }
        #expect(brew?.isRequired == false)
        #expect(brew?.downloadURL == "https://brew.sh")
    }

    @Test("isChecking - 초기값 false")
    func isCheckingInitial() {
        let checker = DependencyChecker()
        #expect(checker.isChecking == false)
    }

    @Test("checkAll - 실행 후 isChecking은 false")
    func checkAllCompletesWithFalse() async {
        let checker = DependencyChecker()
        await checker.checkAll()
        #expect(checker.isChecking == false)
    }

    @Test("checkAll - Git은 대부분의 macOS에 설치되어 있음")
    func checkAllFindsGit() async {
        let checker = DependencyChecker()
        await checker.checkAll()
        let git = checker.dependencies.first { $0.name == "Git" }
        // macOS에는 기본적으로 /usr/bin/git이 있음
        #expect(git?.isFound == true)
    }

    @Test("Dependency - foundPath 초기값 nil")
    func foundPathInitiallyNil() {
        let checker = DependencyChecker()
        for dep in checker.dependencies {
            #expect(dep.foundPath == nil)
        }
    }
}
