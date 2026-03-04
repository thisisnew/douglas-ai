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
        ]
    }

    // MARK: - 전체 체크

    func checkAll() async {
        isChecking = true

        // 1단계: 하드코딩 경로 즉시 체크 (GUI 앱에서도 안정적)
        for i in dependencies.indices {
            let (f, p) = findAnyBinary(dependencies[i].binaryNames)
            dependencies[i].isFound = f
            dependencies[i].foundPath = p
        }

        // 2단계: 로그인 셸 탐색으로 보충 (3초 타임아웃)
        let allNames = dependencies.flatMap(\.binaryNames)
        let shellResults = await Self.shellWhichAll(allNames)

        for i in dependencies.indices {
            if !dependencies[i].isFound {
                for name in dependencies[i].binaryNames {
                    if let path = shellResults[name] {
                        dependencies[i].isFound = true
                        dependencies[i].foundPath = path
                        break
                    }
                }
            }
        }

        isChecking = false
    }

    // MARK: - 설치 명령 실행

    /// installHint 명령 실행 (예: "xcode-select --install")
    func runInstallCommand(_ command: String) {
        Task {
            _ = await ProcessRunner.run(
                executable: "/bin/zsh",
                args: ["-l", "-c", command]
            )
        }
    }

    // MARK: - 로그인 셸 탐색

    /// 여러 바이너리를 한 번의 로그인 셸 호출로 탐색 (백그라운드, 3초 타임아웃)
    private static func shellWhichAll(_ names: [String]) async -> [String: String] {
        await withTaskGroup(of: [String: String].self) { group in
            // 실제 탐색
            group.addTask {
                let script = names.map { "echo \"\($0):$(command -v \($0) 2>/dev/null)\"" }.joined(separator: "; ")
                let processResult = await ProcessRunner.run(
                    executable: "/bin/zsh",
                    args: ["-l", "-c", script]
                )

                var result: [String: String] = [:]
                for line in processResult.stdout.components(separatedBy: "\n") {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let name = String(parts[0])
                        let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
                        if !path.isEmpty {
                            result[name] = path
                        }
                    }
                }
                return result
            }
            // 3초 타임아웃
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return [:]
            }
            let first = await group.next() ?? [:]
            group.cancelAll()
            return first
        }
    }

    // MARK: - 하드코딩 경로 폴백

    private func findAnyBinary(_ names: [String]) -> (Bool, String?) {
        for name in names {
            if let path = findExecutable(name) {
                return (true, path)
            }
        }
        return (false, nil)
    }

    private func findExecutable(_ name: String) -> String? {
        let homePath = NSHomeDirectory()
        let extras = [
            "/usr/bin/\(name)",
            "\(homePath)/.volta/bin/\(name)",
            "\(homePath)/.local/bin/\(name)",
        ]
        return ShellEnvironment.findExecutable(name, extraCandidates: extras)
    }
}
