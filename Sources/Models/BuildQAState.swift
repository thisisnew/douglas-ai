import Foundation

/// 빌드/QA 루프 상태 그룹
struct BuildQAState: Codable {
    var buildLoopStatus: BuildLoopStatus?
    var buildRetryCount: Int
    var maxBuildRetries: Int
    var lastBuildResult: BuildResult?
    var qaLoopStatus: QALoopStatus?
    var qaRetryCount: Int
    var maxQARetries: Int
    var lastQAResult: QAResult?

    init(
        buildLoopStatus: BuildLoopStatus? = nil,
        buildRetryCount: Int = 0,
        maxBuildRetries: Int = 3,
        lastBuildResult: BuildResult? = nil,
        qaLoopStatus: QALoopStatus? = nil,
        qaRetryCount: Int = 0,
        maxQARetries: Int = 3,
        lastQAResult: QAResult? = nil
    ) {
        self.buildLoopStatus = buildLoopStatus
        self.buildRetryCount = buildRetryCount
        self.maxBuildRetries = maxBuildRetries
        self.lastBuildResult = lastBuildResult
        self.qaLoopStatus = qaLoopStatus
        self.qaRetryCount = qaRetryCount
        self.maxQARetries = maxQARetries
        self.lastQAResult = lastQAResult
    }

    // MARK: - 도메인 메서드

    mutating func startBuildLoop() { buildLoopStatus = .building; buildRetryCount = 0 }
    mutating func recordBuildSuccess(result: BuildResult) { buildLoopStatus = .passed; lastBuildResult = result }
    mutating func recordBuildFailure(result: BuildResult) { buildRetryCount += 1; lastBuildResult = result; buildLoopStatus = .fixing }
    mutating func markBuildFailed() { buildLoopStatus = .failed }
    mutating func startQALoop() { qaLoopStatus = .testing; qaRetryCount = 0 }
    mutating func recordQASuccess(result: QAResult) { qaLoopStatus = .passed; lastQAResult = result }
    mutating func recordQAFailure(result: QAResult) { qaRetryCount += 1; lastQAResult = result; qaLoopStatus = .analyzing }
    mutating func markQAFailed() { qaLoopStatus = .failed }
    mutating func resetBuild() { buildLoopStatus = nil; buildRetryCount = 0; lastBuildResult = nil }
    mutating func resetQA() { qaLoopStatus = nil; qaRetryCount = 0; lastQAResult = nil }
}
