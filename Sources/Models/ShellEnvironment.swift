import Foundation

/// 셸 실행에 필요한 환경(PATH 등)을 캐싱하여 반복적인 파일시스템 탐색을 제거
enum ShellEnvironment {

    // MARK: - 캐싱된 NVM 경로

    /// nvm 노드 버전별 bin 경로 (최신 버전 우선, 앱 실행 중 1회만 계산)
    static let nvmBinPaths: [String] = {
        let homePath = NSHomeDirectory()
        let nvmDir = "\(homePath)/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) else {
            return []
        }
        let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        return sorted.map { "\(nvmDir)/\($0)/bin" }
    }()

    /// 셸 실행용 추가 PATH 목록 (nvm + homebrew + usr/local)
    static let additionalPaths: [String] = {
        nvmBinPaths + ["/opt/homebrew/bin", "/usr/local/bin"]
    }()

    // MARK: - 환경 변수 구성

    /// 현재 프로세스 환경에 추가 PATH를 병합한 환경 변수 반환
    static func mergedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let existingPath = env["PATH"] {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath
        }
        return env
    }

    // MARK: - 실행 파일 탐색

    /// 지정 이름의 실행 파일을 캐싱된 경로에서 탐색
    static func findExecutable(_ name: String, extraCandidates: [String] = []) -> String? {
        let candidates = extraCandidates + nvmBinPaths.map { "\($0)/\(name)" } + [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
