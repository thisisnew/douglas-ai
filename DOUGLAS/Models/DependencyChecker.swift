import Foundation

/// 온보딩에서 필수/선택 의존성을 확인하는 체커
@MainActor
class DependencyChecker: ObservableObject {

    struct Dependency: Identifiable {
        let id = UUID()
        let name: String           // "Node.js / npm"
        let binaryNames: [String]  // ["node", "npm"]
        let isRequired: Bool
        let downloadURL: String?
        let installHint: String?   // "xcode-select --install"
        var isFound: Bool = false
        var foundPath: String?
    }

    @Published var dependencies: [Dependency] = []
    @Published var isChecking = false

    /// 모든 필수 의존성이 설치되어 있는지
    var allRequiredFound: Bool {
        dependencies.filter(\.isRequired).allSatisfy(\.isFound)
    }

    init() {
        dependencies = Self.defaultDependencies
    }

    // MARK: - 기본 의존성 목록

    private static var defaultDependencies: [Dependency] {
        [
            Dependency(
                name: "Node.js / npm",
                binaryNames: ["node", "npm"],
                isRequired: true,
                downloadURL: "https://nodejs.org",
                installHint: nil
            ),
            Dependency(
                name: "Git",
                binaryNames: ["git"],
                isRequired: false,
                downloadURL: nil,
                installHint: "xcode-select --install"
            ),
            Dependency(
                name: "Homebrew",
                binaryNames: ["brew"],
                isRequired: false,
                downloadURL: "https://brew.sh",
                installHint: nil
            ),
        ]
    }

    // MARK: - 전체 체크

    func checkAll() async {
        isChecking = true
        for i in dependencies.indices {
            let (found, path) = findAnyBinary(dependencies[i].binaryNames)
            dependencies[i].isFound = found
            dependencies[i].foundPath = path
        }
        isChecking = false
    }

    // MARK: - 바이너리 탐색

    private func findAnyBinary(_ names: [String]) -> (Bool, String?) {
        for name in names {
            if let path = findExecutable(name) {
                return (true, path)
            }
        }
        return (false, nil)
    }

    /// ClaudeCodeInstaller와 동일한 패턴: 다양한 경로에서 실행 파일 탐색
    private func findExecutable(_ name: String) -> String? {
        let homePath = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(homePath)/.nvm/current/bin/\(name)",
            "\(homePath)/.volta/bin/\(name)",
            "\(homePath)/.local/bin/\(name)",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
