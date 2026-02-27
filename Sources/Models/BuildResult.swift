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

// MARK: - QA 결과 + 상태 (Phase C-3)

/// 테스트 실행 결과
struct QAResult: Codable {
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

/// QA 루프 상태
enum QALoopStatus: String, Codable {
    case idle       // QA 루프 비활성
    case testing    // 테스트 실행 중
    case analyzing  // 에이전트가 실패 분석/수정 중
    case passed     // 테스트 통과
    case failed     // 최대 재시도 초과로 실패
}
