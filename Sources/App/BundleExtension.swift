import Foundation

extension Bundle {
    /// Bundle.module 대체 — .app 번들 배포 시에도 안전하게 리소스 번들을 찾는다.
    /// SPM 자동생성 Bundle.module은 .app 내 경로를 올바르게 탐색하지 못해 fatalError 발생.
    static let appModule: Bundle? = {
        let bundleNames = ["DOUGLAS_DOUGLAS", "DOUGLAS_DOUGLASLib"]

        for name in bundleNames {
            // 1. SPM 기본 (swift run, 빌드 디렉토리 실행 시)
            let mainPath = Bundle.main.bundleURL
                .appendingPathComponent("\(name).bundle").path
            if let b = Bundle(path: mainPath) { return b }

            // 2. .app 번들 Contents/Resources/ 내부
            if let resourceURL = Bundle.main.resourceURL {
                let appPath = resourceURL
                    .appendingPathComponent("\(name).bundle").path
                if let b = Bundle(path: appPath) { return b }
            }

            // 3. 실행 파일 옆 (Contents/MacOS/)
            if let execURL = Bundle.main.executableURL?.deletingLastPathComponent() {
                let execPath = execURL
                    .appendingPathComponent("\(name).bundle").path
                if let b = Bundle(path: execPath) { return b }
            }
        }

        return nil
    }()
}
