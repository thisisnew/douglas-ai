import Foundation

/// 복명복창(Clarify) 단계의 컨텍스트 데이터
struct ClarifyContext: Codable {
    var intakeData: IntakeData?
    var clarifySummary: String?
    var clarifyQuestionCount: Int
    var assumptions: [WorkflowAssumption]?
    var userAnswers: [UserAnswer]?
    var delegationInfo: DelegationInfo?
    var playbook: ProjectPlaybook?

    init(
        intakeData: IntakeData? = nil,
        clarifySummary: String? = nil,
        clarifyQuestionCount: Int = 0,
        assumptions: [WorkflowAssumption]? = nil,
        userAnswers: [UserAnswer]? = nil,
        delegationInfo: DelegationInfo? = nil,
        playbook: ProjectPlaybook? = nil
    ) {
        self.intakeData = intakeData
        self.clarifySummary = clarifySummary
        self.clarifyQuestionCount = clarifyQuestionCount
        self.assumptions = assumptions
        self.userAnswers = userAnswers
        self.delegationInfo = delegationInfo
        self.playbook = playbook
    }

    // MARK: - 도메인 메서드

    mutating func setIntakeData(_ data: IntakeData) { intakeData = data }
    mutating func setPlaybook(_ pb: ProjectPlaybook) { playbook = pb }
    mutating func setClarifySummary(_ summary: String?) { clarifySummary = summary }
    mutating func setDelegationInfo(_ info: DelegationInfo?) { delegationInfo = info }
}
