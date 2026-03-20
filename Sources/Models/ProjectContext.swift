import Foundation

/// 프로젝트 연동 컨텍스트 (경로, 빌드/테스트 명령)
struct ProjectContext: Codable, Equatable {
    var projectPaths: [String]
    var worktreePath: String?
    var buildCommand: String?
    var testCommand: String?

    init(
        projectPaths: [String] = [],
        worktreePath: String? = nil,
        buildCommand: String? = nil,
        testCommand: String? = nil
    ) {
        self.projectPaths = projectPaths
        self.worktreePath = worktreePath
        self.buildCommand = buildCommand
        self.testCommand = testCommand
    }

    mutating func setWorktreePath(_ path: String?) { worktreePath = path }
}
