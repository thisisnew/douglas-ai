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

        // 로그인 셸에서 모든 바이너리를 한 번에 탐색 (GUI 앱은 PATH 제한적)
        let allNames = dependencies.flatMap(\.binaryNames)
        let shellResults = await Self.shellWhichAll(allNames)

        for i in dependencies.indices {
            var found = false
            var foundPath: String?

            // 1. 로그인 셸 which 결과
            for name in dependencies[i].binaryNames {
                if let path = shellResults[name] {
                    found = true
                    foundPath = path
                    break
                }
            }

            // 2. 하드코딩 경로 폴백
            if !found {
                let (f, p) = findAnyBinary(dependencies[i].binaryNames)
                found = f
                foundPath = p
            }

            dependencies[i].isFound = found
            dependencies[i].foundPath = foundPath
        }
        isChecking = false
    }

    // MARK: - 설치 명령 실행

    /// installHint 명령 실행 (예: "xcode-select --install")
    func runInstallCommand(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
        }
    }

    // MARK: - 로그인 셸 탐색

    /// 여러 바이너리를 한 번의 로그인 셸 호출로 탐색 (백그라운드)
    private static func shellWhichAll(_ names: [String]) async -> [String: String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = names.map { "echo \"\($0):$(command -v \($0) 2>/dev/null)\"" }.joined(separator: "; ")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", script]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                var result: [String: String] = [:]
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    for line in output.components(separatedBy: "\n") {
                        let parts = line.split(separator: ":", maxSplits: 1)
                        if parts.count == 2 {
                            let name = String(parts[0])
                            let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
                            if !path.isEmpty {
                                result[name] = path
                            }
                        }
                    }
                } catch {}
                continuation.resume(returning: result)
            }
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
        var candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(homePath)/.volta/bin/\(name)",
            "\(homePath)/.local/bin/\(name)",
        ]

        // nvm 버전별 경로 추가
        let nvmDir = "\(homePath)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                candidates.insert("\(nvmDir)/\(version)/bin/\(name)", at: 0)
            }
        }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
