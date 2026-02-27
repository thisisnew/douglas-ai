import Foundation

/// 빌드 실행 결과
struct BuildResult: Codable {
    let success: Bool
    let output: String
    let exitCode: Int32
    let timestamp: Date

    init(success: Bool, output: String, exitCode: Int32, timestamp: Date = Date()) {
        self.success = success
        self.output = output
        self.exitCode = exitCode
        self.timestamp = timestamp
    }
}

/// 빌드 루프 상태
enum BuildLoopStatus: String, Codable {
    case idle       // 빌드 루프 비활성
    case building   // 빌드 실행 중
    case fixing     // 에이전트가 오류 수정 중
    case passed     // 빌드 성공
    case failed     // 최대 재시도 초과로 실패
}
