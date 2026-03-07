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
}
